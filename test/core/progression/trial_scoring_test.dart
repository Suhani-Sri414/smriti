import 'package:flutter_test/flutter_test.dart';
import 'package:smriti/core/progression/trial_scoring.dart';

void main() {
  group('TrialScoring (Partial Credit Engine)', () {
    test('Multi-Item Recall partial credit and intrusion penalties', () {
      // 4 targets, 1 missed, 0 intrusions -> 3/4 = 0.75
      expect(
        TrialScoring.scoreMultiItemRecall(targets: 4, missed: 1),
        0.75,
      );

      // 4 targets, 1 missed, 1 intrusion -> 1 - 2/4 = 0.50
      expect(
        TrialScoring.scoreMultiItemRecall(
            targets: 4, missed: 1, intrusions: 1),
        0.50,
      );

      // 4 targets, 4 missed, 2 intrusions -> clamped to 0.0
      expect(
        TrialScoring.scoreMultiItemRecall(
            targets: 4, missed: 4, intrusions: 2),
        0.0,
      );
    });

    test('Path Sequencing rewards partial completion while penalizing errors', () {
      // 6 nodes, 1 error -> 1 - 1/6 = 5/6
      expect(
        TrialScoring.scorePathSequencing(nodeCount: 6, errors: 1),
        closeTo(5.0 / 6.0, 1e-9),
      );

      // 6 nodes, 0 errors -> 1.0
      expect(
        TrialScoring.scorePathSequencing(nodeCount: 6, errors: 0),
        1.0,
      );
    });

    test('Span Recall scores prefix correctly', () {
      // Target span 5, achieved 3 -> 3/5 = 0.60
      expect(
        TrialScoring.scoreSpanRecall(targetSpan: 5, spanAchieved: 3),
        0.60,
      );
      expect(
        TrialScoring.scoreSpanRecall(targetSpan: 4, spanAchieved: 4),
        1.0,
      );
    });

    test('Continuous Vigilance penalizes false alarms via SDT formula', () {
      // Hit rate 0.90, false alarm 0.20 -> 0.90 - 0.5*0.20 = 0.80
      expect(
        TrialScoring.scoreContinuousVigilance(
            hitRate: 0.90, falseAlarmRate: 0.20),
        0.80,
      );

      // Impulsive tapping: Hit rate 1.0, false alarm 1.0 -> 1.0 - 0.5 = 0.50
      expect(
        TrialScoring.scoreContinuousVigilance(
            hitRate: 1.0, falseAlarmRate: 1.0),
        0.50,
      );
    });

    test('computeTrialScore parses JSON string and map metrics', () {
      // JSON string
      final jsonMetrics = '{"targets": 5, "missed": 1, "intrusions": 0}';
      expect(
        TrialScoring.computeTrialScore(
          gameId: 'market_basket',
          correct: false,
          metrics: jsonMetrics,
        ),
        0.80,
      );

      // Direct map
      expect(
        TrialScoring.computeTrialScore(
          gameId: 'lamps_festival',
          correct: false,
          metrics: {'targetSpan': 5, 'spanAchieved': 4},
        ),
        0.80,
      );

      // Binary fallback when metrics are absent
      expect(
        TrialScoring.computeTrialScore(
          gameId: 'unknown',
          correct: true,
        ),
        1.0,
      );
      expect(
        TrialScoring.computeTrialScore(
          gameId: 'unknown',
          correct: false,
        ),
        0.0,
      );
    });
  });
}
