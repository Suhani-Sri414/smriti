import 'dart:convert';

import 'package:drift/drift.dart';

import '../ability/estimator.dart';
import '../db/database.dart';
import 'progression_config.dart';
import 'progression_state.dart';

/// Persistence adapter for the progression and cognitive fatigue engines.
///
/// Implements the Zero-Migration Persistence Pattern: stores versioned JSON blobs
/// in the generic key-value [AppConfigs] table while reading historical telemetry
/// from SQLite [trialEvents] and [sessions].
///
/// Reference: PROGRESSION_SYSTEM_GUIDE.md §8.1
class ProgressionRepo {
  ProgressionRepo(this.db);

  final SmritiDatabase db;

  // --- GameProgress (Key-Value) ---

  Future<GameProgress> getGameProgress(String gameId) async {
    final key = ProgressionConfig.gameKey(gameId);
    final raw = await db.appConfigsDao.getValue(key);
    if (raw == null || raw.trim().isEmpty) {
      return GameProgress(gameId: gameId);
    }
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return GameProgress.fromJson(json);
    } catch (_) {
      return GameProgress(gameId: gameId);
    }
  }

  Future<void> saveGameProgress(GameProgress progress) async {
    final key = ProgressionConfig.gameKey(progress.gameId);
    final raw = jsonEncode(progress.toJson());
    await db.appConfigsDao.setValue(key, raw);
  }

  // --- RestState (Key-Value) ---

  Future<RestState> getRestState({DateTime? now}) async {
    final effectiveNow = now ?? DateTime.now();
    final todayKey = _dateKey(effectiveNow);
    final raw = await db.appConfigsDao.getValue(ProgressionConfig.keyRest);
    if (raw == null || raw.trim().isEmpty) {
      return RestState(dateKey: todayKey);
    }
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final state = RestState.fromJson(json);
      // Reset if date changed
      if (state.dateKey != todayKey) {
        // Carry forward lock if still active across midnight
        final activeLock = state.isLocked(effectiveNow) ? state.lockUntilTs : null;
        return RestState(dateKey: todayKey, lockUntilTs: activeLock);
      }
      return state;
    } catch (_) {
      return RestState(dateKey: todayKey);
    }
  }

  Future<void> saveRestState(RestState state) async {
    final raw = jsonEncode(state.toJson());
    await db.appConfigsDao.setValue(ProgressionConfig.keyRest, raw);
  }

  // --- NudgeState (Key-Value) ---

  Future<NudgeState> getNudgeState() async {
    final raw = await db.appConfigsDao.getValue(ProgressionConfig.keyNudge);
    if (raw == null || raw.trim().isEmpty) {
      return const NudgeState();
    }
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return NudgeState.fromJson(json);
    } catch (_) {
      return const NudgeState();
    }
  }

  Future<void> saveNudgeState(NudgeState state) async {
    final raw = jsonEncode(state.toJson());
    await db.appConfigsDao.setValue(ProgressionConfig.keyNudge, raw);
  }

  // --- Historical Queries for Review & Fatigue Telemetry ---

  /// Retrieves trials for [gameId] within [windowStart] and [windowEnd].
  Future<List<TrialEvent>> getTrialsInWindow({
    required String gameId,
    required DateTime windowStart,
    required DateTime windowEnd,
  }) {
    final startMs = windowStart.millisecondsSinceEpoch;
    final endMs = windowEnd.millisecondsSinceEpoch;

    return (db.select(db.trialEvents)
          ..where((t) =>
              t.gameId.equals(gameId) &
              t.ts.isBiggerOrEqualValue(startMs) &
              t.ts.isSmallerOrEqualValue(endMs))
          ..orderBy([(t) => OrderingTerm(expression: t.ts)]))
        .get();
  }

  /// Retrieves all sessions that started or ended within [windowStart] and [windowEnd].
  Future<List<Session>> getSessionsInWindow({
    required DateTime windowStart,
    required DateTime windowEnd,
  }) {
    final startMs = windowStart.millisecondsSinceEpoch;
    final endMs = windowEnd.millisecondsSinceEpoch;

    return (db.select(db.sessions)
          ..where((t) =>
              t.startedAt.isBiggerOrEqualValue(startMs) &
              t.startedAt.isSmallerOrEqualValue(endMs))
          ..orderBy([(t) => OrderingTerm(expression: t.startedAt)]))
        .get();
  }

  /// Retrieves sessions completed today (since local midnight).
  Future<List<Session>> getSessionsToday({required DateTime now}) {
    final midnight = DateTime(now.year, now.month, now.day);
    return getSessionsInWindow(windowStart: midnight, windowEnd: now);
  }

  /// Finds all unique game IDs that have trials recorded in SQLite.
  Future<List<String>> getPlayedGameIds() async {
    final query = db.selectOnly(db.trialEvents, distinct: true)
      ..addColumns([db.trialEvents.gameId]);
    final rows = await query.get();
    return rows
        .map((r) => r.read(db.trialEvents.gameId))
        .whereType<String>()
        .toList();
  }

  /// Returns the latest timestamp played for each cognitive domain.
  Future<Map<CognitiveDomain, DateTime?>> getLastPlayedPerDomain() async {
    final result = <CognitiveDomain, DateTime?>{
      for (final d in CognitiveDomain.values) d: null,
    };

    for (final domain in CognitiveDomain.values) {
      final latest = await (db.select(db.trialEvents)
            ..where((t) => t.domain.equals(domain.name))
            ..orderBy([
              (t) => OrderingTerm(
                    expression: t.ts,
                    mode: OrderingMode.desc,
                  )
            ])
            ..limit(1))
          .getSingleOrNull();

      if (latest != null) {
        result[domain] = DateTime.fromMillisecondsSinceEpoch(latest.ts);
      }
    }

    return result;
  }

  static String _dateKey(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
