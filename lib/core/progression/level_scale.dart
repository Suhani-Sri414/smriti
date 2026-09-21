import 'dart:math' as math;

import 'progression_config.dart';

/// Implements the exact, continuous linear bijection between human-readable
/// Level (L) and psychometric Item Response Theory (IRT) Difficulty (d).
///
/// Mathematical mapping:
///   d = (L - 5) / 2  <===>  L = 5 + 2d
///
/// Reference: PROGRESSION_SYSTEM_GUIDE.md §2
class LevelScale {
  const LevelScale._();

  /// Converts a human-readable Level [level] into an IRT logit difficulty [d].
  ///
  /// Examples:
  /// - L = 1.0 <===> d = -2.0 (baseline introduction)
  /// - L = 3.0 <===> d = -1.0 (mild challenge)
  /// - L = 5.0 <===> d =  0.0 (standard adult median)
  /// - L = 7.0 <===> d = +1.0 (enhanced challenge)
  /// - L = 9.0 <===> d = +2.0 (advanced cognitive demand)
  static double levelToDifficulty(double level) {
    return (level - 5.0) / 2.0;
  }

  /// Converts a psychometric logit difficulty [difficulty] into a human-readable Level [L].
  static double difficultyToLevel(double difficulty) {
    return 5.0 + 2.0 * difficulty;
  }

  /// Quantizes a level value to steps of 0.5 (e.g., 1.0, 1.5, 2.0, 2.5...).
  static double quantize(double level) {
    return (level * 2.0).roundToDouble() / 2.0;
  }

  /// Clamps and quantizes a level value ensuring it respects the minimum floor (L >= 1.0)
  /// and optional [maxLevel] ceiling.
  static double clampLevel(
    double level, {
    double? maxLevel,
  }) {
    final quantized = quantize(level);
    var result = math.max(ProgressionConfig.minLevel, quantized);
    if (maxLevel != null && maxLevel >= ProgressionConfig.minLevel) {
      result = math.min(result, quantize(maxLevel));
    }
    return result;
  }
}
