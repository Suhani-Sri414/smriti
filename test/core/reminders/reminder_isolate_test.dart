import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smriti/core/db/database.dart';
import 'package:smriti/core/reminders/alarm_scheduler.dart';
import 'package:smriti/core/reminders/ladder.dart';
import 'package:smriti/core/reminders/notifications.dart';
import 'package:smriti/core/reminders/reminder_isolate.dart';
import 'package:smriti/core/repo/content_repo.dart';
import 'package:smriti/core/repo/event_repo.dart';
import 'package:smriti/core/voice/voice_player.dart';

import '_fake_alarm_api.dart';

class RecordingVoice implements VoicePlayer {
  final List<String> played = [];

  @override
  Future<void> play(String path) async => played.add(path);

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

void main() {
  late SmritiDatabase db;
  late FakeAlarmApi alarms;
  late NoopReminderNotifier notifier;
  late RecordingVoice voice;
  late AlarmScheduler scheduler;
  final List<Map<String, dynamic>> broadcastSent = [];

  /// Monday 8 September 2025, 08:20 — the dose time seeded below.
  var clock = DateTime(2025, 9, 8, 8, 20);

  setUp(() async {
    // Its own connection, exactly as the isolate does it.
    db = SmritiDatabase.connect(NativeDatabase.memory());
    alarms = FakeAlarmApi();
    notifier = NoopReminderNotifier();
    voice = RecordingVoice();
    broadcastSent.clear();
    clock = DateTime(2025, 9, 8, 8, 20);
    scheduler = AlarmScheduler(
      contentRepo: ContentRepo(db),
      alarmApi: alarms,
      now: () => clock,
    );

    await ContentRepo(db).replaceContent(
      people: const [],
      medications: [
        MedicationsCompanion.insert(
          id: 'med-1',
          name: 'Metformin',
          dose: '500mg',
          pillPhotoPath: const Value('medications/photos/med-1.jpg'),
          voicePath: const Value('medications/voice/med-1.m4a'),
          windowStartMin: 480,
          windowEndMin: 540,
          chosenTimeMin: 500,
          daysOfWeek: '1,2,3,4,5,6,7',
        ),
        MedicationsCompanion.insert(
          id: 'med-off',
          name: 'Discontinued',
          dose: '1 tab',
          windowStartMin: 1200,
          windowEndMin: 1260,
          chosenTimeMin: 1230,
          daysOfWeek: '1,2,3,4,5,6,7',
          active: const Value(false),
        ),
      ],
      routineItems: const [],
      contentVersion: '7',
    );
  });

  tearDown(() async => db.close());

  ReminderFirer newFirer({Future<void> Function()? onEscalationQueued}) {
    return ReminderFirer(
      db: db,
      notifier: notifier,
      scheduler: scheduler,
      voice: voice,
      broadcastSender: ({
        required medicationId,
        required reminderEventId,
        required step,
        required medicationName,
        required medicationDose,
      }) async {
        broadcastSent.add({
          'medicationId': medicationId,
          'reminderEventId': reminderEventId,
          'step': step,
          'medicationName': medicationName,
          'medicationDose': medicationDose,
        });
      },
      now: () => clock,
      // Skip path_provider, which has no plugin in a test host.
      resolvePath: (relative) async => '/docs/$relative',
      onEscalationQueued: onEscalationQueued,
    );
  }

  Future<ReminderEvent> soleEvent() async =>
      (await db.select(db.reminderEvents).get()).single;

  group('step 0 — the dose is due', () {
    test('writes the event, notifies, and arms the rest of the ladder',
        () async {
      await newFirer().fire({
        'medicationId': 'med-1',
        'dayOfWeek': DateTime.monday,
        'step': 0,
      });

      // The ReminderEvents row, written by the isolate's own connection.
      final event = await soleEvent();
      expect(event.medicationId, 'med-1');
      expect(event.ladderStep, 0);
      expect(event.channel, 'in_app');
      expect(event.firedAt, clock.millisecondsSinceEpoch);
      expect(event.outcome, isNull);
      expect(event.respondedAt, isNull);
      expect(event.synced, isFalse);

      expect(notifier.shown, ['${event.id}:step0']);
      // Voice playback is intentionally omitted in isolate to avoid dual playback
      // and Android background muting (delegated to foreground ReminderScreen).
      expect(voice.played, isEmpty);
      // Explicit broadcast to ReminderReceiver is sent.
      expect(broadcastSent, hasLength(1));
      expect(broadcastSent.first['medicationId'], 'med-1');
      expect(broadcastSent.first['reminderEventId'], event.id);
      expect(broadcastSent.first['step'], 0);

      // Steps 1 and 2 armed at T+15m and T+30m.
      final ladder = alarms.scheduled
          .where((a) => a.reminderEventId == event.id)
          .toList();
      expect(ladder, hasLength(2));
      expect(ladder[0].step, 1);
      expect(ladder[0].time, clock.add(const Duration(minutes: 15)));
      expect(ladder[1].step, 2);
      expect(ladder[1].time, clock.add(const Duration(minutes: 30)));

      // And next Monday's dose is re-armed, or the cycle stops after one week.
      final next = alarms.scheduled.firstWhere((a) => a.step == 0);
      expect(next.id, ReminderLadder.doseAlarmId('med-1', DateTime.monday));
      expect(next.time, DateTime(2025, 9, 15, 8, 20));
    });

    test('a deactivated medication fires nothing at all', () async {
      await newFirer().fire({
        'medicationId': 'med-off',
        'dayOfWeek': DateTime.monday,
        'step': 0,
      });

      expect(await db.select(db.reminderEvents).get(), isEmpty);
      expect(notifier.shown, isEmpty);
      expect(alarms.scheduled, isEmpty);
    });

    test('a medication deleted by a content pull fires nothing', () async {
      await newFirer().fire({
        'medicationId': 'gone',
        'dayOfWeek': DateTime.monday,
        'step': 0,
      });

      expect(await db.select(db.reminderEvents).get(), isEmpty);
      expect(notifier.shown, isEmpty);
    });
  });

  group('step 1 — repeat, louder', () {
    test('fires again when the dose is still unanswered', () async {
      await newFirer().fire({
        'medicationId': 'med-1',
        'dayOfWeek': DateTime.monday,
        'step': 0,
      });
      final first = await soleEvent();

      clock = clock.add(const Duration(minutes: 15));
      await newFirer().fire({
        'medicationId': 'med-1',
        'reminderEventId': first.id,
        'step': 1,
      });

      final events = await db.select(db.reminderEvents).get();
      expect(events, hasLength(2));
      final repeat = events.firstWhere((e) => e.ladderStep == 1);
      expect(repeat.id, isNot(first.id), reason: 'insert-only, its own row');
      expect(repeat.medicationId, 'med-1');

      // Same dose key, so it replaces rather than stacking.
      expect(notifier.shown.last, '${first.id}:step1');
    });

    test('does nothing once the elder has answered', () async {
      await newFirer().fire({
        'medicationId': 'med-1',
        'dayOfWeek': DateTime.monday,
        'step': 0,
      });
      final first = await soleEvent();

      await EventRepo(db).recordReminderOutcome(
        id: first.id,
        outcome: 'taken',
        respondedAt: clock.millisecondsSinceEpoch,
      );
      notifier.shown.clear();

      clock = clock.add(const Duration(minutes: 15));
      await newFirer().fire({
        'medicationId': 'med-1',
        'reminderEventId': first.id,
        'step': 1,
      });

      expect(notifier.shown, isEmpty, reason: 'no nagging after "taken"');
      expect(
        (await db.select(db.reminderEvents).get()).where((e) => e.ladderStep == 1),
        isEmpty,
      );
    });
  });

  group('step 2 — handoff to the server', () {
    test('writes one escalation row with the deterministic id', () async {
      await newFirer().fire({
        'medicationId': 'med-1',
        'dayOfWeek': DateTime.monday,
        'step': 0,
      });
      final first = await soleEvent();

      var flushes = 0;
      clock = clock.add(const Duration(minutes: 30));
      await newFirer(onEscalationQueued: () async => flushes++).fire({
        'medicationId': 'med-1',
        'reminderEventId': first.id,
        'step': 2,
      });

      final escalation =
          (await db.select(db.escalationRequests).get()).single;
      expect(escalation.id, '${first.id}_2');
      expect(escalation.reminderEventId, first.id);
      expect(escalation.medicationId, 'med-1');
      expect(escalation.step, 2);
      expect(escalation.requestedAt, clock.millisecondsSinceEpoch);
      expect(escalation.cancelled, isFalse);
      expect(escalation.synced, isFalse, reason: 'queued for the pusher');

      expect(flushes, 1, reason: 'tries to hand off immediately');
    });

    test('never escalates a dose the elder already took', () async {
      await newFirer().fire({
        'medicationId': 'med-1',
        'dayOfWeek': DateTime.monday,
        'step': 0,
      });
      final first = await soleEvent();

      await EventRepo(db).recordReminderOutcome(
        id: first.id,
        outcome: 'taken',
        respondedAt: clock.millisecondsSinceEpoch,
      );

      clock = clock.add(const Duration(minutes: 30));
      await newFirer().fire({
        'medicationId': 'med-1',
        'reminderEventId': first.id,
        'step': 2,
      });

      expect(await db.select(db.escalationRequests).get(), isEmpty,
          reason: 'this would ring a family member for nothing');
    });

    test('a failed immediate flush still leaves the row queued', () async {
      await newFirer().fire({
        'medicationId': 'med-1',
        'dayOfWeek': DateTime.monday,
        'step': 0,
      });
      final first = await soleEvent();

      clock = clock.add(const Duration(minutes: 30));
      await newFirer(
        onEscalationQueued: () async => throw Exception('offline'),
      ).fire({
        'medicationId': 'med-1',
        'reminderEventId': first.id,
        'step': 2,
      });

      expect(await db.select(db.escalationRequests).get(), hasLength(1));
      expect(await EventRepo(db).unsyncedEscalations(), hasLength(1));
    });

    test('firing step 2 twice cannot produce two escalations', () async {
      await newFirer().fire({
        'medicationId': 'med-1',
        'dayOfWeek': DateTime.monday,
        'step': 0,
      });
      final first = await soleEvent();

      clock = clock.add(const Duration(minutes: 30));
      for (var i = 0; i < 2; i++) {
        await newFirer().fire({
          'medicationId': 'med-1',
          'reminderEventId': first.id,
          'step': 2,
        });
      }

      expect(await db.select(db.escalationRequests).get(), hasLength(1));
    });
  });

  group('cancellation', () {
    test('cancelling a ladder removes exactly its pending steps', () async {
      await newFirer().fire({
        'medicationId': 'med-1',
        'dayOfWeek': DateTime.monday,
        'step': 0,
      });
      final first = await soleEvent();

      final step1Id = ReminderLadder.ladderAlarmId(first.id, 1);
      final step2Id = ReminderLadder.ladderAlarmId(first.id, 2);
      final weeklyId = ReminderLadder.doseAlarmId('med-1', DateTime.monday);

      expect(alarms.pendingIds, containsAll([step1Id, step2Id, weeklyId]));

      await scheduler.cancelLadder(first.id);

      expect(alarms.pendingIds, isNot(contains(step1Id)));
      expect(alarms.pendingIds, isNot(contains(step2Id)));
      // Tomorrow's dose survives.
      expect(alarms.pendingIds, contains(weeklyId));
    });

    test('cancelling one dose does not touch another dose of the same drug',
        () async {
      await scheduler.cancelLadder('event-A');
      final cancelledForA = [...alarms.cancelled];

      expect(
        cancelledForA,
        isNot(contains(ReminderLadder.ladderAlarmId('event-B', 2))),
      );
    });
  });

  group('rescheduleAll', () {
    test('cancels every dose alarm before scheduling any', () async {
      await scheduler.rescheduleAll();

      final firstSchedule =
          alarms.calls.indexWhere((c) => c.startsWith('schedule:'));
      final lastCancel =
          alarms.calls.lastIndexWhere((c) => c.startsWith('cancel:'));
      expect(lastCancel, lessThan(firstSchedule),
          reason: 'a moved dose time must not leave its old alarm behind');
    });

    test('schedules one alarm per active medication per day', () async {
      await scheduler.rescheduleAll();

      // med-1 is active on 7 days; med-off is not scheduled at all.
      expect(scheduler.lastScheduledAlarmCount, 7);
      expect(alarms.scheduled, hasLength(7));
      expect(
        alarms.scheduled.every((a) => a.medicationId == 'med-1'),
        isTrue,
      );
      expect(alarms.scheduled.every((a) => a.step == 0), isTrue);
      expect(
        alarms.scheduled.map((a) => a.time.weekday).toSet(),
        {1, 2, 3, 4, 5, 6, 7},
      );
    });

    test('a deactivated medication still gets its alarms cancelled', () async {
      await scheduler.rescheduleAll();

      // Cancelled even though it is never rescheduled - otherwise a
      // discontinued medicine keeps reminding forever.
      for (var day = 1; day <= 7; day++) {
        expect(
          alarms.cancelled,
          contains(ReminderLadder.doseAlarmId('med-off', day)),
        );
      }
      expect(
        alarms.scheduled.any((a) => a.medicationId == 'med-off'),
        isFalse,
      );
    });

    test('every scheduled alarm is in the future', () async {
      await scheduler.rescheduleAll();
      for (final alarm in alarms.scheduled) {
        expect(alarm.time.isAfter(clock), isTrue);
      }
    });

    test('purges previously tracked alarm IDs from AppConfigs and persists new ones (G7)', () async {
      final schedulerWithConfigs = AlarmScheduler(
        contentRepo: ContentRepo(db),
        configsDao: db.appConfigsDao,
        alarmApi: alarms,
        now: () => clock,
      );

      // Pre-seed an orphaned alarm ID in AppConfigs that is no longer in medications
      await db.appConfigsDao.setValue(
        AlarmScheduler.trackedAlarmIdsKey,
        '99991,99992',
      );

      await schedulerWithConfigs.rescheduleAll();

      // Orphaned IDs must be cancelled
      expect(alarms.cancelled, contains(99991));
      expect(alarms.cancelled, contains(99992));

      // New alarm IDs must be stored in AppConfigs
      final storedIds =
          await db.appConfigsDao.getValue(AlarmScheduler.trackedAlarmIdsKey);
      expect(storedIds, isNotNull);
      final idList = storedIds!.split(',').map(int.parse).toList();
      expect(idList, hasLength(7));
      for (final id in idList) {
        expect(alarms.scheduled.any((a) => a.id == id), isTrue);
      }
    });

    test('scheduleTestDoseAlarm schedules exact alarm for specified medication in the future', () async {
      final fireAt = clock.add(const Duration(seconds: 20));
      await scheduler.scheduleTestDoseAlarm(
        medicationId: 'med-1',
        fireAt: fireAt,
      );

      final testAlarm = alarms.scheduled.firstWhere(
        (a) => a.medicationId == 'med-1' && a.step == 0 && a.time == fireAt,
      );
      expect(testAlarm.params['test'], isTrue);
    });
  });
}
