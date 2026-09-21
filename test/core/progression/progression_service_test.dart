import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:smriti/core/db/database.dart';
import 'package:smriti/core/progression/play_policy.dart';
import 'package:smriti/core/progression/progression_config.dart';
import 'package:smriti/core/progression/progression_repo.dart';
import 'package:smriti/core/progression/progression_service.dart';
import 'package:smriti/core/progression/progression_state.dart';

import '../repo/_test_db.dart';

void main() {
  late SmritiDatabase db;
  late ProgressionRepo repo;
  late ProgressionService service;

  setUp(() {
    db = newTestDb();
    repo = ProgressionRepo(db);
    service = ProgressionService(repo: repo);
  });

  tearDown(() async {
    await db.close();
  });

  TrialEventsCompanion createTrial({
    required String id,
    required String sessionId,
    required String gameId,
    required String domain,
    required DateTime timestamp,
    bool correct = true,
    int hintLevel = 0,
    String? metrics,
  }) {
    return TrialEventsCompanion.insert(
      id: id,
      sessionId: sessionId,
      gameId: gameId,
      domain: domain,
      itemId: 'item_$id',
      itemDifficulty: 0.0,
      thetaBefore: 1.0,
      correct: correct,
      initiationMs: 800,
      movementMs: 1200,
      responseTimeMs: 2000,
      trialIndex: 0,
      hintLevel: Value(hintLevel),
      metrics: Value(metrics),
      ts: timestamp.millisecondsSinceEpoch,
      hourOfDay: timestamp.hour,
      tzOffsetMin: 0,
    );
  }

  SessionsCompanion createSession({
    required String id,
    required DateTime startedAt,
    DateTime? endedAt,
    String gameIds = 'market_basket',
    bool completed = true,
  }) {
    return SessionsCompanion.insert(
      id: id,
      startedAt: startedAt.millisecondsSinceEpoch,
      endedAt: Value(endedAt?.millisecondsSinceEpoch),
      gameIds: gameIds,
      completed: Value(completed),
    );
  }

  group('ProgressionService - Outer Loop (4-Day Macro Review)', () {
    test('skips games not due for review (< 4 days since last review)', () async {
      final now = DateTime(2026, 9, 20, 12, 0);
      final twoDaysAgo = now.subtract(const Duration(days: 2));

      await repo.saveGameProgress(
        GameProgress(
          gameId: 'market_basket',
          level: 5.0,
          lastReviewTs: twoDaysAgo.millisecondsSinceEpoch,
        ),
      );

      // Add a trial so the game is recognized as played
      await db.into(db.trialEvents).insert(
            createTrial(
              id: 't1',
              sessionId: 's1',
              gameId: 'market_basket',
              domain: 'memory',
              timestamp: now.subtract(const Duration(hours: 1)),
            ),
          );

      final reviews = await service.runDueReviews(currentTime: now);
      expect(reviews, isEmpty);

      // Verify level did not change
      final progress = await repo.getGameProgress('market_basket');
      expect(progress.level, 5.0);
    });

    test('holds without review record when insufficient trials (< 6)', () async {
      final now = DateTime(2026, 9, 20, 12, 0);

      // Insert 4 trials (threshold is 6) across 2 days
      for (int i = 0; i < 4; i++) {
        await db.into(db.trialEvents).insert(
              createTrial(
                id: 't_$i',
                sessionId: 's_$i',
                gameId: 'market_basket',
                domain: 'memory',
                timestamp: now.subtract(Duration(days: i % 2, hours: i + 1)),
                correct: true,
              ),
            );
      }

      final reviews = await service.runDueReviews(currentTime: now);
      expect(reviews, isEmpty);

      final progress = await repo.getGameProgress('market_basket');
      expect(progress.level, 5.0); // Baseline untouched
      expect(progress.lastReviewTs, isNull);
    });

    test('completes 2-phase confirming raise cycle when score >= 0.85 after recent demotion', () async {
      final cycle1Time = DateTime(2026, 9, 20, 12, 0);

      // Seed progress with a recent demotion to activate Anti-Oscillation 2-phase confirmation
      await repo.saveGameProgress(
        GameProgress(
          gameId: 'market_basket',
          level: 5.0,
          reviewHistory: [
            ReviewRecord(
              timestamp: cycle1Time.subtract(const Duration(days: 1)).millisecondsSinceEpoch,
              decision: ReviewDecision.ease,
              levelBefore: 5.5,
              levelAfter: 5.0,
              meanScore: 0.50,
              accuracy: 0.50,
              hintRate: 0.0,
              totalTrials: 8,
            ),
          ],
        ),
      );

      // Cycle 1: 8 trials across 3 days, 100% correct, 0 hints -> score 1.0
      for (int i = 0; i < 8; i++) {
        await db.into(db.trialEvents).insert(
              createTrial(
                id: 'c1_t_$i',
                sessionId: 'c1_s_$i',
                gameId: 'market_basket',
                domain: 'memory',
                timestamp: cycle1Time.subtract(Duration(days: i % 3, hours: i + 1)),
                correct: true,
                hintLevel: 0,
              ),
            );
      }

      // First evaluation: Needs confirming cycle due to anti-oscillation, so decision is HOLD
      final reviews1 = await service.runDueReviews(currentTime: cycle1Time);
      expect(reviews1, hasLength(1));
      expect(reviews1.single.decision, ReviewDecision.hold);
      expect(reviews1.single.levelBefore, 5.0);
      expect(reviews1.single.levelAfter, 5.0);

      var progress = await repo.getGameProgress('market_basket');
      expect(progress.level, 5.0);
      expect(progress.consecutiveRaiseQualifyingCount, 1);
      expect(progress.reviewHistory, hasLength(2));

      // Cycle 2: 4 days later, another 8 perfect trials
      final cycle2Time = cycle1Time.add(const Duration(days: 4));
      for (int i = 0; i < 8; i++) {
        await db.into(db.trialEvents).insert(
              createTrial(
                id: 'c2_t_$i',
                sessionId: 'c2_s_$i',
                gameId: 'market_basket',
                domain: 'memory',
                timestamp: cycle2Time.subtract(Duration(days: i % 3, hours: i + 1)),
                correct: true,
                hintLevel: 0,
              ),
            );
      }

      // Second evaluation: Confirming cycle met -> RAISE with anti-oscillation throttling (+0.5)
      final reviews2 = await service.runDueReviews(currentTime: cycle2Time);
      expect(reviews2, hasLength(1));
      expect(reviews2.single.decision, ReviewDecision.raise);
      expect(reviews2.single.throttled, isTrue);
      expect(reviews2.single.levelBefore, 5.0);
      expect(reviews2.single.levelAfter, 5.5);

      progress = await repo.getGameProgress('market_basket');
      expect(progress.level, 5.5);
      expect(progress.consecutiveRaiseQualifyingCount, 0); // reset after raise
      expect(progress.reviewHistory, hasLength(3));
    });

    test('eases level on poor performance and detects clinical concern on drop >= 30%', () async {
      final now = DateTime(2026, 9, 20, 12, 0);

      // Start at level 6.0 with a high previous score (0.90)
      await repo.saveGameProgress(
        GameProgress(
          gameId: 'trace_path',
          level: 6.0,
          lastReviewScore: 0.90,
          lastReviewTs: now.subtract(const Duration(days: 5)).millisecondsSinceEpoch,
        ),
      );

      // Insert 8 trials with very low accuracy (25% correct -> mean score 0.25)
      for (int i = 0; i < 8; i++) {
        await db.into(db.trialEvents).insert(
              createTrial(
                id: 'low_t_$i',
                sessionId: 'low_s_$i',
                gameId: 'trace_path',
                domain: 'visuospatial',
                timestamp: now.subtract(Duration(days: i % 2, hours: i + 1)),
                correct: i < 2, // 2/8 = 0.25
                hintLevel: 1,
              ),
            );
      }

      final reviews = await service.runDueReviews(currentTime: now);
      expect(reviews, hasLength(1));
      final review = reviews.single;

      expect(review.decision, ReviewDecision.easeMore);
      expect(review.levelBefore, 6.0);
      expect(review.levelAfter, 5.0); // 6.0 - 1.0 = 5.0
      expect(review.isConcern, isTrue); // 0.90 -> 0.25 drop is > 0.30

      final progress = await repo.getGameProgress('trace_path');
      expect(progress.level, 5.0);
      expect(progress.reviewHistory.first.isConcern, isTrue);
    });
  });

  group('ProgressionService - Fatigue Management & Daily Rest Card', () {
    test('reports none when cumulative play is below 30 minutes', () async {
      final now = DateTime(2026, 9, 20, 14, 0);

      // Insert 2 sessions of 6 minutes each = 12 minutes
      await db.into(db.sessions).insert(
            createSession(
              id: 's1',
              startedAt: now.subtract(const Duration(hours: 2)),
              endedAt: now.subtract(const Duration(hours: 1, minutes: 54)),
            ),
          );
      await db.into(db.sessions).insert(
            createSession(
              id: 's2',
              startedAt: now.subtract(const Duration(minutes: 30)),
              endedAt: now.subtract(const Duration(minutes: 24)),
            ),
          );

      final eval = await service.checkRestStatus(currentTime: now);
      expect(eval.status, RestCardStatus.none);
      expect(eval.playSecondsToday ~/ 60, 12);
    });

    test('prompts for rest when cumulative play reaches 30 minutes', () async {
      final now = DateTime(2026, 9, 20, 14, 0);

      // Insert 4 sessions of 8 minutes = 32 minutes
      for (int i = 0; i < 4; i++) {
        final start = now.subtract(Duration(hours: 3 - i, minutes: 10));
        final end = start.add(const Duration(minutes: 8));
        await db.into(db.sessions).insert(
              createSession(id: 's_$i', startedAt: start, endedAt: end),
            );
      }

      final eval = await service.checkRestStatus(currentTime: now);
      expect(eval.status, RestCardStatus.showPrompt);
      expect(eval.playSecondsToday ~/ 60, 32);

      // Verify that lastPromptPlaySeconds was saved to prevent immediate re-prompting
      final state = await repo.getRestState(now: now);
      expect(state.lastPromptPlaySeconds, 32 * 60);
    });

    test('keepPlaying increments counter and triggers 3-hour lock on 3rd override', () async {
      final now = DateTime(2026, 9, 20, 14, 0);

      // First keepPlaying
      await service.recordRestAction(RestAction.keepPlaying, currentTime: now);
      var state = await repo.getRestState(now: now);
      expect(state.keepPlayingCount, 1);
      expect(state.isLocked(now), isFalse);

      // Second keepPlaying
      await service.recordRestAction(RestAction.keepPlaying, currentTime: now);
      state = await repo.getRestState(now: now);
      expect(state.keepPlayingCount, 2);
      expect(state.isLocked(now), isFalse);

      // Third keepPlaying triggers gentle lock
      await service.recordRestAction(RestAction.keepPlaying, currentTime: now);
      state = await repo.getRestState(now: now);
      expect(state.keepPlayingCount, 3);
      expect(state.isLocked(now), isTrue);
      expect(state.lockUntilTs, now.add(ProgressionConfig.gameLockDuration).millisecondsSinceEpoch);

      // checkRestStatus now returns locked
      final eval = await service.checkRestStatus(currentTime: now);
      expect(eval.status, RestCardStatus.locked);
      expect(eval.lockUntil, now.add(ProgressionConfig.gameLockDuration));
    });

    test('takeBreak resets keepPlaying count', () async {
      final now = DateTime(2026, 9, 20, 14, 0);

      await service.recordRestAction(RestAction.keepPlaying, currentTime: now);
      await service.recordRestAction(RestAction.takeBreak, currentTime: now);

      final state = await repo.getRestState(now: now);
      expect(state.keepPlayingCount, 0);
    });
  });

  group('ProgressionService - Anti-Perseveration Variety Nudge', () {
    test('returns shouldNudge: false when fewer than 6 sessions', () async {
      final now = DateTime(2026, 9, 20, 14, 0);

      // 4 sessions in market_basket (100% share but < 6 plays)
      for (int i = 0; i < 4; i++) {
        await db.into(db.sessions).insert(
              createSession(
                id: 'sess_$i',
                startedAt: now.subtract(Duration(days: 1, hours: i)),
                endedAt: now.subtract(Duration(days: 1, hours: i, minutes: -5)),
                gameIds: 'market_basket',
              ),
            );
      }

      final eval = await service.checkVarietyNudge(currentTime: now);
      expect(eval.shouldNudge, isFalse);
    });

    test('triggers variety nudge when single game exceeds 60% share over >= 6 sessions', () async {
      final now = DateTime(2026, 9, 20, 14, 0);

      // 8 sessions: 6 market_basket (75% share >= 60%, >= 6 plays), 2 sort_harvest
      for (int i = 0; i < 6; i++) {
        await db.into(db.sessions).insert(
              createSession(
                id: 'mb_$i',
                startedAt: now.subtract(Duration(days: 1, hours: i)),
                endedAt: now.subtract(Duration(days: 1, hours: i, minutes: -5)),
                gameIds: 'market_basket',
              ),
            );
      }
      for (int i = 0; i < 2; i++) {
        await db.into(db.sessions).insert(
              createSession(
                id: 'sh_$i',
                startedAt: now.subtract(Duration(days: 2, hours: i)),
                endedAt: now.subtract(Duration(days: 2, hours: i, minutes: -5)),
                gameIds: 'sort_harvest',
              ),
            );
      }

      final eval = await service.checkVarietyNudge(currentTime: now);
      expect(eval.shouldNudge, isTrue);
      expect(eval.dominantGameId, 'market_basket');
      expect(eval.recommendedGameId, isNotNull);
      expect(eval.recommendedDomain, isNotNull);
    });

    test('recordNudgeDismissed snoozes after 2 dismissals', () async {
      final now = DateTime(2026, 9, 20, 14, 0);

      // First dismissal
      await service.recordNudgeDismissed(currentTime: now);
      var state = await repo.getNudgeState();
      expect(state.dismissCount, 1);
      expect(state.isSnoozed(now), isFalse);

      // Second dismissal -> 2-day snooze
      await service.recordNudgeDismissed(currentTime: now);
      state = await repo.getNudgeState();
      expect(state.dismissCount, 2);
      expect(state.isSnoozed(now), isTrue);
      expect(
        state.snoozeUntilTs,
        now
            .add(const Duration(days: ProgressionConfig.nudgeSnoozeDays))
            .millisecondsSinceEpoch,
      );
    });
  });

  group('ProgressionService - Difficulty Source Factory', () {
    test('creates StaircaseDifficultySource initialized with saved baseline level', () async {
      await repo.saveGameProgress(
        const GameProgress(
          gameId: 'market_basket',
          level: 6.5,
        ),
      );

      final source = await service.createDifficultySource('market_basket');
      expect(source.baseLevel, 6.5);
      expect(source.currentLevel('market_basket'), 6.5);

      // 3 consecutive hits -> +0.5 in-session adjustment
      source.recordTrialResult(gameId: 'market_basket', correct: true);
      source.recordTrialResult(gameId: 'market_basket', correct: true);
      source.recordTrialResult(gameId: 'market_basket', correct: true);
      expect(source.sessionOffset, 0.5);
      expect(source.currentLevel('market_basket'), 7.0);
    });
  });
}
