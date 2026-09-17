import '../db/dao/app_configs_dao.dart';
import '../repo/event_repo.dart';
import 'remote_rows.dart';
import 'sync_gateway.dart';

/// Ships locally-committed sessions, trials and reminder events upstream.
///
/// Everything here is fire-and-forget: rows are upserted with
/// `ignoreDuplicates`, never read back (AGENTS.md #4), and only marked synced
/// once the write returned without throwing. A push that dies mid-batch simply
/// re-sends those rows next time — the deterministic ids make that harmless.
class EventPusher {
  EventPusher({
    required this.eventRepo,
    required this.configs,
    this.gateway = const SupabaseSyncGateway(),
    this.batchSize = 200,
  });

  final EventRepo eventRepo;
  final AppConfigsDao configs;
  final SyncGateway gateway;
  final int batchSize;

  static const String patientIdKey = 'patientId';

  /// Pushes in dependency order: sessions before the trials that reference
  /// them, so a foreign key on the server never sees an orphan.
  /// Reminder events push independently so a failure in one category does not
  /// block the other.
  Future<int> push() async {
    final patientId = await configs.getValue(patientIdKey);
    if (patientId == null || patientId.isEmpty) return 0;

    var pushed = 0;
    Object? firstError;

    // 1. Sessions and Trials
    try {
      pushed += await _pushSessions(patientId);
      pushed += await _pushTrials(patientId);
    } catch (e) {
      firstError ??= e;
    }

    // 2. Reminder Events
    try {
      pushed += await _pushReminderEvents(patientId);
    } catch (e) {
      firstError ??= e;
    }

    if (firstError != null) {
      throw firstError;
    }
    return pushed;
  }

  Future<int> _pushSessions(String patientId) async {
    await eventRepo.closeDanglingSessions();
    var pushed = 0;
    while (true) {
      final rows = await eventRepo.unsyncedSessions(
        limit: batchSize,
        onlyCompleted: true,
      );
      if (rows.isEmpty) break;

      // Sessions allow device updates (`s_update` RLS policy) so finalized
      // sessions update any row previously ingested while in-progress.
      await gateway.upsert(
        RemoteRows.sessionsTable,
        [for (final row in rows) RemoteRows.session(row, patientId)],
        ignoreDuplicates: false,
      );
      await eventRepo.markSessionsSynced([for (final row in rows) row.id]);
      pushed += rows.length;
      if (rows.length < batchSize) break;
    }
    return pushed;
  }

  Future<int> _pushTrials(String patientId) async {
    var pushed = 0;
    while (true) {
      final rows = await eventRepo.unsyncedTrials(limit: batchSize);
      if (rows.isEmpty) break;

      await gateway.upsert(
        RemoteRows.eventsTable,
        [for (final row in rows) RemoteRows.trial(row, patientId)],
      );
      await eventRepo.markTrialsSynced([for (final row in rows) row.id]);
      pushed += rows.length;
      if (rows.length < batchSize) break;
    }
    return pushed;
  }

  Future<int> _pushReminderEvents(String patientId) async {
    await eventRepo.closeDanglingReminderEvents();
    var pushed = 0;
    while (true) {
      final rows = await eventRepo.unsyncedReminderEvents(
        limit: batchSize,
        onlyFinalized: true,
      );
      if (rows.isEmpty) break;

      await gateway.upsert(
        RemoteRows.reminderEventsTable,
        [for (final row in rows) RemoteRows.reminderEvent(row, patientId)],
      );
      await eventRepo.markReminderEventsSynced([for (final row in rows) row.id]);
      pushed += rows.length;
      if (rows.length < batchSize) break;
    }
    return pushed;
  }
}
