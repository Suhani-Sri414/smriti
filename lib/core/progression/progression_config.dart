/// Centralized configuration and threshold constants for the Adaptive Progression
/// and Cognitive Fatigue Management Engine.
///
/// Governed by PROGRESSION_SYSTEM_GUIDE.md.
class ProgressionConfig {
  const ProgressionConfig._();

  // --- Scale & Level Bounds (§2) ---
  /// Minimum allowed level floor to prevent underflow into degenerate negative configurations.
  static const double minLevel = 1.0;

  /// Default baseline level for a new, unassessed game (corresponds to d = 0.0).
  static const double defaultLevel = 5.0;

  /// Quantization step size for persistent baseline levels.
  static const double levelStep = 0.5;

  /// Extra level headroom permitted above the profile plateau level.
  static const double plateauHeadroom = 1.0;

  // --- Inner Loop: In-Session Staircase (§4) ---
  /// Number of consecutive correct hits required to trigger an upward step.
  static const int staircaseUpHits = 3;

  /// Number of consecutive misses / timeouts that trigger a downward step.
  static const int staircaseDownMisses = 2;

  /// In-session step adjustment magnitude.
  static const double staircaseStep = 0.5;

  /// Maximum absolute in-session offset bound relative to session baseline (+/- 1.0).
  static const double staircaseClamp = 1.0;

  // --- Outer Loop: 4-Day Macro Review (§6) ---
  /// Duration of the evaluation window in calendar days.
  static const int reviewWindowDays = 4;

  /// Minimum total completed trials required in the window to perform a standard review.
  static const int minReviewTrials = 8;

  /// Minimum total completed trials required for long-form cognitive tasks.
  static const int minReviewTrialsLong = 3;

  /// Minimum distinct active calendar days in the window required to qualify for review.
  static const int minReviewActiveDays = 2;

  /// Inactivity threshold in days that triggers a gentle returning ease.
  static const int inactivityDaysThreshold = 14;

  /// Level drop applied after >= 14 days of inactivity.
  static const double inactivityLevelDrop = 1.0;

  /// Promotion (Raise) requirements:
  static const double raiseMinScore = 0.85;
  static const double raiseMinAccuracy = 0.80;
  static const double raiseMaxHintRate = 0.20;
  static const double raiseLevelDelta = 1.0;
  static const double raiseThrottledLevelDelta = 0.5;

  /// Nudge Up requirements:
  static const double nudgeUpMinScore = 0.78;
  static const double nudgeUpMaxHintRate = 0.20;
  static const double nudgeUpLevelDelta = 0.5;

  /// Hold requirements:
  static const double holdMinScore = 0.60;
  static const double holdLevelDelta = 0.0;

  /// Ease requirements:
  static const double easeMinScore = 0.45;
  static const double easeLevelDelta = -0.5;

  /// Ease More requirements:
  static const double easeMoreLevelDelta = -1.0;

  /// Anti-oscillation safeguard: reviews to look back for recent demotions.
  static const int antiOscillationLookbackReviews = 2;

  /// Consecutive qualifying review cycles required before promotion after a demotion.
  static const int antiOscillationRequiredQualifyingCycles = 2;

  /// Clinical concern detection threshold: acute score drop of >= 30% between reviews.
  static const double concernScoreDropThreshold = 0.30;

  // --- Fatigue & Fixation Management (§7) ---
  /// Daily cumulative play time (in seconds) that triggers the warm rest card (30 min).
  static const int restPromptPlaySeconds = 30 * 60; // 1800s
  static const int restCardThresholdSeconds = restPromptPlaySeconds;

  /// Maximum seconds a single session can contribute to the daily total (8 min cap).
  static const int maxCountedSessionSeconds = 8 * 60; // 480s

  /// Additional play time before repeating the rest prompt after "Keep playing" (15 min).
  static const int restSnoozeSeconds = 15 * 60; // 900s
  static const int restCardSnoozeSeconds = restSnoozeSeconds;

  /// Maximum times an elder can choose "Keep playing" before gentle lock activates.
  static const int maxKeepPlayingCount = 3;

  /// Duration of the gentle eye-break lock once maximum overrides are reached (3 hours).
  static const Duration gameLockDuration = Duration(hours: 3);

  /// Variety nudge lookback window in calendar days.
  static const int nudgeWindowDays = 3;

  /// Minimum plays in the window required before considering a variety nudge.
  static const int nudgeRepeatPlays = 6;

  /// Proportion of total session plays accounted for by a single game to trigger nudge (60%).
  static const double nudgeShareOfPlays = 0.60;

  /// Number of dismissals before the variety nudge snoozes.
  static const int nudgeDismissalsToSnooze = 2;

  /// Duration in calendar days to snooze variety nudges after repeated dismissals.
  static const int nudgeSnoozeDays = 2;

  // --- Persistence Key Patterns in AppConfigs (§8.1) ---
  static const String keyGamePrefix = 'progression.v1.game.';
  static const String keyRest = 'progression.v1.rest';
  static const String keyNudge = 'progression.v1.nudge';
  static const String keySettings = 'progression.v1.settings';

  static String gameKey(String gameId) => '$keyGamePrefix$gameId';
}
