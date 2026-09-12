import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';

import '../core/ability/estimator.dart';
import '../core/db/database.dart';
import '../core/repo/ability_repo.dart';
import '../core/repo/event_repo.dart';
import '../core/voice/phrase_player.dart';
import 'cognitive_game.dart';

/// Tone of the cue shown or played after a trial.
///
/// There is deliberately no negative value. AGENTS.md non-negotiable #11: the
/// app never says "wrong", never shows red, and never plays a negative sound.
/// An incorrect answer is [neutral] - the card returns silently and play
/// continues.
enum FeedbackTone { praise, neutral }

class TrialFeedback {
  const TrialFeedback({required this.tone, required this.phrase});

  final FeedbackTone tone;
  final PhraseKey phrase;
}

/// Owns everything about a play session that is not the game itself: the
/// 6-minute cap, hint escalation, demo replay counting, the ability update
/// after every trial, and the `TrialEvents` write.
///
/// Games hand it [TrialResult]s and nothing else (AGENTS.md #10).
class SessionRunner {
  SessionRunner({
    required this.eventRepo,
    required this.abilityRepo,
    required this.content,
    this.phrasePlayer,
    Uuid? uuid,
    DateTime Function()? now,
    this.sessionCap = const Duration(minutes: 6),
    this.maxHintLevel = 2,
  })  : _uuid = uuid ?? const Uuid(),
        _now = now ?? DateTime.now;

  final EventRepo eventRepo;
  final AbilityRepo abilityRepo;
  final GameContent content;
  final PhrasePlayer? phrasePlayer;
  final Duration sessionCap;
  final int maxHintLevel;

  final Uuid _uuid;
  final DateTime Function() _now;

  final _feedback = StreamController<TrialFeedback>.broadcast();
  final List<StreamSubscription<TrialResult>> _subscriptions = [];

  /// Cues for the UI and voice layers. Never carries a negative tone.
  Stream<TrialFeedback> get feedback => _feedback.stream;

  String? _sessionId;
  DateTime? _startedAt;
  int _trialIndex = 0;
  int _hintLevel = 0;
  bool _ended = false;

  CognitiveGame? _currentGame;
  GameItem? _currentItem;
  double _thetaBefore = 0;

  String? get sessionId => _sessionId;
  int get trialIndex => _trialIndex;
  int get hintLevel => _hintLevel;
  bool get isRunning => _sessionId != null && !_ended;

  /// The game currently handing out items, if any.
  CognitiveGame? get currentGame => _currentGame;

  Duration get elapsed =>
      _startedAt == null ? Duration.zero : _now().difference(_startedAt!);

  /// True once the 6-minute cap is spent. No further items are handed out.
  bool get isCapReached => elapsed >= sessionCap;

  /// True while there is still time for another trial.
  bool get canContinue => isRunning && !isCapReached;

  /// Opens the session row and starts listening to each game's trial stream.
  Future<String> start(List<CognitiveGame> games) async {
    if (_sessionId != null) {
      throw StateError('Session already started');
    }

    final startedAt = _now();
    final id = _uuid.v4();

    await eventRepo.insertSession(
      SessionsCompanion.insert(
        id: id,
        startedAt: startedAt.millisecondsSinceEpoch,
        gameIds: games.map((g) => g.id).join(','),
      ),
    );

    _sessionId = id;
    _startedAt = startedAt;

    unawaited(
        phrasePlayer?.playPhrase(PhraseKey.sessionStart) ?? Future.value());

    for (final game in games) {
      _subscriptions.add(
        game.trials.listen((result) => _recordTrial(game, result)),
      );
    }

    return id;
  }

