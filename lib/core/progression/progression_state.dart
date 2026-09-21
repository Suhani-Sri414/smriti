import 'level_scale.dart';
import 'progression_config.dart';

/// Decisions produced by the 4-Day Macro Review Engine.
enum ReviewDecision {
  raise,
  nudgeUp,
  hold,
  ease,
  easeMore,
  notEnoughData,
  returning,
}

/// A historical record of a single completed 4-day macro review.
class ReviewRecord {
  const ReviewRecord({
    required this.timestamp,
    required this.decision,
    required this.levelBefore,
    required this.levelAfter,
    required this.meanScore,
    required this.accuracy,
    required this.hintRate,
    required this.totalTrials,
    this.isConcern = false,
    this.throttled = false,
  });

  final int timestamp;
  final ReviewDecision decision;
  final double levelBefore;
  final double levelAfter;
  final double meanScore;
  final double accuracy;
  final double hintRate;
  final int totalTrials;
  final bool isConcern;
  final bool throttled;

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp,
        'decision': decision.name,
        'levelBefore': levelBefore,
        'levelAfter': levelAfter,
        'meanScore': meanScore,
        'accuracy': accuracy,
        'hintRate': hintRate,
        'totalTrials': totalTrials,
        'isConcern': isConcern,
        'throttled': throttled,
      };

  factory ReviewRecord.fromJson(Map<String, dynamic> json) {
    return ReviewRecord(
      timestamp: (json['timestamp'] as num).toInt(),
      decision: ReviewDecision.values.byName(json['decision'] as String),
      levelBefore: (json['levelBefore'] as num).toDouble(),
      levelAfter: (json['levelAfter'] as num).toDouble(),
      meanScore: (json['meanScore'] as num).toDouble(),
      accuracy: (json['accuracy'] as num).toDouble(),
      hintRate: (json['hintRate'] as num).toDouble(),
      totalTrials: (json['totalTrials'] as num).toInt(),
      isConcern: (json['isConcern'] as bool?) ?? false,
      throttled: (json['throttled'] as bool?) ?? false,
    );
  }
}

/// Encapsulates the persistent progression state for an individual cognitive game.
class GameProgress {
  const GameProgress({
    required this.gameId,
    this.level = ProgressionConfig.defaultLevel,
    this.lastReviewTs,
    this.reviewHistory = const [],
    this.consecutiveRaiseQualifyingCount = 0,
    this.lastReviewScore,
    this.isPlateaued = false,
  });

  final String gameId;
  final double level;
  final int? lastReviewTs;
  final List<ReviewRecord> reviewHistory;
  final int consecutiveRaiseQualifyingCount;
  final double? lastReviewScore;
  final bool isPlateaued;

  GameProgress copyWith({
    String? gameId,
    double? level,
    int? lastReviewTs,
    List<ReviewRecord>? reviewHistory,
    int? consecutiveRaiseQualifyingCount,
    double? lastReviewScore,
    bool? isPlateaued,
  }) {
    return GameProgress(
      gameId: gameId ?? this.gameId,
      level: level != null ? LevelScale.clampLevel(level) : this.level,
      lastReviewTs: lastReviewTs ?? this.lastReviewTs,
      reviewHistory: reviewHistory ?? this.reviewHistory,
      consecutiveRaiseQualifyingCount: consecutiveRaiseQualifyingCount ??
          this.consecutiveRaiseQualifyingCount,
      lastReviewScore: lastReviewScore ?? this.lastReviewScore,
      isPlateaued: isPlateaued ?? this.isPlateaued,
    );
  }

  Map<String, dynamic> toJson() => {
        'gameId': gameId,
        'level': level,
        'lastReviewTs': lastReviewTs,
        'reviewHistory': reviewHistory.map((r) => r.toJson()).toList(),
        'consecutiveRaiseQualifyingCount': consecutiveRaiseQualifyingCount,
        'lastReviewScore': lastReviewScore,
        'isPlateaued': isPlateaued,
      };

  factory GameProgress.fromJson(Map<String, dynamic> json) {
    final rawHistory = json['reviewHistory'] as List<dynamic>? ?? [];
    return GameProgress(
      gameId: json['gameId'] as String,
      level: LevelScale.clampLevel((json['level'] as num?)?.toDouble() ??
          ProgressionConfig.defaultLevel),
      lastReviewTs: (json['lastReviewTs'] as num?)?.toInt(),
      reviewHistory: rawHistory
          .map((item) => ReviewRecord.fromJson(item as Map<String, dynamic>))
          .toList(),
      consecutiveRaiseQualifyingCount:
          (json['consecutiveRaiseQualifyingCount'] as num?)?.toInt() ?? 0,
      lastReviewScore: (json['lastReviewScore'] as num?)?.toDouble(),
      isPlateaued: (json['isPlateaued'] as bool?) ?? false,
    );
  }
}

