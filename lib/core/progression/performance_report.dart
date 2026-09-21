import '../db/database.dart';
import 'progression_config.dart';
import 'trial_scoring.dart';

/// Aggregated performance telemetry across an evaluation window for a single game.
///
/// Used by the 4-Day Macro Review Engine to decide promotions, holds, and eases.
/// Reference: PROGRESSION_SYSTEM_GUIDE.md §6
class PerformanceReport {
  const PerformanceReport({
    required this.gameId,
    required this.totalTrials,
    required this.activeDays,
    required this.meanScore,
    required this.accuracy,
    required this.hintRate,
    this.firstTrialTs,
    this.lastTrialTs,
  });

  final String gameId;
  final int totalTrials;
  final int activeDays;
  final double meanScore;
  final double accuracy;
  final double hintRate;
  final int? firstTrialTs;
  final int? lastTrialTs;

  /// True if trial volume and active days meet the review threshold.
  bool hasSufficientData({bool isLongTask = false}) {
    final requiredTrials = isLongTask
        ? ProgressionConfig.minReviewTrialsLong
        : ProgressionConfig.minReviewTrials;
    return totalTrials >= requiredTrials &&
        activeDays >= ProgressionConfig.minReviewActiveDays;
  }

  /// Builds a [PerformanceReport] from a collection of raw [TrialEvent] rows.
  factory PerformanceReport.fromTrials({
    required String gameId,
    required List<TrialEvent> trials,
  }) {
    if (trials.isEmpty) {
      return PerformanceReport(
        gameId: gameId,
        totalTrials: 0,
        activeDays: 0,
        meanScore: 0.0,
        accuracy: 0.0,
        hintRate: 0.0,
      );
    }

    int correctCount = 0;
    int hintCount = 0;
    double scoreSum = 0.0;
    final distinctDates = <String>{};
    int? minTs;
    int? maxTs;

    for (final trial in trials) {
      final score = TrialScoring.computeTrialScore(
        gameId: gameId,
        correct: trial.correct,
        metrics: trial.metrics,
      );
      scoreSum += score;

      if (trial.correct) correctCount++;
      if (trial.hintLevel > 0) hintCount++;

      final ts = trial.ts;
      if (minTs == null || ts < minTs) minTs = ts;
      if (maxTs == null || ts > maxTs) maxTs = ts;

      final date = DateTime.fromMillisecondsSinceEpoch(ts);
      final dateKey =
          '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      distinctDates.add(dateKey);
    }

    final n = trials.length;
    return PerformanceReport(
      gameId: gameId,
      totalTrials: n,
      activeDays: distinctDates.length,
      meanScore: scoreSum / n,
      accuracy: correctCount / n,
      hintRate: hintCount / n,
      firstTrialTs: minTs,
      lastTrialTs: maxTs,
    );
  }
}
