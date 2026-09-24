import 'dart:io';
import 'dart:ui' show DartPluginRegistrant;

import 'package:android_intent_plus/android_intent.dart';
import 'package:drift/drift.dart' show QueryExecutor, Value;
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';
import '../files/file_paths.dart';
import '../repo/content_repo.dart';
import '../repo/event_repo.dart';
import '../voice/voice_player.dart';
import 'alarm_scheduler.dart';
import 'ladder.dart';
import 'notifications.dart';

typedef ReminderBroadcastSender = Future<void> Function({
  required String medicationId,
  required String reminderEventId,
  required int step,
  required String medicationName,
  required String medicationDose,
});

/// Entry point AndroidAlarmManager calls when a dose is due.
///
/// AGENTS.md non-negotiable #6: this runs in a **separate isolate** with no
/// access to anything in the main isolate — no Riverpod container, no existing
/// database instance, nothing set in `main()`. So it is a top-level function,
/// annotated `@pragma('vm:entry-point')` so tree-shaking cannot remove it, and
/// it opens its own Drift connection.
@pragma('vm:entry-point')
Future<void> fireReminderCallback(int id, Map<String, dynamic> params) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  // Its own connection, via the constructor that exists for exactly this.
  final db = SmritiDatabase.connect(await openConnectionForIsolate());

  try {
    final notifier = LocalReminderNotifier();
    await notifier.initialize();

    await ReminderFirer(
      db: db,
      notifier: notifier,
      scheduler: AlarmScheduler(
        contentRepo: ContentRepo(db),
        configsDao: db.appConfigsDao,
      ),
    ).fire(params);
  } finally {
    // Leaving the connection open would hold a lock the main isolate needs.
    await db.close();
  }
}

/// Opens a database connection owned by this isolate alone.
Future<QueryExecutor> openConnectionForIsolate() async {
  final directory = await getApplicationDocumentsDirectory();
  return NativeDatabase(File(p.join(directory.path, 'smriti.sqlite')));
}

/// Everything the alarm callback does, with its dependencies injected.
///
/// Split out from [fireReminderCallback] because a top-level plugin entry
/// point cannot be unit-tested, but this can: it is handed a database, a
/// notifier, a scheduler and a player, and does not care where they came from.
class ReminderFirer {
  ReminderFirer({
    required this.db,
    required this.notifier,
    required this.scheduler,
    VoicePlayer? voice,
    ReminderBroadcastSender? broadcastSender,
    Uuid? uuid,
    DateTime Function()? now,
    Future<String> Function(String relativePath)? resolvePath,
    Future<void> Function()? onEscalationQueued,
  })  : voice = voice ?? const SilentVoicePlayer(),
        _broadcastSender = broadcastSender ?? _defaultBroadcastSender,
        _uuid = uuid ?? const Uuid(),
        _now = now ?? DateTime.now,
        _resolvePath = resolvePath ?? FilePaths.absolute,
        _onEscalationQueued = onEscalationQueued;

  final SmritiDatabase db;
  final ReminderNotifier notifier;
  final AlarmScheduler scheduler;
  final VoicePlayer voice;
  final ReminderBroadcastSender _broadcastSender;

  static Future<void> _defaultBroadcastSender({
    required String medicationId,
    required String reminderEventId,
    required int step,
    required String medicationName,
    required String medicationDose,
  }) async {
    if (Platform.isAndroid) {
      try {
        final intent = AndroidIntent(
          action: 'com.example.smriti.ACTION_SHOW_REMINDER',
          package: 'com.example.smriti',
          componentName: 'com.example.smriti.ReminderReceiver',
          arguments: <String, dynamic>{
            'medicationId': medicationId,
            'reminderEventId': reminderEventId,
            'step': step,
            'medicationName': medicationName,
            'medicationDose': medicationDose,
          },
        );
        await intent.sendBroadcast();
      } catch (_) {}
    }
  }

  final Uuid _uuid;
  final DateTime Function() _now;
  final Future<String> Function(String relativePath) _resolvePath;

  /// Attempt to push the escalation immediately. Optional: the row is already
  /// committed locally and the next sync will carry it either way.
  final Future<void> Function()? _onEscalationQueued;

  late final ContentRepo _content = ContentRepo(db);
  late final EventRepo _events = EventRepo(db);

  Future<void> fire(Map<String, dynamic> params) async {
    final medicationId = params['medicationId'] as String?;
    if (medicationId == null) return;

    final step = (params['step'] as int?) ?? ReminderLadder.stepInitial;

    final medication = await _content.getMedication(medicationId);
    // A medication removed or deactivated by a content pull must not keep
    // nagging, even though its alarm was already in the system.
    if (medication == null || !medication.active) return;

    switch (step) {
      case ReminderLadder.stepInitial:
        await _fireInitial(medication, params);
      case ReminderLadder.stepRepeat:
        await _fireRepeat(medication, params);
      case ReminderLadder.stepEscalate:
        await _fireEscalation(medication, params);
    }
  }

