import 'performance_report.dart';
import 'progression_config.dart';
import 'progression_state.dart';

/// The result of a 4-day macro review evaluation.
class ReviewEvaluation {
  const ReviewEvaluation({
    required this.decision,
    required this.levelDelta,
    required this.isConcern,
    required this.reason,
    this.throttled = false,
  });

  final ReviewDecision decision;
  final double levelDelta;
  final bool isConcern;
  final String reason;
  final bool throttled;
}

/// Pure decision engine for the 4-Day Macro Review.
///
/// Encapsulates the Decision Policy Table, Anti-Oscillation Safeguard,
/// and Clinical Concern Detection.
///
/// Reference: PROGRESSION_SYSTEM_GUIDE.md §6
class ProgressionPolicy {
  const ProgressionPolicy._();

  /// Evaluates performance over the 4-day window against historical progress.
  static ReviewEvaluation evaluateReview({
    required PerformanceReport report,
    required GameProgress currentProgress,
    required DateTime now,
    bool isLongTask = false,
    bool forceOverride = false,
  }) {
    // 1. Check for extended absence / returning patient (>= 14 days inactivity)
    if (currentProgress.lastReviewTs != null && !forceOverride) {
      final lastReview = DateTime.fromMillisecondsSinceEpoch(
        currentProgress.lastReviewTs!,
      );
      final daysSinceLastReview = now.difference(lastReview).inDays;
      if (daysSinceLastReview >= ProgressionConfig.inactivityDaysThreshold) {
        return const ReviewEvaluation(
          decision: ReviewDecision.returning,
          levelDelta: -ProgressionConfig.inactivityLevelDrop,
          isConcern: false,
          reason: 'Returning after extended inactivity (>= 14 days)',
        );
      }
    }

    // 2. Check for sufficient trial volume and active days
    if (!forceOverride && !report.hasSufficientData(isLongTask: isLongTask)) {
      return const ReviewEvaluation(
        decision: ReviewDecision.notEnoughData,
        levelDelta: 0.0,
        isConcern: false,
        reason: 'Insufficient trials or active days in review window',
      );
    }

    // 3. Clinical Concern Detection
    // Flags an acute drop of >= 30% from the previous valid review score
    bool isConcern = false;
    if (currentProgress.lastReviewScore != null) {
      final drop = currentProgress.lastReviewScore! - report.meanScore;
      if (drop >= ProgressionConfig.concernScoreDropThreshold) {
        isConcern = true;
      }
    }

    // 4. Evaluate Prior Review History for Anti-Oscillation
    final recentReviews = currentProgress.reviewHistory.take(
      ProgressionConfig.antiOscillationLookbackReviews,
    );
    final recentlyDemoted = recentReviews.any(
      (r) =>
          r.decision == ReviewDecision.ease ||
          r.decision == ReviewDecision.easeMore,
    );

    // 5. Evaluate Decision Policy Table
    // Check Hint Reliance first: cannot promote if hint rate > 20%
    final bool hintReliant = report.hintRate > ProgressionConfig.raiseMaxHintRate;

    // A. RAISE candidate: Score >= 0.85 AND Accuracy >= 0.80 AND HintRate <= 0.20
    if (report.meanScore >= ProgressionConfig.raiseMinScore &&
        report.accuracy >= ProgressionConfig.raiseMinAccuracy &&
        !hintReliant) {
      if (recentlyDemoted) {
        // Anti-Oscillation: requires 2 consecutive qualifying cycles
        final currentQualifyingCount =
            currentProgress.consecutiveRaiseQualifyingCount + 1;

        if (currentQualifyingCount <
            ProgressionConfig.antiOscillationRequiredQualifyingCycles) {
          return ReviewEvaluation(
            decision: ReviewDecision.hold,
            levelDelta: 0.0,
            isConcern: isConcern,
            reason:
                'Qualifies for raise after recent demotion; holding for second confirming cycle',
          );
        }

        // Second consecutive qualifying cycle confirmed: promote with throttling (+0.5)
        return ReviewEvaluation(
          decision: ReviewDecision.raise,
          levelDelta: ProgressionConfig.raiseThrottledLevelDelta,
          isConcern: isConcern,
          throttled: true,
          reason:
              'Promoted with anti-oscillation throttling (+0.5) after confirmed stability',
        );
      }

      // Normal un-throttled promotion (+1.0)
      return ReviewEvaluation(
        decision: ReviewDecision.raise,
        levelDelta: ProgressionConfig.raiseLevelDelta,
        isConcern: isConcern,
        reason: 'Thriving performance: promoted by +1.0',
      );
    }

    // B. NUDGE UP candidate: Score >= 0.78 AND Prior in {Hold, NudgeUp} AND HintRate <= 0.20
    final priorDecision = currentProgress.reviewHistory.isNotEmpty
        ? currentProgress.reviewHistory.first.decision
        : null;
    final priorWasHolding = priorDecision == ReviewDecision.hold ||
        priorDecision == ReviewDecision.nudgeUp;

    if (report.meanScore >= ProgressionConfig.nudgeUpMinScore &&
        priorWasHolding &&
        !hintReliant) {
      return ReviewEvaluation(
        decision: ReviewDecision.nudgeUp,
        levelDelta: ProgressionConfig.nudgeUpLevelDelta,
        isConcern: isConcern,
        reason: 'Consistent solid performance: nudged up by +0.5',
      );
    }

    // C. HOLD: Score in [0.60, 0.78) OR (Score >= 0.78 with HintRate > 0.20)
    if (report.meanScore >= ProgressionConfig.holdMinScore ||
        (report.meanScore >= ProgressionConfig.nudgeUpMinScore && hintReliant)) {
      return ReviewEvaluation(
        decision: ReviewDecision.hold,
        levelDelta: ProgressionConfig.holdLevelDelta,
        isConcern: isConcern,
        reason: hintReliant
            ? 'High hint usage (>20%): promotion blocked, level held'
            : 'Comfortable engagement sweet spot: level maintained',
      );
    }

    // D. EASE: Score in [0.45, 0.60)
    if (report.meanScore >= ProgressionConfig.easeMinScore) {
      return ReviewEvaluation(
        decision: ReviewDecision.ease,
        levelDelta: ProgressionConfig.easeLevelDelta,
        isConcern: isConcern,
        reason: 'Emergent cognitive strain: gently eased by -0.5',
      );
    }

    // E. EASE MORE: Score < 0.45
    return ReviewEvaluation(
      decision: ReviewDecision.easeMore,
      levelDelta: ProgressionConfig.easeMoreLevelDelta,
      isConcern: isConcern,
      reason: 'Substantial struggle: eased by -1.0 to restore confidence',
    );
  }
}