  /// Picks the next item's difficulty from the current ability estimate and
  /// asks [game] to generate it. Returns null once the cap is reached.
  Future<GameItem?> nextItem(CognitiveGame game) async {
    if (!canContinue) return null;

    final record = await abilityRepo.getOrSeed(game.primaryDomain);
    _thetaBefore = record.theta;
    _hintLevel = 0;

    final item = game.generateItem(
      AbilityEstimator.nextDifficulty(record.theta),
      content,
    );

    _currentGame = game;
    _currentItem = item;
    return item;
  }

  /// Escalates the hint shown for the current item. Capped, and never framed as
  /// a correction - a hint is help, not a reprimand.
  int escalateHint() {
    if (_hintLevel < maxHintLevel) _hintLevel++;
    return _hintLevel;
  }

  /// First demonstration of a game. Does not count as a replay.
  Future<void> playIntroDemo(BuildContext context, CognitiveGame game) {
    return game.playDemo(context);
  }

  /// The elder asked to see the demo again. Counted on the session row, because
  /// replay frequency is itself a signal in the report pipeline.
  Future<void> replayDemo(BuildContext context, CognitiveGame game) async {
    await game.playDemo(context);
    final id = _sessionId;
    if (id != null && !_ended) {
      await eventRepo.bumpDemoReplays(id);
    }
  }

  /// Writes the trial, updates the ability estimate, and emits a feedback cue.
  Future<void> _recordTrial(CognitiveGame game, TrialResult result) async {
    final sessionId = _sessionId;
    final item = _currentItem;
    if (sessionId == null || _ended || item == null) return;

    final ts = _now();
    final responseTimeMs = result.initiationMs + result.movementMs;

    await eventRepo.insertTrial(
      TrialEventsCompanion.insert(
        id: _uuid.v4(),
        sessionId: sessionId,
        gameId: game.id,
        domain: game.primaryDomain.name,
        itemId: item.id,
        itemDifficulty: result.itemDifficulty,
        thetaBefore: _thetaBefore,
        correct: result.correct,
        initiationMs: result.initiationMs,
        movementMs: result.movementMs,
        responseTimeMs: responseTimeMs,
        chosenId: Value(result.chosenId),
        errorClass: Value(result.errorClass),
        trialIndex: _trialIndex,
        trialContext: Value(jsonEncode(item.context)),
        hintLevel: Value(_hintLevel),
        metrics: Value(jsonEncode(result.metrics)),
        ts: ts.millisecondsSinceEpoch,
        hourOfDay: ts.hour,
        tzOffsetMin: ts.timeZoneOffset.inMinutes,
      ),
    );

    await abilityRepo.applyTrial(
      domain: game.primaryDomain,
      itemDifficulty: result.itemDifficulty,
      correct: result.correct,
      responseTimeMs: responseTimeMs,
      now: ts,
    );

    _trialIndex++;
    _currentItem = null;

    _feedback.add(
      result.correct
          ? const TrialFeedback(
              tone: FeedbackTone.praise,
              phrase: PhraseKey.wellDone,
            )
          // Not a failure cue: same warmth, no red, no "wrong".
          : const TrialFeedback(
              tone: FeedbackTone.neutral,
              phrase: PhraseKey.tryAnother,
            ),
    );
    unawaited(phrasePlayer?.playPhrase(result.correct
            ? PhraseKey.wellDone
            : PhraseKey.tryAnother) ??
        Future.value());
  }

  /// Closes the session. [completed] is false when the elder walked away.
  Future<void> end({bool? completed}) async {
    final id = _sessionId;
    if (id == null || _ended) return;

    _ended = true;
    final endedAt = _now();
    final ranFullLength = completed ?? isCapReached;

    unawaited(phrasePlayer?.playPhrase(PhraseKey.sessionEnd) ?? Future.value());

    await eventRepo.endSession(
      id: id,
      endedAt: endedAt.millisecondsSinceEpoch,
      completed: ranFullLength,
      abandonedAtMs: ranFullLength ? null : elapsed.inMilliseconds,
    );

    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    _currentGame = null;
    await _feedback.close();
  }
}
