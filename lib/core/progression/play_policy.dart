import 'dart:math' as math;

import '../ability/estimator.dart';
import '../db/database.dart';
import 'progression_config.dart';
import 'progression_state.dart';

/// Status of the Daily Rest Card evaluation.
enum RestCardStatus {
  /// User has not hit fatigue thresholds; play continues freely.
  none,

  /// User has reached 30m cumulative play (or +15m snooze); show warm tea-break card.
  showPrompt,

  /// User has overridden 3 times; gentle eye-break lock is currently active.
  locked,
}

/// Evaluation result for the Daily Rest Card.
class RestCardEvaluation {
  const RestCardEvaluation({
    required this.status,
    required this.playSecondsToday,
    this.lockUntil,
  });

  final RestCardStatus status;
  final int playSecondsToday;
  final DateTime? lockUntil;
}

/// Evaluation result for the Variety Nudge.
class VarietyNudgeEvaluation {
  const VarietyNudgeEvaluation({
    required this.shouldNudge,
    this.dominantGameId,
    this.recommendedDomain,
    this.recommendedGameId,
  });

  final bool shouldNudge;
  final String? dominantGameId;
  final CognitiveDomain? recommendedDomain;
  final String? recommendedGameId;
}

/// Pure decision logic for Fatigue Management (Rest Card) and
/// Perseveration Management (Variety Nudge).
///
/// Reference: PROGRESSION_SYSTEM_GUIDE.md §7
class PlayPolicy {
  const PlayPolicy._();

  /// Calculates cumulative play seconds today from a list of completed sessions,
  /// capping each session's contribution at 8 minutes (480s).
  static int calculateCappedPlaySecondsToday({
    required List<Session> todaySessions,
  }) {
    int total = 0;
    for (final s in todaySessions) {
      final start = s.startedAt;
      final end = s.endedAt;
      if (end != null && end > start) {
        final durationSeconds = ((end - start) / 1000).round();
        total += math.min(
          durationSeconds,
          ProgressionConfig.maxCountedSessionSeconds,
        );
      }
    }
    return total;
  }

  /// Evaluates whether the rest card prompt should be shown or if a gentle lock is active.
  static RestCardEvaluation evaluateRestCard({
    required RestState state,
    required DateTime now,
  }) {
    // 1. Check if an existing 3-hour lock is still active
    if (state.isLocked(now)) {
      return RestCardEvaluation(
        status: RestCardStatus.locked,
        playSecondsToday: state.playSecondsToday,
        lockUntil: DateTime.fromMillisecondsSinceEpoch(state.lockUntilTs!),
      );
    }

    // 2. Check if maximum overrides have been reached -> triggers lock
    if (state.keepPlayingCount >= ProgressionConfig.maxKeepPlayingCount) {
      final lockUntil = now.add(ProgressionConfig.gameLockDuration);
      return RestCardEvaluation(
        status: RestCardStatus.locked,
        playSecondsToday: state.playSecondsToday,
        lockUntil: lockUntil,
      );
    }

    // 3. Initial 30-minute threshold check
    if (state.lastPromptPlaySeconds == 0) {
      if (state.playSecondsToday >= ProgressionConfig.restPromptPlaySeconds) {
        return RestCardEvaluation(
          status: RestCardStatus.showPrompt,
          playSecondsToday: state.playSecondsToday,
        );
      }
      return RestCardEvaluation(
        status: RestCardStatus.none,
        playSecondsToday: state.playSecondsToday,
      );
    }

    // 4. Repeated snooze check: triggers every +15m of additional play
    final additionalPlay =
        state.playSecondsToday - state.lastPromptPlaySeconds;
    if (additionalPlay >= ProgressionConfig.restSnoozeSeconds) {
      return RestCardEvaluation(
        status: RestCardStatus.showPrompt,
        playSecondsToday: state.playSecondsToday,
      );
    }

    return RestCardEvaluation(
      status: RestCardStatus.none,
      playSecondsToday: state.playSecondsToday,
    );
  }

  /// Evaluates whether a user is perseverating on a single game and recommends
  /// an under-exercised cognitive domain.
  static VarietyNudgeEvaluation evaluateVarietyNudge({
    required List<Session> recentSessions,
    required NudgeState nudgeState,
    required DateTime now,
    required Map<String, CognitiveDomain> gameDomainMapping,
    required Map<CognitiveDomain, DateTime?> lastPlayedPerDomain,
    required Map<CognitiveDomain, String> defaultGamePerDomain,
  }) {
    // 1. Check if currently snoozed due to previous dismissals
    if (nudgeState.isSnoozed(now)) {
      return const VarietyNudgeEvaluation(shouldNudge: false);
    }

    // 2. Count sessions per game in the recent window
    final totalSessions = recentSessions.length;
    if (totalSessions < ProgressionConfig.nudgeRepeatPlays) {
      return const VarietyNudgeEvaluation(shouldNudge: false);
    }

    final playCounts = <String, int>{};
    for (final s in recentSessions) {
      final gameId = s.gameIds.trim();
      if (gameId.isNotEmpty) {
        playCounts[gameId] = (playCounts[gameId] ?? 0) + 1;
      }
    }

    // 3. Find dominant game exceeding the share threshold (>= 60%)
    String? dominantGame;
    for (final entry in playCounts.entries) {
      final share = entry.value / totalSessions;
      if (share >= ProgressionConfig.nudgeShareOfPlays &&
          entry.value >= ProgressionConfig.nudgeRepeatPlays) {
        dominantGame = entry.key;
        break;
      }
    }

    if (dominantGame == null) {
      return const VarietyNudgeEvaluation(shouldNudge: false);
    }

    // 4. Select least recently played remaining cognitive domain
    final dominantDomain = gameDomainMapping[dominantGame];
    CognitiveDomain? candidateDomain;
    DateTime? oldestTimestamp;

    for (final domain in CognitiveDomain.values) {
      if (domain == dominantDomain) continue;
      final lastPlayed = lastPlayedPerDomain[domain];
      if (lastPlayed == null) {
        // Never played has highest priority
        candidateDomain = domain;
        break;
      }
      if (oldestTimestamp == null || lastPlayed.isBefore(oldestTimestamp)) {
        oldestTimestamp = lastPlayed;
        candidateDomain = domain;
      }
    }

    candidateDomain ??= CognitiveDomain.memory;
    final recommendedGame = defaultGamePerDomain[candidateDomain];

    return VarietyNudgeEvaluation(
      shouldNudge: true,
      dominantGameId: dominantGame,
      recommendedDomain: candidateDomain,
      recommendedGameId: recommendedGame,
    );
  }
}