  /// Step 0: the dose is due now.
  Future<void> _fireInitial(
    Medication medication,
    Map<String, dynamic> params,
  ) async {
    final firedAt = _now();
    final reminderEventId = _uuid.v4();

    await _events.insertReminderEvent(
      ReminderEventsCompanion.insert(
        id: reminderEventId,
        medicationId: medication.id,
        scheduledAt: firedAt.millisecondsSinceEpoch,
        firedAt: Value(firedAt.millisecondsSinceEpoch),
        channel: 'in_app',
        ladderStep: ReminderLadder.stepInitial,
      ),
    );

    await _present(medication, reminderEventId, ReminderLadder.stepInitial);

    // Arm the rest of the ladder before doing anything else that might fail.
    await scheduler.scheduleLadderStep(
      reminderEventId: reminderEventId,
      medicationId: medication.id,
      step: ReminderLadder.stepRepeat,
      fireAt: firedAt.add(ReminderLadder.step1Delay),
    );
    await scheduler.scheduleLadderStep(
      reminderEventId: reminderEventId,
      medicationId: medication.id,
      step: ReminderLadder.stepEscalate,
      fireAt: firedAt.add(ReminderLadder.step2Delay),
    );

    // Keep the weekly cycle going. `rescheduleOnReboot` covers restarts, but
    // nothing else re-arms next week's dose.
    final dayOfWeek = params['dayOfWeek'] as int?;
    if (dayOfWeek != null) {
      await scheduler.scheduleNextOccurrence(
        medicationId: medication.id,
        dayOfWeek: dayOfWeek,
        chosenTimeMin: medication.chosenTimeMin,
      );
    }
  }

  /// Step 1: T+15m, same reminder, louder.
  Future<void> _fireRepeat(
    Medication medication,
    Map<String, dynamic> params,
  ) async {
    final reminderEventId = params['reminderEventId'] as String?;
    if (reminderEventId == null) return;
    if (await _alreadyAnswered(reminderEventId)) return;

    final firedAt = _now();
    await _events.insertReminderEvent(
      ReminderEventsCompanion.insert(
        // Its own row: the repeat firing is itself an event worth reporting.
        id: _uuid.v4(),
        medicationId: medication.id,
        scheduledAt: firedAt.millisecondsSinceEpoch,
        firedAt: Value(firedAt.millisecondsSinceEpoch),
        channel: 'in_app',
        ladderStep: ReminderLadder.stepRepeat,
      ),
    );

    await _present(medication, reminderEventId, ReminderLadder.stepRepeat);
  }

  /// Step 2: T+30m, still unanswered. Write the escalation row and stop.
  ///
  /// The device places no calls and waits for nothing. The server's escalation
  /// worker picks the row up — that path is already live and proven.
  Future<void> _fireEscalation(
    Medication medication,
    Map<String, dynamic> params,
  ) async {
    final reminderEventId = params['reminderEventId'] as String?;
    if (reminderEventId == null) return;
    if (await _alreadyAnswered(reminderEventId)) return;

    final nowMs = _now().millisecondsSinceEpoch;

    // The elder never answered within the ladder window; finalize the outcome
    // as `no_response` so it reports as missed adherence.
    await _events.recordReminderOutcome(
      id: reminderEventId,
      outcome: 'no_response',
      respondedAt: nowMs,
    );

    await _events.insertEscalation(
      EscalationRequestsCompanion.insert(
        // Deterministic, so a retry cannot cause a second phone call.
        id: ReminderLadder.escalationId(
          reminderEventId,
          ReminderLadder.stepEscalate,
        ),
        reminderEventId: reminderEventId,
        medicationId: medication.id,
        step: ReminderLadder.stepEscalate,
        requestedAt: nowMs,
      ),
    );

    // Best effort. If it fails — offline, no session in this isolate — the row
    // stays queued and the next sync carries it.
    try {
      await _onEscalationQueued?.call();
    } catch (_) {}
  }

  /// True once the elder has answered this dose either way.
  Future<bool> _alreadyAnswered(String reminderEventId) async {
    final event = await _events.getReminderEvent(reminderEventId);
    return event?.respondedAt != null;
  }

  Future<void> _present(
    Medication medication,
    String reminderEventId,
    int step,
  ) async {
    // 1. Explicit broadcast to ReminderReceiver to launch ReminderActivity
    await _broadcastSender(
      medicationId: medication.id,
      reminderEventId: reminderEventId,
      step: step,
      medicationName: medication.name,
      medicationDose: medication.dose,
    );

    // 2. Full-screen intent notification fallback/system tray entry
    final photo = medication.pillPhotoPath;
    await notifier.showReminder(
      reminderEventId: reminderEventId,
      medication: medication,
      step: step,
      pillPhotoPath: photo == null ? null : await _resolvePath(photo),
    );

    // Note: Caregiver voice memo autoplay is handled by the foreground
    // ReminderScreen/ReminderActivity with USAGE_ALARM (G3).
    // Audio playback in this background isolate is omitted to prevent
    // dual playback and OS background muting.
  }
}

/// Entry point for the health check's test alarm (A12).
///
/// Runs in its own isolate like any other alarm callback, which is the point:
/// it proves the same mechanism a real dose uses.
@pragma('vm:entry-point')
Future<void> fireTestAlarmCallback(int id) => recordTestAlarmFired();

/// Records that the health check's test alarm fired.
///
/// Its own isolate, its own connection — the whole point of the test is that
/// it runs exactly like a real dose alarm, with the app possibly killed.
@pragma('vm:entry-point')
Future<void> recordTestAlarmFired() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  final db = SmritiDatabase.connect(await openConnectionForIsolate());
  try {
    await db.appConfigsDao.setValue(
      'healthCheckTestAlarmFiredAt',
      '${DateTime.now().millisecondsSinceEpoch}',
    );
    await LocalReminderNotifier().initialize();
  } finally {
    await db.close();
  }
}
