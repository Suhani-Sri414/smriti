import 'dart:async';
import 'dart:math' as math;

import '../ability/estimator.dart';
import 'difficulty_source.dart';
import 'game_level_profiles.dart';
import 'level_scale.dart';
import 'performance_report.dart';
import 'play_policy.dart';
import 'progression_config.dart';
import 'progression_policy.dart';
import 'progression_repo.dart';
import 'progression_state.dart';

/// User actions taken in response to the Daily Rest Card.
enum RestAction {
  takeBreak,
  keepPlaying,
}

/// Unified facade orchestrating the dual-loop progression system,
/// fatigue tracking, and anti-perseveration nudges.
///
/// Reference: PROGRESSION_SYSTEM_GUIDE.md §8 & §9
class ProgressionService {
  ProgressionService({
    required this.repo,
    DateTime Function()? now,
    Map<String, CognitiveDomain>? gameDomainMapping,
    Map<CognitiveDomain, String>? defaultGamePerDomain,
  })  : _now = now ?? DateTime.now,
        _gameDomainMapping = gameDomainMapping ?? _defaultGameDomainMapping,
        _defaultGamePerDomain =
            defaultGamePerDomain ?? _defaultGamePerDomainMapping;

  final ProgressionRepo repo;
  final DateTime Function() _now;
  final Map<String, CognitiveDomain> _gameDomainMapping;
  final Map<CognitiveDomain, String> _defaultGamePerDomain;

  static const Map<String, CognitiveDomain> _defaultGameDomainMapping = {
    'market_basket': CognitiveDomain.memory,
    'faces_of_my_family': CognitiveDomain.memory,
    'faces_of_the_family': CognitiveDomain.memory,
    'sort_the_harvest': CognitiveDomain.executive,
    'sort_harvest': CognitiveDomain.executive,
    'sounds_of_home': CognitiveDomain.attention,
    'sounds_home': CognitiveDomain.attention,
    'trace_path': CognitiveDomain.visuospatial,
    'lamps_festival': CognitiveDomain.memory,
  };

  static const Map<CognitiveDomain, String> _defaultGamePerDomainMapping = {
    CognitiveDomain.memory: 'market_basket',
    CognitiveDomain.executive: 'sort_the_harvest',
    CognitiveDomain.attention: 'sounds_of_home',
    CognitiveDomain.visuospatial: 'trace_path',
    CognitiveDomain.language: 'faces_of_my_family',
  };

  // --- Outer Loop: 4-Day Macro Review ---

  /// Executes background reviews for all played games that are due for evaluation.
  ///
  /// If [forceOverride] is true, bypasses the time window and active days restrictions,
  /// evaluating all existing trials in the database for instant testing.
  /// Returns the list of reviews that produced an outcome.
  Future<List<ReviewRecord>> runDueReviews({
    DateTime? currentTime,
    bool forceOverride = false,
  }) async {
    final now = currentTime ?? _now();
    final playedIds = await repo.getPlayedGameIds();
    final gameIds = forceOverride
        ? {...playedIds, ...GameLevelProfiles.catalog.keys}.toList()
        : playedIds;
    final completedReviews = <ReviewRecord>[];

    for (final gameId in gameIds) {
      final progress = await repo.getGameProgress(gameId);

      // Check if due for review
      bool isDue = forceOverride;
      if (!isDue) {
        if (progress.lastReviewTs == null) {
          isDue = true;
        } else {
          final lastReview =
              DateTime.fromMillisecondsSinceEpoch(progress.lastReviewTs!);
          final days = now.difference(lastReview).inDays;
          if (days >= ProgressionConfig.reviewWindowDays) {
            isDue = true;
          }
        }
      }

      if (!isDue) continue;

      final windowStart = forceOverride
          ? DateTime.fromMillisecondsSinceEpoch(0)
          : now.subtract(
              const Duration(days: ProgressionConfig.reviewWindowDays),
            );
      final trials = await repo.getTrialsInWindow(
        gameId: gameId,
        windowStart: windowStart,
        windowEnd: now,
      );

      if (trials.isEmpty) continue;

      final report = PerformanceReport.fromTrials(
        gameId: gameId,
        trials: trials,
      );

      final evaluation = ProgressionPolicy.evaluateReview(
        report: report,
        currentProgress: progress,
        now: now,
        forceOverride: forceOverride,
      );

      // If not enough data, don't write a permanent review record yet; recheck tomorrow
      if (evaluation.decision == ReviewDecision.notEnoughData) {
        continue;
      }

      final profile = GameLevelProfiles.forGame(gameId);
      final newLevel = LevelScale.clampLevel(
        progress.level + evaluation.levelDelta,
        maxLevel: profile.maxAllowedLevel,
      );
      final isPlateaued = newLevel >= profile.maxAllowedLevel;

      int qualifyingCount = progress.consecutiveRaiseQualifyingCount;
      if (evaluation.decision == ReviewDecision.raise) {
        qualifyingCount = 0;
      } else if (evaluation.decision == ReviewDecision.hold &&
          evaluation.reason.contains('second confirming cycle')) {
        qualifyingCount++;
      } else if (evaluation.decision == ReviewDecision.ease ||
          evaluation.decision == ReviewDecision.easeMore) {
        qualifyingCount = 0;
      }

      final record = ReviewRecord(
        timestamp: now.millisecondsSinceEpoch,
        decision: evaluation.decision,
        levelBefore: progress.level,
        levelAfter: newLevel,
        meanScore: report.meanScore,
        accuracy: report.accuracy,
        hintRate: report.hintRate,
        totalTrials: report.totalTrials,
        isConcern: evaluation.isConcern,
        throttled: evaluation.throttled,
      );

      final updatedProgress = progress.copyWith(
        level: newLevel,
        lastReviewTs: now.millisecondsSinceEpoch,
        lastReviewScore: report.meanScore,
        isPlateaued: isPlateaued,
        consecutiveRaiseQualifyingCount: qualifyingCount,
        reviewHistory: [record, ...progress.reviewHistory],
      );

      await repo.saveGameProgress(updatedProgress);
      completedReviews.add(record);
    }

    return completedReviews;
  }

