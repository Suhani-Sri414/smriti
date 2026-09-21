import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smriti/core/ability/estimator.dart';
import 'package:smriti/core/db/database.dart';
import 'package:smriti/core/repo/ability_repo.dart';
import 'package:smriti/core/repo/event_repo.dart';
import 'package:smriti/games/cognitive_game.dart';
import 'package:smriti/games/ghost_hand.dart';
import 'package:smriti/games/market_basket/market_basket_game.dart';
import 'package:smriti/games/session_runner.dart';

import '../core/repo/_test_db.dart';

/// Loads the same mock content JSON the app ships, straight off disk so the
/// test needs no asset bundle.
GameContent loadMockContent() {
  final file = File('assets/mock_content/mock_content.json');
  expect(file.existsSync(), isTrue,
      reason: 'mock content JSON missing at ${file.path}');
  return GameContent.fromJson(
    jsonDecode(file.readAsStringSync()) as Map<String, Object?>,
  );
}

void main() {
  late SmritiDatabase db;
  late EventRepo eventRepo;
  late AbilityRepo abilityRepo;
  late GameContent content;
  late MarketBasketGame game;

  /// A clock the test drives by hand, so cap and timestamp assertions are exact.
  late DateTime clock;
  DateTime now() => clock;

  setUp(() async {
    db = newTestDb();
    eventRepo = EventRepo(db);
    abilityRepo = AbilityRepo(db);
    content = loadMockContent();
    game = MarketBasketGame(random: Random(7));
    // 2025-09-07 09:30 local.
    clock = DateTime(2025, 9, 7, 9, 30);
    await db.appConfigsDao.setValue(AbilityRepo.ageKey, '76');
    await db.appConfigsDao.setValue(AbilityRepo.educationYearsKey, '8');
  });

  tearDown(() async {
    await game.dispose();
    await db.close();
  });

  SessionRunner newRunner() => SessionRunner(
        eventRepo: eventRepo,
        abilityRepo: abilityRepo,
        content: content,
        now: now,
      );

  /// Plays one trial and waits for the runner to finish persisting it.
  Future<void> playTrial(
    SessionRunner runner,
    GameItem item, {
    required List<String> chosenIds,
    int initiationMs = 900,
    int movementMs = 1400,
  }) async {
    final written = runner.feedback.first;
    game.submit(
      item: item,
      chosenIds: chosenIds,
      initiationMs: initiationMs,
      movementMs: movementMs,
    );
    await written;
  }

  List<String> targetsOf(GameItem item) =>
      (item.context['targetIds']! as List<Object?>).cast<String>();

  test('a correct trial populates every TrialEvents column and moves ability',
      () async {
    final runner = newRunner();
    final sessionId = await runner.start([game]);

    final seeded = await abilityRepo.getOrSeed(CognitiveDomain.memory);
    final expectedDifficulty =
        AbilityEstimator.nextDifficulty(seeded.theta);

    final item = await runner.nextItem(game);
    expect(item, isNotNull);
    expect(item!.difficulty, closeTo(expectedDifficulty, 1e-12));

    clock = clock.add(const Duration(seconds: 12));
    await playTrial(runner, item, chosenIds: targetsOf(item));

    final rows = await eventRepo.getTrialsForSession(sessionId);
    expect(rows, hasLength(1));
    final t = rows.single;

    // 1-4: identity and provenance.
    expect(t.id, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-'
        r'[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    expect(t.sessionId, sessionId);
    expect(t.gameId, 'market_basket');
    expect(t.domain, 'memory');

    // 5-7: the item and the estimate it was chosen from.
    expect(t.itemId, item.id);
    expect(t.itemId, startsWith('mb_'));
    expect(t.itemDifficulty, closeTo(expectedDifficulty, 1e-12));
    expect(t.thetaBefore, closeTo(seeded.theta, 1e-12));

    // 8: outcome.
    expect(t.correct, isTrue);

    // 9-11: timing, with responseTimeMs the sum of its parts.
    expect(t.initiationMs, 900);
    expect(t.movementMs, 1400);
    expect(t.responseTimeMs, 2300);

    // 12-13: nothing was picked wrongly, so these are legitimately null.
    expect(t.chosenId, isNull);
    expect(t.errorClass, isNull);

    // 14-16: position and context.
    expect(t.trialIndex, 0);
    final ctx = jsonDecode(t.trialContext!) as Map<String, Object?>;
    expect(ctx['listLength'], isA<int>());
    expect(ctx['shelfSize'], greaterThan(ctx['listLength']! as int));
    expect(ctx['targetIds'], targetsOf(item));
    expect(ctx['contentVersion'], 'mock-1');
    expect(t.hintLevel, 0);

    // 17: game metrics.
    final metrics = jsonDecode(t.metrics!) as Map<String, Object?>;
    expect(metrics['missed'], 0);
    expect(metrics['intrusions'], 0);
    expect(metrics['repeats'], 0);
    expect(metrics['picked'], targetsOf(item).length);

    // 18-20: time of day, which the report pipeline slices on.
    expect(t.ts, clock.millisecondsSinceEpoch);
    expect(t.hourOfDay, 9);
    expect(t.tzOffsetMin, clock.timeZoneOffset.inMinutes);

    // 21: written locally, not yet pushed.
    expect(t.synced, isFalse);

    // Every other column is populated - only the two wrong-answer columns are
    // null, and only because this answer was right.
    final populated = t.toJson()
      ..remove('chosenId')
      ..remove('errorClass');
    expect(populated.values.where((v) => v == null), isEmpty);
    expect(populated, hasLength(19));

    // AbilityStates moved for this domain, and only this domain.
    final after = await abilityRepo.getRecord(CognitiveDomain.memory);
    expect(after, isNotNull);
    expect(after!.nTrials, 1);
    expect(after.theta, greaterThan(seeded.theta));
    expect(after.rtMeanLog, isNot(closeTo(seeded.rtMeanLog, 1e-9)));
    expect(await abilityRepo.getUpdatedAt(CognitiveDomain.memory),
        clock.millisecondsSinceEpoch);
    expect(await abilityRepo.getRecord(CognitiveDomain.attention), isNull);

    await runner.end(completed: true);
  });

  test('an incorrect trial fills chosenId and errorClass, and lowers theta',
      () async {
    final runner = newRunner();
    final sessionId = await runner.start([game]);

    final seeded = await abilityRepo.getOrSeed(CognitiveDomain.memory);
    final item = (await runner.nextItem(game))!;

    // Pick one thing that was never on the list.
    final targets = targetsOf(item);
    final shelf = (item.payload['shelf']! as List<Object?>).cast<MarketItem>();
    final intruder =
        shelf.firstWhere((i) => !targets.contains(i.id));

    await playTrial(
      runner,
      item,
      chosenIds: [...targets, intruder.id],
      initiationMs: 1500,
      movementMs: 2600,
    );

    final t = (await eventRepo.getTrialsForSession(sessionId)).single;
    expect(t.correct, isFalse);
    expect(t.chosenId, intruder.id);
    expect(t.errorClass, anyOf('semantic_near', 'semantic_far'));
    expect(t.responseTimeMs, 4100);

    final metrics = jsonDecode(t.metrics!) as Map<String, Object?>;
    expect(metrics['intrusions'], 1);
    expect(metrics['missed'], 0);

    // Every column populated on the error path too.
    expect(t.toJson().values.where((v) => v == null), isEmpty);

    final after = await abilityRepo.getRecord(CognitiveDomain.memory);
    expect(after!.nTrials, 1);
    expect(after.theta, lessThan(seeded.theta));

    await runner.end(completed: true);
  });

  test('omission is classified when the elder picks too few', () async {
    final runner = newRunner();
    final sessionId = await runner.start([game]);
    final item = (await runner.nextItem(game))!;
    final targets = targetsOf(item);

    await playTrial(runner, item, chosenIds: targets.take(1).toList());

    final t = (await eventRepo.getTrialsForSession(sessionId)).single;
    expect(t.correct, isFalse);
    expect(t.errorClass, 'omission');
    expect(t.chosenId, isNotNull);
    expect(jsonDecode(t.metrics!)['missed'], targets.length - 1);

    await runner.end(completed: true);
  });

  test('trials index sequentially and difficulty tracks the estimate',
      () async {
    final runner = newRunner();
    final sessionId = await runner.start([game]);

    final difficulties = <double>[];
    for (var i = 0; i < 5; i++) {
      final item = (await runner.nextItem(game))!;
      difficulties.add(item.difficulty);
      clock = clock.add(const Duration(seconds: 10));
      await playTrial(runner, item, chosenIds: targetsOf(item));
    }

    final rows = await eventRepo.getTrialsForSession(sessionId);
    expect(rows.map((r) => r.trialIndex), [0, 1, 2, 3, 4]);
    expect(rows.map((r) => r.id).toSet(), hasLength(5));

    // All correct, so the estimate rises and items get harder.
    expect(difficulties.last, greaterThan(difficulties.first));
    for (var i = 0; i < rows.length; i++) {
      expect(rows[i].itemDifficulty, closeTo(difficulties[i], 1e-12));
    }

    final ability = await abilityRepo.getRecord(CognitiveDomain.memory);
    expect(ability!.nTrials, 5);

    await runner.end(completed: true);
  });

  test('the 6-minute cap stops handing out items', () async {
    final runner = newRunner();
    await runner.start([game]);

    expect(runner.canContinue, isTrue);
    expect(await runner.nextItem(game), isNotNull);

    clock = clock.add(const Duration(minutes: 5, seconds: 59));
    expect(runner.isCapReached, isFalse);
    expect(await runner.nextItem(game), isNotNull);

    clock = clock.add(const Duration(seconds: 1));
    expect(runner.isCapReached, isTrue);
    expect(runner.canContinue, isFalse);
    expect(await runner.nextItem(game), isNull);

    await runner.end();
    final session = await eventRepo.getSession(runner.sessionId!);
    expect(session!.completed, isTrue);
    expect(session.endedAt, clock.millisecondsSinceEpoch);
    expect(session.abandonedAtMs, isNull);
  });

  test('walking away early records abandonment rather than completion',
      () async {
    final runner = newRunner();
    await runner.start([game]);
    final item = (await runner.nextItem(game))!;
    await playTrial(runner, item, chosenIds: targetsOf(item));

    clock = clock.add(const Duration(minutes: 2));
    await runner.end(completed: false);

    final session = await eventRepo.getSession(runner.sessionId!);
    expect(session!.completed, isFalse);
    expect(session.abandonedAtMs, const Duration(minutes: 2).inMilliseconds);
  });

  test('feedback is never negative, even on a wrong answer', () async {
    final runner = newRunner();
    await runner.start([game]);

    final cues = <TrialFeedback>[];
    final sub = runner.feedback.listen(cues.add);

    final first = (await runner.nextItem(game))!;
    await playTrial(runner, first, chosenIds: targetsOf(first));

    final second = (await runner.nextItem(game))!;
    await playTrial(runner, second, chosenIds: const []);

    await sub.cancel();

    expect(cues, hasLength(2));
    expect(cues.first.tone, FeedbackTone.praise);
    expect(cues.first.phrase, PhraseKey.wellDone);

    // The incorrect trial gets a neutral invitation, never a correction.
    expect(cues.last.tone, FeedbackTone.neutral);
    expect(cues.last.phrase, PhraseKey.tryAnother);

    // There is no negative tone to reach for in the first place.
    expect(FeedbackTone.values, [FeedbackTone.praise, FeedbackTone.neutral]);

    await runner.end(completed: true);
  });

  test('hints escalate, cap out, and reset on the next item', () async {
    final runner = newRunner();
    final sessionId = await runner.start([game]);

    final item = (await runner.nextItem(game))!;
    expect(runner.hintLevel, 0);
    expect(runner.escalateHint(), 1);
    expect(runner.escalateHint(), 2);
    expect(runner.escalateHint(), 2, reason: 'capped at maxHintLevel');

    await playTrial(runner, item, chosenIds: targetsOf(item));

    final next = (await runner.nextItem(game))!;
    expect(runner.hintLevel, 0, reason: 'hints reset per item');
    await playTrial(runner, next, chosenIds: targetsOf(next));

    final rows = await eventRepo.getTrialsForSession(sessionId);
    expect(rows.map((r) => r.hintLevel), [2, 0]);

    await runner.end(completed: true);
  });

  testWidgets('replaying the demo increments demoReplays on the session row',
      (WidgetTester tester) async {
    // A real BuildContext, since CognitiveGame.playDemo takes one per §11.
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (ctx) {
            context = ctx;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    // The ghost hand waits on a real timer, so this runs outside fake-async.
    final demoGame = MarketBasketGame(
      random: Random(7),
      ghostHand: GhostHandController(
        stepDuration: const Duration(milliseconds: 1),
      ),
    );
    addTearDown(demoGame.dispose);

    final runner = newRunner();
    late String sessionId;

    await tester.runAsync(() async {
      sessionId = await runner.start([demoGame]);

      await runner.playIntroDemo(context, demoGame);
      expect((await eventRepo.getSession(sessionId))!.demoReplays, 0,
          reason: 'the first demo is not a replay');

      await runner.replayDemo(context, demoGame);
      await runner.replayDemo(context, demoGame);

      expect((await eventRepo.getSession(sessionId))!.demoReplays, 2);
      expect(demoGame.ghostHand.completedRuns, 3);

      await runner.end(completed: true);
    });
  });

  test('the session row itself is written and closed exactly once', () async {
    final runner = newRunner();
    final sessionId = await runner.start([game]);

    final open = await eventRepo.getSession(sessionId);
    expect(open!.gameIds, 'market_basket');
    expect(open.startedAt, clock.millisecondsSinceEpoch);
    expect(open.endedAt, isNull);
    expect(open.synced, isFalse);

    expect(() => runner.start([game]), throwsStateError);

    clock = clock.add(const Duration(minutes: 3));
    await runner.end(completed: true);
    final firstEnd = (await eventRepo.getSession(sessionId))!.endedAt;

    clock = clock.add(const Duration(minutes: 5));
    await runner.end(completed: false);
    expect((await eventRepo.getSession(sessionId))!.endedAt, firstEnd);

    // Everything the sync layer needs is queued.
    expect(await eventRepo.unsyncedSessions(), hasLength(1));
  });

  test('runner.end() without arguments defaults to completed = true', () async {
    final runner = newRunner();
    final sessionId = await runner.start([game]);

    clock = clock.add(const Duration(minutes: 2));
    await runner.end();

    final session = await eventRepo.getSession(sessionId);
    expect(session, isNotNull);
    expect(session!.completed, isTrue);
    expect(session.endedAt, clock.millisecondsSinceEpoch);
    expect(session.abandonedAtMs, isNull);
  });
}
