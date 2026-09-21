import 'dart:math' as math;

import 'level_scale.dart';
import 'progression_config.dart';

/// Provider for current difficulty and level during active gameplay.
abstract class DifficultySource {
  /// Returns the current effective level (L >= 1.0) for [gameId].
  double currentLevel(String gameId);

  /// Returns the psychometric IRT difficulty (d) corresponding to current level.
  double currentDifficulty(String gameId);

  /// Records the result of a single trial to update in-session staircase state.
  void recordTrialResult({
    required String gameId,
    required bool correct,
    int hintLevel = 0,
  });

  /// Discards ephemeral within-session offsets and resets counters.
  void resetSession();
}

/// In-Session Staircase implementation of [DifficultySource].
///
/// Handles within-session micro-adjustments for transient cognitive fluctuations:
/// - 3 consecutive correct hits -> +0.5 level offset
/// - 2 consecutive misses -> -0.5 level offset
/// - Offset strictly clamped to [-1.0, +1.0]
/// - Ephemeral: resets on session end, never mutates persistent baseline level.
///
/// Reference: PROGRESSION_SYSTEM_GUIDE.md §4
class StaircaseDifficultySource implements DifficultySource {
  StaircaseDifficultySource({
    required double baseLevel,
    this.maxLevel,
  }) : _baseLevel = LevelScale.clampLevel(baseLevel, maxLevel: maxLevel);

  final double _baseLevel;
  final double? maxLevel;

  double _sessionOffset = 0.0;
  int _consecutiveHits = 0;
  int _consecutiveMisses = 0;

  /// The persistent base level for this session.
  double get baseLevel => _baseLevel;

  /// The ephemeral within-session offset, clamped to [-1.0, +1.0].
  double get sessionOffset => _sessionOffset;

  /// Current consecutive correct hits.
  int get consecutiveHits => _consecutiveHits;

  /// Current consecutive misses.
  int get consecutiveMisses => _consecutiveMisses;

  @override
  double currentLevel(String gameId) {
    final raw = _baseLevel + _sessionOffset;
    return LevelScale.clampLevel(raw, maxLevel: maxLevel);
  }

  @override
  double currentDifficulty(String gameId) {
    return LevelScale.levelToDifficulty(currentLevel(gameId));
  }

  @override
  void recordTrialResult({
    required String gameId,
    required bool correct,
    int hintLevel = 0,
  }) {
    if (correct) {
      _consecutiveHits++;
      _consecutiveMisses = 0;

      if (_consecutiveHits >= ProgressionConfig.staircaseUpHits) {
        _sessionOffset = math.min(
          _sessionOffset + ProgressionConfig.staircaseStep,
          ProgressionConfig.staircaseClamp,
        );
        _consecutiveHits = 0;
      }
    } else {
      _consecutiveMisses++;
      _consecutiveHits = 0;

      if (_consecutiveMisses >= ProgressionConfig.staircaseDownMisses) {
        _sessionOffset = math.max(
          _sessionOffset - ProgressionConfig.staircaseStep,
          -ProgressionConfig.staircaseClamp,
        );
        _consecutiveMisses = 0;
      }
    }
  }

  @override
  void resetSession() {
    _sessionOffset = 0.0;
    _consecutiveHits = 0;
    _consecutiveMisses = 0;
  }
}