  // --- Player Well-Being: Fatigue & Daily Rest Card ---

  /// Evaluates cumulative play today and checks if rest prompt or lock is active.
  Future<RestCardEvaluation> checkRestStatus({DateTime? currentTime}) async {
    final now = currentTime ?? _now();
    final todaySessions = await repo.getSessionsToday(now: now);
    final calculatedSeconds = PlayPolicy.calculateCappedPlaySecondsToday(
      todaySessions: todaySessions,
    );

    var restState = await repo.getRestState(now: now);
    final playSecondsToday =
        math.max(calculatedSeconds, restState.playSecondsToday);
    restState = restState.copyWith(playSecondsToday: playSecondsToday);

    final evaluation = PlayPolicy.evaluateRestCard(state: restState, now: now);

    if (evaluation.status == RestCardStatus.showPrompt &&
        restState.lastPromptPlaySeconds != playSecondsToday) {
      restState =
          restState.copyWith(lastPromptPlaySeconds: playSecondsToday);
      await repo.saveRestState(restState);
    }

    return evaluation;
  }

  /// Records elder response to the Daily Rest Card.
  Future<void> recordRestAction(
    RestAction action, {
    DateTime? currentTime,
  }) async {
    final now = currentTime ?? _now();
    var restState = await repo.getRestState(now: now);

    if (action == RestAction.keepPlaying) {
      final newCount = restState.keepPlayingCount + 1;
      int? lockUntil;
      if (newCount >= ProgressionConfig.maxKeepPlayingCount) {
        lockUntil = now
            .add(ProgressionConfig.gameLockDuration)
            .millisecondsSinceEpoch;
      }

      restState = restState.copyWith(
        keepPlayingCount: newCount,
        lockUntilTs: lockUntil,
      );
      await repo.saveRestState(restState);
    } else {
      // takeBreak: clear override counters
      restState = restState.copyWith(keepPlayingCount: 0);
      await repo.saveRestState(restState);
    }
  }

  // --- Player Well-Being: Variety Nudge ---

  /// Evaluates whether a perseveration variety nudge should be displayed on game select.
  Future<VarietyNudgeEvaluation> checkVarietyNudge({DateTime? currentTime}) async {
    final now = currentTime ?? _now();
    final nudgeState = await repo.getNudgeState();
    final windowStart = now.subtract(
      const Duration(days: ProgressionConfig.nudgeWindowDays),
    );
    final recentSessions = await repo.getSessionsInWindow(
      windowStart: windowStart,
      windowEnd: now,
    );
    final lastPlayedPerDomain = await repo.getLastPlayedPerDomain();

    final evaluation = PlayPolicy.evaluateVarietyNudge(
      recentSessions: recentSessions,
      nudgeState: nudgeState,
      now: now,
      gameDomainMapping: _gameDomainMapping,
      lastPlayedPerDomain: lastPlayedPerDomain,
      defaultGamePerDomain: _defaultGamePerDomain,
    );

    return evaluation;
  }

  /// Records that the user dismissed the variety nudge banner.
  Future<void> recordNudgeDismissed({DateTime? currentTime}) async {
    final now = currentTime ?? _now();
    var nudgeState = await repo.getNudgeState();
    final newCount = nudgeState.dismissCount + 1;

    int? snoozeUntil;
    if (newCount >= ProgressionConfig.nudgeDismissalsToSnooze) {
      snoozeUntil = now
          .add(const Duration(days: ProgressionConfig.nudgeSnoozeDays))
          .millisecondsSinceEpoch;
    }

    nudgeState = nudgeState.copyWith(
      dismissCount: newCount,
      snoozeUntilTs: snoozeUntil,
    );
    await repo.saveNudgeState(nudgeState);
  }

  // --- Inner Loop Factory ---

  /// Creates an in-session difficulty provider seeded with the game's persistent baseline level.
  Future<StaircaseDifficultySource> createDifficultySource(String gameId) async {
    final progress = await repo.getGameProgress(gameId);
    final profile = GameLevelProfiles.forGame(gameId);
    return StaircaseDifficultySource(
      baseLevel: progress.level,
      maxLevel: profile.maxAllowedLevel,
    );
  }
}
