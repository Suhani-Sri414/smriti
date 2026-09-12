import 'dart:io';

import 'package:drift/drift.dart' hide Column, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smriti/core/app_services.dart';
import 'package:smriti/core/db/database.dart';
import 'package:smriti/core/files/file_paths.dart';
import 'package:smriti/core/reminders/alarm_scheduler.dart';
import 'package:smriti/core/reminders/notifications.dart';
import 'package:smriti/core/repo/content_repo.dart';
import 'package:smriti/core/voice/voice_player.dart';
import 'package:smriti/screens/reminder_screen.dart';

import '../core/repo/_test_db.dart';
import '../core/reminders/_fake_alarm_api.dart';

class RecordingVoicePlayer implements VoicePlayer {
  final List<String> played = [];
  int stops = 0;

  @override
  Future<void> play(String path) async => played.add(path);

  @override
  Future<void> stop() async => stops++;

  @override
  Future<void> dispose() async {}
}

void main() {
  late SmritiDatabase db;
  late Directory tempDir;

  const testMedication = Medication(
    id: 'med_metformin',
    name: 'Metformin',
    dose: '500mg',
    windowStartMin: 480,
    windowEndMin: 540,
    chosenTimeMin: 500,
    daysOfWeek: '1,2,3,4,5,6,7',
    active: true,
  );

  setUp(() async {
    db = newTestDb();
    tempDir = await Directory.systemTemp.createTemp('smriti_reminder_test_');
    FilePaths.documentsDirectoryOverride = tempDir.path;

    await db.into(db.medications).insert(
      MedicationsCompanion.insert(
        id: testMedication.id,
        name: testMedication.name,
        dose: testMedication.dose,
        windowStartMin: testMedication.windowStartMin,
        windowEndMin: testMedication.windowEndMin,
        chosenTimeMin: testMedication.chosenTimeMin,
        daysOfWeek: testMedication.daysOfWeek,
        active: Value(testMedication.active),
      ),
    );
  });

  tearDown(() async {
    FilePaths.documentsDirectoryOverride = null;
    await db.close();
    try {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  AppServices createServices() {
    return AppServices(
      database: db,
      alarmScheduler: AlarmScheduler(
        contentRepo: ContentRepo(db),
        alarmApi: FakeAlarmApi(),
      ),
      notifier: NoopReminderNotifier(),
    );
  }

  Widget createSubject({
    required AppServices services,
    Medication medication = testMedication,
    VoicePlayer? voicePlayer,
    DateTime Function()? now,
  }) {
    return MaterialApp(
      home: ReminderScreen(
        services: services,
        medication: medication,
        voicePlayer: voicePlayer,
        now: now,
      ),
    );
  }

  testWidgets('renders blush background, medication info, and vector pill',
      (tester) async {
    final services = createServices();

    await tester.pumpWidget(createSubject(services: services));
    await tester.pumpAndSettle();

    // Verify medication details
    expect(find.byKey(const Key('reminder_medication_name')), findsOneWidget);
    expect(find.text('Metformin'), findsOneWidget);

    expect(find.byKey(const Key('reminder_medication_dose')), findsOneWidget);
    expect(find.text('500mg'), findsOneWidget);

    // Verify time window tag
    expect(find.text('Time: 08:00 – 09:00'), findsOneWidget);
    expect(find.text('Medicine time'), findsOneWidget);

    // Both action targets present
    expect(find.byKey(const Key('reminder_taken')), findsOneWidget);
    expect(find.byKey(const Key('reminder_not_now')), findsOneWidget);
    expect(find.text('Taken'), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);

    // Custom vector pill is drawn when photo is absent
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('plays caregiver voice on mount and supports replay',
      (tester) async {
    final voice = RecordingVoicePlayer();
    final services = createServices();

    const medWithVoice = Medication(
      id: 'med_with_voice',
      name: 'Amlodipine',
      dose: '5mg',
      windowStartMin: 480,
      windowEndMin: 540,
      chosenTimeMin: 500,
      daysOfWeek: '1,2,3,4,5,6,7',
      active: true,
      voicePath: 'medications/voice/med_with_voice.m4a',
    );

    await db.into(db.medications).insert(
      MedicationsCompanion.insert(
        id: medWithVoice.id,
        name: medWithVoice.name,
        dose: medWithVoice.dose,
        windowStartMin: medWithVoice.windowStartMin,
        windowEndMin: medWithVoice.windowEndMin,
        chosenTimeMin: medWithVoice.chosenTimeMin,
        daysOfWeek: medWithVoice.daysOfWeek,
        active: Value(medWithVoice.active),
        voicePath: Value(medWithVoice.voicePath),
      ),
    );

    await tester.pumpWidget(
      createSubject(
        services: services,
        medication: medWithVoice,
        voicePlayer: voice,
      ),
    );
    await tester.pumpAndSettle();

    // Verify voice was played on mount
    expect(voice.played, hasLength(1));
    expect(voice.played.single, contains('med_with_voice.m4a'));

    // Replay button is visible
    expect(find.byKey(const Key('reminder_replay_voice')), findsOneWidget);
    expect(find.text('Hear message again'), findsOneWidget);

    // Tap replay
    await tester.tap(find.byKey(const Key('reminder_replay_voice')));
    await tester.pumpAndSettle();

    // Voice was stopped and replayed
    expect(voice.stops, greaterThanOrEqualTo(1));
    expect(voice.played, hasLength(2));
  });

  testWidgets('tapping Taken records outcome and pops', (tester) async {
    final voice = RecordingVoicePlayer();
    final services = createServices();

    String? poppedOutcome;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              poppedOutcome = await Navigator.of(context).push<String>(
                MaterialPageRoute(
                  builder: (_) => ReminderScreen(
                    services: services,
                    medication: testMedication,
                    voicePlayer: voice,
                    now: () => DateTime.fromMillisecondsSinceEpoch(1757200000000),
                  ),
                ),
              );
            },
            child: const Text('Open Reminder'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Reminder'));
    await tester.pumpAndSettle();

    // Tap Taken
    await tester.tap(find.byKey(const Key('reminder_taken')));
    await tester.pumpAndSettle();

    expect(poppedOutcome, 'taken');

    final events = await db.select(db.reminderEvents).get();
    expect(events, hasLength(1));
    expect(events.single.medicationId, testMedication.id);
    expect(events.single.outcome, 'taken');
    expect(events.single.respondedAt, 1757200000000);
    expect(voice.stops, greaterThan(0));
  });

  testWidgets('tapping Not now records snooze outcome without penalty',
      (tester) async {
    final services = createServices();

    String? poppedOutcome;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              poppedOutcome = await Navigator.of(context).push<String>(
                MaterialPageRoute(
                  builder: (_) => ReminderScreen(
                    services: services,
                    medication: testMedication,
                  ),
                ),
              );
            },
            child: const Text('Open Reminder'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Reminder'));
    await tester.pumpAndSettle();

    // Tap Not now
    await tester.tap(find.byKey(const Key('reminder_not_now')));
    await tester.pumpAndSettle();

    expect(poppedOutcome, 'snoozed');

    final events = await db.select(db.reminderEvents).get();
    expect(events, hasLength(1));
    expect(events.single.outcome, 'snoozed');
    expect(events.single.respondedAt, isNotNull);
  });

  testWidgets('zero-shame: no red warnings, no panic countdowns',
      (tester) async {
    final services = createServices();

    await tester.pumpWidget(createSubject(services: services));
    await tester.pumpAndSettle();

    expect(find.textContaining('Warning'), findsNothing);
    expect(find.textContaining('Urgent'), findsNothing);
    expect(find.textContaining('Penalty'), findsNothing);
    expect(find.textContaining('Failed'), findsNothing);
  });
}
