import 'dart:convert';

/// Computes a continuous, partial-credit performance score S in [0.0, 1.0]
/// based on structured trial telemetry.
///
/// Reference: PROGRESSION_SYSTEM_GUIDE.md §5
class TrialScoring {
  const TrialScoring._();

  /// Multi-Item Recall (e.g. Market Basket)
  ///
  /// S = max(0, 1 - (missed + intrusions) / targets)
  static double scoreMultiItemRecall({
    required int targets,
    required int missed,
    int intrusions = 0,
  }) {
    if (targets <= 0) return 0.0;
    final penalty = (missed + intrusions) / targets;
    return (1.0 - penalty).clamp(0.0, 1.0);
  }

  /// Path Sequencing (e.g. Trace the Path)
  ///
  /// S = max(0, 1 - errors / nodeCount)
  static double scorePathSequencing({
    required int nodeCount,
    required int errors,
  }) {
    if (nodeCount <= 0) return 0.0;
    final penalty = errors / nodeCount;
    return (1.0 - penalty).clamp(0.0, 1.0);
  }

  /// Chronological Ordering (e.g. My Day)
  ///
  /// S = max(0, 1 - misplaced / totalEvents)
  static double scoreChronologicalOrdering({
    required int totalEvents,
    required int misplaced,
  }) {
    if (totalEvents <= 0) return 0.0;
    final penalty = misplaced / totalEvents;
    return (1.0 - penalty).clamp(0.0, 1.0);
  }

  /// Span Recall (e.g. Lamps Festival)
  ///
  /// S = spanAchieved / targetSpan
  static double scoreSpanRecall({
    required int targetSpan,
    required int spanAchieved,
  }) {
    if (targetSpan <= 0) return 0.0;
    return (spanAchieved / targetSpan).clamp(0.0, 1.0);
  }

  /// Categorical Fluency (e.g. Name the Harvest)
  ///
  /// S = min(1.0, validNamed / expectedCount)
  static double scoreCategoricalFluency({
    required int expectedCount,
    required int validNamed,
  }) {
    if (expectedCount <= 0) return 0.0;
    return (validNamed / expectedCount).clamp(0.0, 1.0);
  }

  /// Continuous Vigilance (e.g. Sounds of Home)
  ///
  /// S = max(0, hitRate - 0.5 * falseAlarmRate)
  static double scoreContinuousVigilance({
    required double hitRate,
    required double falseAlarmRate,
  }) {
    final net = hitRate - 0.5 * falseAlarmRate;
    return net.clamp(0.0, 1.0);
  }

  /// Evaluates a trial's telemetry and returns a continuous score in [0.0, 1.0].
  ///
  /// Inspects structured [metrics] (as a map or JSON string) and falls back
  /// to binary accuracy when detailed metrics are absent.
  static double computeTrialScore({
    required String gameId,
    required bool correct,
    dynamic metrics,
  }) {
    final Map<String, dynamic>? metricsMap = _parseMetrics(metrics);

    if (metricsMap != null) {
      // Direct override if explicit score was saved
      if (metricsMap.containsKey('score')) {
        final score = (metricsMap['score'] as num?)?.toDouble();
        if (score != null) return score.clamp(0.0, 1.0);
      }

      // Check archetype-specific metrics
      if (metricsMap.containsKey('targets') && metricsMap.containsKey('missed')) {
        final targets = (metricsMap['targets'] as num).toInt();
        final missed = (metricsMap['missed'] as num).toInt();
        final intrusions = (metricsMap['intrusions'] as num?)?.toInt() ?? 0;
        return scoreMultiItemRecall(
          targets: targets,
          missed: missed,
          intrusions: intrusions,
        );
      }

      if (metricsMap.containsKey('nodeCount') && metricsMap.containsKey('errors')) {
        final nodeCount = (metricsMap['nodeCount'] as num).toInt();
        final errors = (metricsMap['errors'] as num).toInt();
        return scorePathSequencing(
          nodeCount: nodeCount,
          errors: errors,
        );
      }

      if (metricsMap.containsKey('targetSpan') &&
          metricsMap.containsKey('spanAchieved')) {
        final targetSpan = (metricsMap['targetSpan'] as num).toInt();
        final spanAchieved = (metricsMap['spanAchieved'] as num).toInt();
        return scoreSpanRecall(
          targetSpan: targetSpan,
          spanAchieved: spanAchieved,
        );
      }

      if (metricsMap.containsKey('hitRate') &&
          metricsMap.containsKey('falseAlarmRate')) {
        final hitRate = (metricsMap['hitRate'] as num).toDouble();
        final falseAlarmRate =
            (metricsMap['falseAlarmRate'] as num).toDouble();
        return scoreContinuousVigilance(
          hitRate: hitRate,
          falseAlarmRate: falseAlarmRate,
        );
      }

      final errorClass =
          (metricsMap['error_class'] ?? metricsMap['errorClass']) as String?;
      if (!correct && errorClass != null) {
        if (errorClass == 'semantic' || errorClass == 'semantic_near') {
          return 0.5;
        } else if (errorClass == 'perseverative') {
          return 0.3;
        }
      }
    }

    // Default binary fallback
    return correct ? 1.0 : 0.0;
  }

  static Map<String, dynamic>? _parseMetrics(dynamic metrics) {
    if (metrics is Map<String, dynamic>) return metrics;
    if (metrics is Map) return Map<String, dynamic>.from(metrics);
    if (metrics is String && metrics.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(metrics);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return null;
  }
}
