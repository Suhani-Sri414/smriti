import '../db/dao/app_configs_dao.dart';
import 'content_puller.dart';
import 'escalation_writer.dart';
import 'event_pusher.dart';
import 'heartbeat.dart';
import 'memo_uploader.dart';

/// What kicked off a sync run. Triggers per §9: connectivity regained, every
/// 15 minutes via Workmanager, app foreground, and immediately after a session
/// ends.
enum SyncTrigger { periodic, connectivity, foreground, sessionEnd, manual }

class SyncResult {
  const SyncResult._(this.status, {this.errors = const [], this.reason});

  final String status;
  final List<String> errors;
  final String? reason;

  factory SyncResult.ok() => const SyncResult._('ok');

  factory SyncResult.skipped(String reason) =>
      SyncResult._('skipped', reason: reason);

  factory SyncResult.partial(List<String> errors) =>
      SyncResult._('partial', errors: errors);

  bool get isOk => status == 'ok';

  @override
  String toString() => 'SyncResult($status'
      '${reason != null ? ': $reason' : ''}'
      '${errors.isEmpty ? '' : ': ${errors.join('; ')}'})';
}

/// Runs the sync stages in order, each independently wrapped.
///
/// §9: "A content-pull failure must never prevent event upload." So every stage
/// catches its own errors and the run continues; the caller gets a partial
/// result listing what failed.
///
/// Nothing here is ever surfaced to the elder (AGENTS.md non-negotiable #9) —
/// failures are recorded in `AppConfigs.lastSyncError` for the diagnostics
/// screen and nowhere else.
class SyncEngine {
  SyncEngine({
    required this.eventPusher,
    required this.escalationWriter,
    required this.memoUploader,
    required this.contentPuller,
    required this.heartbeat,
    required this.configs,
    required this.hasConnection,
    required this.isAuthenticated,
    this.minInterval = const Duration(minutes: 2),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final EventPusher eventPusher;
  final EscalationWriter escalationWriter;
  final MemoUploader memoUploader;
  final ContentPuller contentPuller;
  final Heartbeat heartbeat;
  final AppConfigsDao configs;

  /// Injected rather than calling `connectivity_plus` directly, so the engine
  /// stays testable and the package stays out of `core/`.
  final Future<bool> Function() hasConnection;
  final Future<bool> Function() isAuthenticated;

  final Duration minInterval;
  final DateTime Function() _now;

  static const String lastSyncErrorKey = 'lastSyncError';

  bool _running = false;
  DateTime? _lastRun;

  Future<SyncResult> run({
    SyncTrigger trigger = SyncTrigger.periodic,
  }) async {
    if (_running) return SyncResult.skipped('already running');

    // A session ending, manual sync, or connectivity restoration should always sync,
    // whatever the throttle says.
    final throttled = _lastRun != null &&
        _now().difference(_lastRun!) < minInterval &&
        trigger != SyncTrigger.sessionEnd &&
        trigger != SyncTrigger.manual &&
        trigger != SyncTrigger.connectivity;
    if (throttled) return SyncResult.skipped('throttled');

    if (!await hasConnection()) return SyncResult.skipped('offline');
    if (!await isAuthenticated()) return SyncResult.skipped('not authed');

    _running = true;
    _lastRun = _now();
    final errors = <String>[];

    // Order matters only in that events go first: the elder's data is the
    // thing we least want to lose.
    try {
      await eventPusher.push();
    } catch (e) {
      errors.add('events: $e');
    }
    try {
      await escalationWriter.flush();
    } catch (e) {
      errors.add('escalations: $e');
    }
    try {
      await memoUploader.upload();
    } catch (e) {
      errors.add('memos: $e');
    }
    try {
      await contentPuller.pull();
    } catch (e) {
      errors.add('content: $e');
    }
    try {
      await heartbeat.send();
    } catch (e) {
      errors.add('heartbeat: $e');
    }

    _running = false;

    // Diagnostics-screen only.
    await configs.setAll({lastSyncErrorKey: errors.join('; ')});

    return errors.isEmpty ? SyncResult.ok() : SyncResult.partial(errors);
  }
}
