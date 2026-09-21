import 'package:flutter_test/flutter_test.dart';
import 'package:smriti/core/progression/level_scale.dart';
import 'package:smriti/core/progression/progression_config.dart';

void main() {
  group('LevelScale (Bijective Math & Scale Properties)', () {
    test('exact linear bijection between level and difficulty', () {
      final testCases = [
        (1.0, -2.0),
        (3.0, -1.0),
        (5.0, 0.0),
        (7.0, 1.0),
        (9.0, 2.0),
        (13.0, 4.0),
      ];

      for (final (level, difficulty) in testCases) {
        expect(LevelScale.levelToDifficulty(level), closeTo(difficulty, 1e-9));
        expect(LevelScale.difficultyToLevel(difficulty), closeTo(level, 1e-9));
      }
    });

    test('round-trip bijection identity holds across continuous domain', () {
      for (double l = 1.0; l <= 20.0; l += 0.25) {
        final d = LevelScale.levelToDifficulty(l);
        final reconstructedL = LevelScale.difficultyToLevel(d);
        expect(reconstructedL, closeTo(l, 1e-9));
      }
    });

    test('quantizes levels to 0.5 increments', () {
      expect(LevelScale.quantize(1.0), 1.0);
      expect(LevelScale.quantize(1.2), 1.0);
      expect(LevelScale.quantize(1.3), 1.5);
      expect(LevelScale.quantize(1.74), 1.5);
      expect(LevelScale.quantize(1.76), 2.0);
      expect(LevelScale.quantize(5.24), 5.0);
      expect(LevelScale.quantize(5.25), 5.5);
    });

    test('clamps level to minimum floor (L >= 1.0)', () {
      expect(LevelScale.clampLevel(0.0), ProgressionConfig.minLevel);
      expect(LevelScale.clampLevel(-5.0), ProgressionConfig.minLevel);
      expect(LevelScale.clampLevel(0.8), ProgressionConfig.minLevel);
      expect(LevelScale.clampLevel(1.5), 1.5);
    });

    test('clamps level to optional ceiling when specified', () {
      expect(LevelScale.clampLevel(8.0, maxLevel: 7.0), 7.0);
      expect(LevelScale.clampLevel(5.5, maxLevel: 7.0), 5.5);
    });
  });
}
