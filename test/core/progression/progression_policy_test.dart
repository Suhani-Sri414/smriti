import 'package:flutter_test/flutter_test.dart';
import 'package:smriti/core/progression/performance_report.dart';
import 'package:smriti/core/progression/progression_policy.dart';
import 'package:smriti/core/progression/progression_state.dart';

void main() {
  group('ProgressionPolicy (4-Day Macro Review Engine)', () {
    final now = DateTime(2026, 9, 20, 12, 0);

    test('promotes thriving user (+1.0) when score >= 0.85 and acc >= 0.80', () {
      const report = PerformanceReport(
        gameId: 'game_1',
        totalTrials: 12,
        activeDays: 3,
        meanScore: 0.88,
        accuracy: 0.85,
        hintRate: 0.10,
      );

      final eval = ProgressionPolicy.evaluateReview(
        report: report,
        currentProgress: const GameProgress(gameId: 'game_1', level: 5.0),
        now: now,
      );

      expect(eval.decision, ReviewDecision.raise);
      expect(eval.levelDelta, 1.0);
      expect(eval.throttled, isFalse);
      expect(eval.isConcern, isFalse);
    });

    test('high hint rate (>20%) blocks promotion and holds level', () {
      const report = PerformanceReport(
        gameId: 'game_1',
        totalTrials: 12,
        activeDays: 3,
        meanScore: 0.92,
        accuracy: 0.90,
        hintRate: 0.25, // Reliant on hints
      );

      final eval = ProgressionPolicy.evaluateReview(
        report: report,
        currentProgress: const GameProgress(gameId: 'game_1', level: 5.0),
        now: now,
      );

      expect(eval.decision, ReviewDecision.hold);
      expect(eval.levelDelta, 0.0);
      expect(eval.reason, contains('hint'));
    });

    test('nudges up (+0.5) when score >= 0.78 and prior was holding', () {
      const report = PerformanceReport(
        gameId: 'game_1',
        totalTrials: 10,
        activeDays: 2,
        meanScore: 0.81,
        accuracy: 0.78,
        hintRate: 0.10,
      );

      final priorReview = ReviewRecord(
        timestamp: now.subtract(const Duration(days: 4)).millisecondsSinceEpoch,
        decision: ReviewDecision.hold,
        levelBefore: 5.0,
        levelAfter: 5.0,
        meanScore: 0.70,
        accuracy: 0.70,
        hintRate: 0.10,
        totalTrials: 10,
      );

      final eval = ProgressionPolicy.evaluateReview(
        report: report,
        currentProgress: GameProgress(
          gameId: 'game_1',
          level: 5.0,
          reviewHistory: [priorReview],
        ),
        now: now,
      );

      expect(eval.decision, ReviewDecision.nudgeUp);
      expect(eval.levelDelta, 0.5);
    });

    test('eases (-0.5) when score is in [0.45, 0.60)', () {
      const report = PerformanceReport(
        gameId: 'game_1',
        totalTrials: 10,
        activeDays: 2,
        meanScore: 0.52,
        accuracy: 0.50,
        hintRate: 0.10,
      );

      final eval = ProgressionPolicy.evaluateReview(
        report: report,
        currentProgress: const GameProgress(gameId: 'game_1', level: 5.0),
        now: now,
      );

      expect(eval.decision, ReviewDecision.ease);
      expect(eval.levelDelta, -0.5);
    });

    test('eases more (-1.0) when score < 0.45', () {
      const report = PerformanceReport(
        gameId: 'game_1',
        totalTrials: 10,
        activeDays: 2,
        meanScore: 0.38,
        accuracy: 0.35,
        hintRate: 0.10,
      );

      final eval = ProgressionPolicy.evaluateReview(
        report: report,
        currentProgress: const GameProgress(gameId: 'game_1', level: 5.0),
        now: now,
      );

      expect(eval.decision, ReviewDecision.easeMore);
      expect(eval.levelDelta, -1.0);
    });

    test('notEnoughData when trials < 8 or activeDays < 2', () {
      const fewTrials = PerformanceReport(
        gameId: 'game_1',
        totalTrials: 6,
        activeDays: 3,
        meanScore: 0.90,
        accuracy: 0.90,
        hintRate: 0.0,
      );
      expect(
        ProgressionPolicy.evaluateReview(
          report: fewTrials,
          currentProgress: const GameProgress(gameId: 'game_1'),
          now: now,
        ).decision,
        ReviewDecision.notEnoughData,
      );

      const oneDayOnly = PerformanceReport(
        gameId: 'game_1',
        totalTrials: 15,
        activeDays: 1,
        meanScore: 0.90,
        accuracy: 0.90,
        hintRate: 0.0,
      );
      expect(
        ProgressionPolicy.evaluateReview(
          report: oneDayOnly,
          currentProgress: const GameProgress(gameId: 'game_1'),
          now: now,
        ).decision,
        ReviewDecision.notEnoughData,
      );
    });

    test('returning ease (-1.0) after >= 14 days inactivity', () {
      final fifteenDaysAgo = now.subtract(const Duration(days: 15));
      final eval = ProgressionPolicy.evaluateReview(
        report: const PerformanceReport(
          gameId: 'game_1',
          totalTrials: 0,
          activeDays: 0,
          meanScore: 0.0,
          accuracy: 0.0,
          hintRate: 0.0,
        ),
        currentProgress: GameProgress(
          gameId: 'game_1',
          level: 5.0,
          lastReviewTs: fifteenDaysAgo.millisecondsSinceEpoch,
        ),
        now: now,
      );

      expect(eval.decision, ReviewDecision.returning);
      expect(eval.levelDelta, -1.0);
    });

    test('Anti-Oscillation Safeguard throttles promotion after recent demotion', () {
      final demotedReview = ReviewRecord(
        timestamp: now.subtract(const Duration(days: 4)).millisecondsSinceEpoch,
        decision: ReviewDecision.ease,
        levelBefore: 5.0,
        levelAfter: 4.5,
        meanScore: 0.50,
        accuracy: 0.50,
        hintRate: 0.10,
        totalTrials: 10,
      );

      const qualifyingReport = PerformanceReport(
        gameId: 'game_1',
        totalTrials: 12,
        activeDays: 3,
        meanScore: 0.90,
        accuracy: 0.88,
        hintRate: 0.05,
      );

      // Cycle 1: qualifies for raise, but holding for 2nd confirming cycle
      final cycle1 = ProgressionPolicy.evaluateReview(
        report: qualifyingReport,
        currentProgress: GameProgress(
          gameId: 'game_1',
          level: 4.5,
          reviewHistory: [demotedReview],
          consecutiveRaiseQualifyingCount: 0,
        ),
        now: now,
      );
      expect(cycle1.decision, ReviewDecision.hold);
      expect(cycle1.levelDelta, 0.0);

      // Cycle 2: confirmed! Throttled to +0.5 instead of +1.0
      final cycle2 = ProgressionPolicy.evaluateReview(
        report: qualifyingReport,
        currentProgress: GameProgress(
          gameId: 'game_1',
          level: 4.5,
          reviewHistory: [demotedReview],
          consecutiveRaiseQualifyingCount: 1, // 1 previous qualifying cycle
        ),
        now: now,
      );
      expect(cycle2.decision, ReviewDecision.raise);
      expect(cycle2.levelDelta, 0.5);
      expect(cycle2.throttled, isTrue);
    });

    test('Clinical Concern flags acute drop >= 30%', () {
      const acuteDropReport = PerformanceReport(
        gameId: 'game_1',
        totalTrials: 10,
        activeDays: 2,
        meanScore: 0.50,
        accuracy: 0.50,
        hintRate: 0.10,
      );

      final eval = ProgressionPolicy.evaluateReview(
        report: acuteDropReport,
        currentProgress: const GameProgress(
          gameId: 'game_1',
          level: 6.0,
          lastReviewScore: 0.85, // 0.85 - 0.50 = 0.35 (35% drop >= 30%)
        ),
        now: now,
      );

      expect(eval.isConcern, isTrue);
      expect(eval.decision, ReviewDecision.ease);
    });
  });
}