/// Tracks player fatigue and gentle rest locks for the local calendar day.
class RestState {
  const RestState({
    required this.dateKey,
    this.playSecondsToday = 0,
    this.lastPromptPlaySeconds = 0,
    this.keepPlayingCount = 0,
    this.lockUntilTs,
  });

  /// Local calendar date key (YYYY-MM-DD).
  final String dateKey;

  /// Cumulative play time counted toward the daily rest threshold in seconds.
  final int playSecondsToday;

  /// The playSecondsToday value when the rest prompt was last shown.
  final int lastPromptPlaySeconds;

  /// Number of times the elder chose "Keep playing" today.
  final int keepPlayingCount;

  /// Epoch ms when the 3-hour gentle eye-break lock expires, or null if unlocked.
  final int? lockUntilTs;

  bool isLocked(DateTime now) {
    if (lockUntilTs == null) return false;
    return now.millisecondsSinceEpoch < lockUntilTs!;
  }

  /// True if rest card prompt or gentle lock is active for the current time.
  bool shouldRest({DateTime? now}) {
    final currentTime = now ?? DateTime.now();
    if (isLocked(currentTime)) return true;
    if (playSecondsToday < ProgressionConfig.restCardThresholdSeconds) {
      return false;
    }
    if (lastPromptPlaySeconds == 0) return true;
    return (playSecondsToday - lastPromptPlaySeconds) >=
        ProgressionConfig.restCardSnoozeSeconds;
  }

  RestState copyWith({
    String? dateKey,
    int? playSecondsToday,
    int? lastPromptPlaySeconds,
    int? keepPlayingCount,
    int? lockUntilTs,
    bool clearLock = false,
  }) {
    return RestState(
      dateKey: dateKey ?? this.dateKey,
      playSecondsToday: playSecondsToday ?? this.playSecondsToday,
      lastPromptPlaySeconds:
          lastPromptPlaySeconds ?? this.lastPromptPlaySeconds,
      keepPlayingCount: keepPlayingCount ?? this.keepPlayingCount,
      lockUntilTs: clearLock ? null : (lockUntilTs ?? this.lockUntilTs),
    );
  }

  Map<String, dynamic> toJson() => {
        'dateKey': dateKey,
        'playSecondsToday': playSecondsToday,
        'lastPromptPlaySeconds': lastPromptPlaySeconds,
        'keepPlayingCount': keepPlayingCount,
        'lockUntilTs': lockUntilTs,
      };

  factory RestState.fromJson(Map<String, dynamic> json) {
    return RestState(
      dateKey: json['dateKey'] as String? ?? '',
      playSecondsToday: (json['playSecondsToday'] as num?)?.toInt() ?? 0,
      lastPromptPlaySeconds:
          (json['lastPromptPlaySeconds'] as num?)?.toInt() ?? 0,
      keepPlayingCount: (json['keepPlayingCount'] as num?)?.toInt() ?? 0,
      lockUntilTs: (json['lockUntilTs'] as num?)?.toInt(),
    );
  }
}

/// Tracks variety nudge dismissals and snoozing.
class NudgeState {
  const NudgeState({
    this.dismissCount = 0,
    this.snoozeUntilTs,
    this.lastTargetGameId,
    this.lastTargetDomain,
  });

  final int dismissCount;
  final int? snoozeUntilTs;
  final String? lastTargetGameId;
  final String? lastTargetDomain;

  bool isSnoozed(DateTime now) {
    if (snoozeUntilTs == null) return false;
    return now.millisecondsSinceEpoch < snoozeUntilTs!;
  }

  NudgeState copyWith({
    int? dismissCount,
    int? snoozeUntilTs,
    String? lastTargetGameId,
    String? lastTargetDomain,
    bool clearSnooze = false,
  }) {
    return NudgeState(
      dismissCount: dismissCount ?? this.dismissCount,
      snoozeUntilTs:
          clearSnooze ? null : (snoozeUntilTs ?? this.snoozeUntilTs),
      lastTargetGameId: lastTargetGameId ?? this.lastTargetGameId,
      lastTargetDomain: lastTargetDomain ?? this.lastTargetDomain,
    );
  }

  Map<String, dynamic> toJson() => {
        'dismissCount': dismissCount,
        'snoozeUntilTs': snoozeUntilTs,
        'lastTargetGameId': lastTargetGameId,
        'lastTargetDomain': lastTargetDomain,
      };

  factory NudgeState.fromJson(Map<String, dynamic> json) {
    return NudgeState(
      dismissCount: (json['dismissCount'] as num?)?.toInt() ?? 0,
      snoozeUntilTs: (json['snoozeUntilTs'] as num?)?.toInt(),
      lastTargetGameId: json['lastTargetGameId'] as String?,
      lastTargetDomain: json['lastTargetDomain'] as String?,
    );
  }
}
