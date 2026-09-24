import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';

import '../db/dao/app_configs_dao.dart';
import '../repo/content_repo.dart';
import 'ladder.dart';
import 'reminder_isolate.dart';

/// The AndroidAlarmManager surface the scheduler uses.
///
/// Abstracted so cancel-then-reschedule can be tested. Nothing about whether
/// an alarm actually *fires* can be tested here — that needs a real device.
abstract class AlarmApi {
  Future<void> initialize();

  Future<bool> oneShotAt(
    DateTime time,
    int id,
    Function callback, {
    required Map<String, dynamic> params,
  });

  Future<bool> cancel(int id);
}

class AndroidAlarmApi implements AlarmApi {
  const AndroidAlarmApi();

  @override
  Future<void> initialize() => AndroidAlarmManager.initialize();

  /// Every flag from APP-BUILD-SPEC.md §10 matters:
  /// `exact` so the dose is on time, `wakeup` so a sleeping device still
  /// fires, `alarmClock` to exempt from Doze mode (G6), `allowWhileIdle` to
  /// survive Doze, and `rescheduleOnReboot` so a restart does not silently
  /// drop every future dose.
  @override
  Future<bool> oneShotAt(
    DateTime time,
    int id,
    Function callback, {
    required Map<String, dynamic> params,
  }) {
    return AndroidAlarmManager.oneShotAt(
      time,
      id,
      callback,
      exact: true,
      wakeup: true,
      alarmClock: true,
      allowWhileIdle: true,
      rescheduleOnReboot: true,
      params: params,
    );
  }

  @override
  Future<bool> cancel(int id) => AndroidAlarmManager.cancel(id);
}

/// Schedules every medication alarm, and the ladder steps that follow a dose.
class AlarmScheduler {
  AlarmScheduler({
    required this.contentRepo,
    this.configsDao,
    AlarmApi alarmApi = const AndroidAlarmApi(),
    DateTime Function()? now,
  })  : _alarms = alarmApi,
        _now = now ?? DateTime.now;

  final ContentRepo contentRepo;
  final AppConfigsDao? configsDao;
  final AlarmApi _alarms;
  final DateTime Function() _now;

  static const String trackedAlarmIdsKey = 'scheduled_alarm_ids';

  /// How many alarms the last [rescheduleAll] scheduled. Surfaced for the
  /// diagnostics screen.
  int lastScheduledAlarmCount = 0;

  Future<void> initialize() => _alarms.initialize();

  /// Cancels every dose alarm, then re-creates them.
  ///
  /// Cancel-then-schedule in two passes, as §10 specifies: a medication whose
  /// time moved must not leave its old alarm behind, and a medication that was
  /// deactivated must stop firing entirely. Called as the last step of a
  /// content pull, because medication times may have changed.
  Future<void> rescheduleAll() async {
    // 1. Purge previously tracked alarm IDs from AppConfigs to prevent orphaned alarms (G7).
    if (configsDao != null) {
      final raw = await configsDao!.getValue(trackedAlarmIdsKey);
      if (raw != null && raw.isNotEmpty) {
        final oldIds = raw
            .split(',')
            .map((s) => int.tryParse(s.trim()))
            .whereType<int>();
        for (final id in oldIds) {
          await _alarms.cancel(id);
        }
      }
    }

    // Every medication, not just active ones — a medication deactivated by the
    // last pull still has alarms out there that must be cancelled.
    final all = await contentRepo.getMedications(activeOnly: false);
    for (final medication in all) {
      for (final day in ReminderLadder.parseDays(medication.daysOfWeek)) {
        await _alarms.cancel(ReminderLadder.doseAlarmId(medication.id, day));
      }
    }

    final newAlarmIds = <int>[];
    var scheduled = 0;
    final from = _now();
    for (final medication in all.where((m) => m.active)) {
      for (final day in ReminderLadder.parseDays(medication.daysOfWeek)) {
        final alarmId = ReminderLadder.doseAlarmId(medication.id, day);
        await _alarms.oneShotAt(
          ReminderLadder.nextOccurrence(
            dayOfWeek: day,
            minutesFromMidnight: medication.chosenTimeMin,
            from: from,
          ),
          alarmId,
          fireReminderCallback,
          params: {
            'medicationId': medication.id,
            'dayOfWeek': day,
            'step': ReminderLadder.stepInitial,
          },
        );
        newAlarmIds.add(alarmId);
        scheduled++;
      }
    }

    // 2. Persist new tracked IDs in AppConfigs (G7).
    if (configsDao != null) {
      await configsDao!.setValue(trackedAlarmIdsKey, newAlarmIds.join(','));
    }

    lastScheduledAlarmCount = scheduled;
  }

