import 'dart:math' as math;

import 'progression_config.dart';

/// Rounding modes for difficulty axis values.
enum AxisRounding {
  /// Unrounded continuous floating-point values (e.g. ratios, seconds, probabilities).
  none,

  /// Truncate to floor (e.g. discrete count of cards, items, categories).
  floor,

  /// Round to nearest integer (e.g. sequence span, display milliseconds).
  round,
}

/// Represents one physical or cognitive dimension of a game.
///
/// Evaluates parameter values continuously and deterministically for any Level L.
/// Reference: PROGRESSION_SYSTEM_GUIDE.md §3
class DifficultyAxis {
  const DifficultyAxis({
    required this.name,
    required this.start,
    required this.perLevel,
    required this.limit,
    this.startLevel = 1.0,
    this.rounding = AxisRounding.none,
  });

  /// Unique identifier of the axis (e.g., 'targetCount', 'delaySeconds').
  final String name;

  /// Baseline value at and below [startLevel].
  final double start;

  /// Rate of change per +1.0 level (positive for increasing challenge,
  /// negative for reducing duration/delay).
  final double perLevel;

  /// Humane upper or lower bound that must never be crossed.
  final double limit;

  /// Level at which this axis starts moving (defaults to 1.0).
  final double startLevel;

  /// Rounding applied to the evaluated value.
  final AxisRounding rounding;

  /// Evaluates the axis value at a given [level].
  ///
  /// Guarantees that the value never crosses [limit] and moves monotonically.
  double evaluate(double level) {
    if (level <= startLevel) {
      return _applyRounding(start);
    }

    final rawDelta = perLevel * (level - startLevel);
    double computed;

    if (perLevel > 0) {
      computed = math.min(start + rawDelta, limit);
    } else if (perLevel < 0) {
      computed = math.max(start + rawDelta, limit);
    } else {
      computed = start;
    }

    return _applyRounding(computed);
  }

  /// Calculates the exact level where this axis hits its [limit].
  double get saturationLevel {
    if (perLevel == 0.0) return startLevel;
    final distance = (limit - start).abs();
    final rate = perLevel.abs();
    return startLevel + (distance / rate);
  }

  double _applyRounding(double value) {
    return switch (rounding) {
      AxisRounding.none => value,
      AxisRounding.floor => value.floorToDouble(),
      AxisRounding.round => value.roundToDouble(),
    };
  }
}

/// Declarative profile combining multiple [DifficultyAxis] objects for a game.
class LevelProfile {
  const LevelProfile({
    required this.gameId,
    required this.axes,
  });

  final String gameId;
  final List<DifficultyAxis> axes;

  /// Evaluates all difficulty axes for the specified [level] and returns
  /// a parameter map keyed by axis name.
  Map<String, double> paramsAt(double level) {
    final result = <String, double>{};
    for (final axis in axes) {
      result[axis.name] = axis.evaluate(level);
    }
    return result;
  }

  /// The level at which ALL axes of this game profile have saturated.
  double get plateauLevel {
    if (axes.isEmpty) return ProgressionConfig.minLevel;
    double maxSat = ProgressionConfig.minLevel;
    for (final axis in axes) {
      final sat = axis.saturationLevel;
      if (sat > maxSat) {
        maxSat = sat;
      }
    }
    return maxSat;
  }

  /// Maximum permitted level before human ceiling capping applies (Plateau + 1.0).
  double get maxAllowedLevel =>
      plateauLevel + ProgressionConfig.plateauHeadroom;

  /// Looks up a specific axis by name.
  DifficultyAxis? getAxis(String name) {
    for (final axis in axes) {
      if (axis.name == name) return axis;
    }
    return null;
  }
}
