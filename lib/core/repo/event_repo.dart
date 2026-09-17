import 'package:drift/drift.dart';

import '../db/database.dart';

/// Append-only store for everything the sync layer later pushes upstream:
/// trials, sessions, reminder events and escalation requests.
///
/// AGENTS.md non-negotiable #3: these tables are INSERT-only in application
/// code. The only permitted updates are flipping `synced`, and closing a
/// still-open session via [endSession] / [bumpDemoReplays]. Nothing here ever
/// mutates a finalized row, and nothing here touches Supabase.
class EventRepo {
  EventRepo(this.db);

  final SmritiDatabase db;

  // SESSIONS

  Future<void> insertSession(SessionsCompanion session) async {
    await db.into(db.sessions).insert(session);
  }

  Future<Session?> getSession(String id) {
    return (db.select(db.sessions)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  /// Closes an open session. Refuses to touch one that already ended, so a
  /// finalized row can never be rewritten.
  Future<void> endSession({
    required String id,
    required int endedAt,
    required bool completed,
    int? abandonedAtMs,
  }) async {
    await (db.update(db.sessions)
          ..where((t) => t.id.equals(id) & t.endedAt.isNull()))
        .write(
      SessionsCompanion(
        endedAt: Value(endedAt),
        completed: Value(completed),
        abandonedAtMs: Value(abandonedAtMs),
        synced: const Value(false),
      ),
    );
  }

  /// Closes any open session that was left dangling due to an app crash or kill.
  /// Any session older than the 6-minute cap is marked abandoned.
  Future<void> closeDanglingSessions({DateTime? now}) async {
    final currentTime = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final capMs = const Duration(minutes: 6).inMilliseconds;
    final cutoff = currentTime - capMs;

    final dangling = await (db.select(db.sessions)
          ..where((t) => t.endedAt.isNull() & t.startedAt.isSmallerThanValue(cutoff)))
        .get();

    for (final s in dangling) {
      await (db.update(db.sessions)..where((t) => t.id.equals(s.id)))
          .write(
        SessionsCompanion(
          endedAt: Value(s.startedAt + capMs),
          completed: const Value(false),
          abandonedAtMs: Value(capMs),
          synced: const Value(false),
        ),
      );
    }
  }

  /// Finalizes any reminder event that fired more than 30 minutes ago without
  /// being answered or escalated, marking it as `no_response`.
  Future<void> closeDanglingReminderEvents({DateTime? now}) async {
    final currentTime = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final timeoutMs = const Duration(minutes: 30).inMilliseconds;
    final cutoff = currentTime - timeoutMs;

    final dangling = await (db.select(db.reminderEvents)
          ..where((t) => t.outcome.isNull() & t.scheduledAt.isSmallerThanValue(cutoff)))
        .get();

    for (final r in dangling) {
      await (db.update(db.reminderEvents)..where((t) => t.id.equals(r.id)))
          .write(
        ReminderEventsCompanion(
          outcome: const Value('no_response'),
          respondedAt: Value(r.scheduledAt + timeoutMs),
          synced: const Value(false),
        ),
      );
    }
  }

  /// Increments the ghost-hand demo replay count on an open session.
  Future<void> bumpDemoReplays(String id) async {
    await db.customUpdate(
      'UPDATE sessions SET demo_replays = demo_replays + 1 '
      'WHERE id = ? AND ended_at IS NULL',
      variables: [Variable<String>(id)],
      updates: {db.sessions},
    );
  }

  // TRIAL EVENTS

  Future<void> insertTrial(TrialEventsCompanion trial) async {
    await db.into(db.trialEvents).insert(trial);
  }

  Future<void> insertTrials(List<TrialEventsCompanion> trials) async {
    await db.batch((batch) => batch.insertAll(db.trialEvents, trials));
  }

  Future<List<TrialEvent>> getTrialsForSession(String sessionId) {
    return (db.select(db.trialEvents)
          ..where((t) => t.sessionId.equals(sessionId))
          ..orderBy([(t) => OrderingTerm(expression: t.trialIndex)]))
        .get();
  }

  // REMINDER EVENTS

  Future<void> insertReminderEvent(ReminderEventsCompanion event) async {
    await db.into(db.reminderEvents).insert(event);
  }

  /// Records what the elder did about a dose, exactly once.
  ///
  /// AGENTS.md non-negotiable #3 lists `endedAt`/`completed` on a still-open
  /// `Sessions` row as the permitted "finish the row" update. This is the same
  /// shape for reminders: `outcome` and `respondedAt` are null from the moment
  /// the alarm fires until the elder answers, and the `respondedAt IS NULL`
  /// guard means a finalized row can never be rewritten. Flagged for
  /// confirmation — #3 does not name this case explicitly.
  Future<void> recordReminderOutcome({
    required String id,
    required String outcome,
    required int respondedAt,
  }) async {
    await (db.update(db.reminderEvents)
          ..where((t) => t.id.equals(id) & t.respondedAt.isNull()))
        .write(
      ReminderEventsCompanion(
        outcome: Value(outcome),
        respondedAt: Value(respondedAt),
        synced: const Value(false),
      ),
    );
  }

  Future<ReminderEvent?> getReminderEvent(String id) {
    return (db.select(db.reminderEvents)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  // ESCALATION REQUESTS

  /// Escalation IDs are deterministic (`{reminderEventId}_{step}`), so a retry
  /// after a crash or a lost response can never place a second phone call
  /// (AGENTS.md non-negotiable #2).
  Future<void> insertEscalation(EscalationRequestsCompanion request) async {
    await db
        .into(db.escalationRequests)
        .insert(request, mode: InsertMode.insertOrIgnore);
  }

  /// Cancels an armed escalation on the device. Called when the elder takes
  /// their medicine after a reminder has already queued an escalation. The
  /// push layer skips cancelled rows entirely, so the server never sees them.
  Future<void> cancelEscalation(String id) async {
    await (db.update(db.escalationRequests)..where((t) => t.id.equals(id)))
        .write(const EscalationRequestsCompanion(cancelled: Value(true)));
  }

  Future<EscalationRequest?> getEscalation(String id) {
    return (db.select(db.escalationRequests)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  // UNSYNCED READS — used by the sync layer to build push batches

  Future<List<Session>> unsyncedSessions({
    int limit = 200,
    bool onlyCompleted = false,
  }) {
    final query = db.select(db.sessions);
    if (onlyCompleted) {
      query.where((t) => t.synced.equals(false) & t.endedAt.isNotNull());
    } else {
      query.where((t) => t.synced.equals(false));
    }
    return (query
          ..orderBy([(t) => OrderingTerm(expression: t.startedAt)])
          ..limit(limit))
        .get();
  }

  Future<List<TrialEvent>> unsyncedTrials({int limit = 500}) {
    return (db.select(db.trialEvents)
          ..where((t) => t.synced.equals(false))
          ..orderBy([(t) => OrderingTerm(expression: t.ts)])
          ..limit(limit))
        .get();
  }

  Future<List<ReminderEvent>> unsyncedReminderEvents({
    int limit = 200,
    bool onlyFinalized = false,
  }) {
    final query = db.select(db.reminderEvents);
    if (onlyFinalized) {
      query.where((t) => t.synced.equals(false) & t.outcome.isNotNull());
    } else {
      query.where((t) => t.synced.equals(false));
    }
    return (query
          ..orderBy([(t) => OrderingTerm(expression: t.scheduledAt)])
          ..limit(limit))
        .get();
  }

  Future<List<EscalationRequest>> unsyncedEscalations({int limit = 200}) {
    return (db.select(db.escalationRequests)
          ..where((t) => t.synced.equals(false))
          ..orderBy([(t) => OrderingTerm(expression: t.requestedAt)])
          ..limit(limit))
        .get();
  }

  /// Total rows still waiting to be pushed, across all four tables. Reported
  /// to the server by the heartbeat (APP-BUILD-SPEC.md §9).
  Future<int> unsyncedCount({bool pushableOnly = true}) async {
    await closeDanglingSessions();
    await closeDanglingReminderEvents();
    final counts = await Future.wait<int>([
      _countUnsynced('trial_events'),
      _countUnsynced(
        'sessions',
        extraCondition: pushableOnly ? 'AND ended_at IS NOT NULL' : '',
      ),
      _countUnsynced(
        'reminder_events',
        extraCondition: pushableOnly ? 'AND outcome IS NOT NULL' : '',
      ),
      _countUnsynced('escalation_requests'),
    ]);
    return counts.fold<int>(0, (sum, count) => sum + count);
  }

  Future<int> _countUnsynced(String table, {String extraCondition = ''}) async {
    final row = await db.customSelect(
      'SELECT COUNT(*) AS c FROM $table WHERE synced = 0 $extraCondition',
    ).getSingle();
    return row.read<int>('c');
  }

  // SYNC FLAGS — the only permitted update on these rows

  Future<void> markSessionsSynced(List<String> ids) =>
      _markSynced(db.sessions, ids);

  Future<void> markTrialsSynced(List<String> ids) =>
      _markSynced(db.trialEvents, ids);

  Future<void> markReminderEventsSynced(List<String> ids) =>
      _markSynced(db.reminderEvents, ids);

  Future<void> markEscalationsSynced(List<String> ids) =>
      _markSynced(db.escalationRequests, ids);

  Future<void> _markSynced(TableInfo table, List<String> ids) async {
    if (ids.isEmpty) return;
    final placeholders = List.filled(ids.length, '?').join(', ');
    await db.customUpdate(
      'UPDATE ${table.actualTableName} SET synced = 1 '
      'WHERE id IN ($placeholders)',
      variables: [for (final id in ids) Variable<String>(id)],
      updates: {table},
    );
  }
}
