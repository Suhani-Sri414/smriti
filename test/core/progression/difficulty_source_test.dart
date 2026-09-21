import 'package:flutter_test/flutter_test.dart';
import 'package:smriti/core/progression/difficulty_source.dart';
import 'package:smriti/core/progression/level_scale.dart';
import 'package:smriti/core/progression/progression_config.dart';

void main() {
  group('StaircaseDifficultySource (Inner Loop Micro-Adaptation)', () {
    test('initializes with base level and zero offset', () {
      final source = StaircaseDifficultySource(baseLevel: 5.0);
      expect(source.baseLevel, 5.0);
      expect(source.sessionOffset, 0.0);
      expect(source.currentLevel('game_1'), 5.0);
      expect(source.currentDifficulty('game_1'),
          LevelScale.levelToDifficulty(5.0));
    });

    test('3 consecutive correct hits increment level by +0.5', () {
      final source = StaircaseDifficultySource(baseLevel: 5.0);

      // Hit 1
      source.recordTrialResult(gameId: 'game_1', correct: true);
      expect(source.sessionOffset, 0.0);
      expect(source.consecutiveHits, 1);

      // Hit 2
      source.recordTrialResult(gameId: 'game_1', correct: true);
      expect(source.sessionOffset, 0.0);
      expect(source.consecutiveHits, 2);

      // Hit 3 -> triggers +0.5 step up
      source.recordTrialResult(gameId: 'game_1', correct: true);
      expect(source.sessionOffset, 0.5);
      expect(source.consecutiveHits, 0);
      expect(source.currentLevel('game_1'), 5.5);
    });

    test('2 consecutive misses decrement level by -0.5', () {
      final source = StaircaseDifficultySource(baseLevel: 5.0);

      // Miss 1
      source.recordTrialResult(gameId: 'game_1', correct: false);
      expect(source.sessionOffset, 0.0);
      expect(source.consecutiveMisses, 1);

      // Miss 2 -> triggers -0.5 step down
      source.recordTrialResult(gameId: 'game_1', correct: false);
      expect(source.sessionOffset, -0.5);
      expect(source.consecutiveMisses, 0);
      expect(source.currentLevel('game_1'), 4.5);
    });

    test('offset is strictly clamped within [-1.0, +1.0]', () {
      final source = StaircaseDifficultySource(baseLevel: 5.0);

      // 9 consecutive hits (3 step-ups)
      for (int i = 0; i < 9; i++) {
        source.recordTrialResult(gameId: 'game_1', correct: true);
      }

      // 2 step-ups reached max clamp +1.0; 3rd cannot exceed +1.0
      expect(source.sessionOffset, ProgressionConfig.staircaseClamp);
      expect(source.currentLevel('game_1'), 6.0);

      // Now 6 consecutive misses (3 step-downs)
      for (int i = 0; i < 6; i++) {
        source.recordTrialResult(gameId: 'game_1', correct: false);
      }
      // Offset drops from +1.0 to -0.5 (3 steps: +0.5, 0.0, -0.5)
      expect(source.sessionOffset, -0.5);

      // 4 more misses (2 step-downs)
      for (int i = 0; i < 4; i++) {
        source.recordTrialResult(gameId: 'game_1', correct: false);
      }
      // Clamped at -1.0
      expect(source.sessionOffset, -ProgressionConfig.staircaseClamp);
      expect(source.currentLevel('game_1'), 4.0);
    });

    test('effective level never underflows below L = 1.0 floor', () {
      final source = StaircaseDifficultySource(baseLevel: 1.0);

      // 2 misses would decrement offset to -0.5, but level is clamped at 1.0
      source.recordTrialResult(gameId: 'game_1', correct: false);
      source.recordTrialResult(gameId: 'game_1', correct: false);

      expect(source.sessionOffset, -0.5);
      expect(source.currentLevel('game_1'), 1.0);
    });

    test('resetSession restores offset to zero without modifying baseLevel', () {
      final source = StaircaseDifficultySource(baseLevel: 5.0);

      for (int i = 0; i < 3; i++) {
        source.recordTrialResult(gameId: 'game_1', correct: true);
      }
      expect(source.currentLevel('game_1'), 5.5);

      source.resetSession();
      expect(source.sessionOffset, 0.0);
      expect(source.baseLevel, 5.0);
      expect(source.currentLevel('game_1'), 5.0);
    });
  });
}