  /// Re-arms one medication/day for its next occurrence, called by the isolate
  /// after a dose fires so the weekly cycle continues.
  Future<void> scheduleNextOccurrence({
    required String medicationId,
    required int dayOfWeek,
    required int chosenTimeMin,
  }) {
    return _alarms.oneShotAt(
      ReminderLadder.nextOccurrence(
        dayOfWeek: dayOfWeek,
        minutesFromMidnight: chosenTimeMin,
        from: _now(),
      ),
      ReminderLadder.doseAlarmId(medicationId, dayOfWeek),
      fireReminderCallback,
      params: {
        'medicationId': medicationId,
        'dayOfWeek': dayOfWeek,
        'step': ReminderLadder.stepInitial,
      },
    );
  }

  /// Arms one ladder step for a dose that has just fired.
  Future<void> scheduleLadderStep({
    required String reminderEventId,
    required String medicationId,
    required int step,
    required DateTime fireAt,
  }) {
    return _alarms.oneShotAt(
      fireAt,
      ReminderLadder.ladderAlarmId(reminderEventId, step),
      fireReminderCallback,
      params: {
        'medicationId': medicationId,
        'reminderEventId': reminderEventId,
        'step': step,
      },
    );
  }

  /// Drops every pending step for a dose.
  ///
  /// Called the instant "taken" is tapped: leaving step 2 armed after the
  /// elder has taken their medicine would place a real phone call to a family
  /// member for no reason.
  Future<void> cancelLadder(String reminderEventId) async {
    for (var step = ReminderLadder.stepRepeat;
        step <= ReminderLadder.lastDeviceStep;
        step++) {
      await _alarms.cancel(
        ReminderLadder.ladderAlarmId(reminderEventId, step),
      );
    }
  }
}

/// Extension point for the setup health check (A12).
extension TestAlarmScheduling on AlarmScheduler {
  /// Arms the health check's live test alarm, through the same
  /// AndroidAlarmManager path a real dose uses.
  Future<void> scheduleTestAlarm({required DateTime fireAt}) async {
    await _alarms.oneShotAt(
      fireAt,
      ReminderLadder.stableHash('smriti_health_check_alarm') & 0x00FFFFFF,
      fireTestAlarmCallback,
      params: const {'step': ReminderLadder.stepInitial, 'test': true},
    );
  }

  /// Arms a test dose reminder for physical device verification (e.g. in 20 seconds).
  ///
  /// Uses the exact same [fireReminderCallback] pipeline with [alarmClock: true]
  /// so that when the device is locked and Doze is active, the system wakes up,
  /// fires the broadcast, and displays [ReminderActivity] over keyguard.
  Future<void> scheduleTestDoseAlarm({
    required String medicationId,
    required DateTime fireAt,
  }) async {
    final testAlarmId =
        ReminderLadder.stableHash('smriti_test_dose_alarm') & 0x00FFFFFF;
    await _alarms.cancel(testAlarmId);
    await _alarms.oneShotAt(
      fireAt,
      testAlarmId,
      fireReminderCallback,
      params: {
        'medicationId': medicationId,
        'step': ReminderLadder.stepInitial,
        'test': true,
      },
    );
  }
}
