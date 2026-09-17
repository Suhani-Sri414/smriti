import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smriti/core/app_services.dart';
import 'package:smriti/core/db/database.dart';
import 'package:smriti/core/reminders/alarm_scheduler.dart';
import 'package:smriti/core/repo/content_repo.dart';
import 'package:smriti/core/sync/content_puller.dart';
import 'package:smriti/core/sync/media_downloader.dart';
import 'package:smriti/core/voice/voice_player.dart';
import 'package:smriti/screens/debug_sheet.dart';
import 'package:smriti/screens/home_screen.dart';
import 'package:smriti/screens/login_screen.dart';
import 'package:smriti/core/auth/pairing_service.dart';
import 'package:smriti/core/repo/ability_repo.dart';
import 'package:smriti/screens/pairing/code_entry_screen.dart';
import 'package:smriti/screens/reminder_screen.dart';
import 'package:smriti/screens/startup_gate.dart';
import 'package:smriti/core/voice/screen_reader_service.dart';

import '../core/auth/pairing_service_test.dart'
    show FakePairingGateway, successBody;
import '../core/voice/screen_reader_service_test.dart' show FakeTtsAdapter;
import '../core/repo/_test_db.dart';
import '../core/reminders/_fake_alarm_api.dart';

/// Counts calls so the wiring can be asserted without an alarm manager.
class SpyAlarmScheduler extends AlarmScheduler {
  SpyAlarmScheduler({required super.contentRepo, required super.alarmApi});

  int rescheduleCalls = 0;

  @override
  Future<void> rescheduleAll() async {
    rescheduleCalls++;
    await super.rescheduleAll();
  }
}

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

  setUp(() => db = newTestDb());
  tearDown(() async => db.close());

  Future<void> seedContent() async {
    await ContentRepo(db).replaceContent(
      people: [
        PeopleCompanion.insert(
          id: 'per-1',
          name: 'Bina',
          relationship: 'daughter',
          photoPath: 'people/photos/per-1.jpg',
          sortOrder: 0,
        ),
      ],
      medications: [
        MedicationsCompanion.insert(
          id: 'med-1',
          name: 'Metformin',
          dose: '500mg',
          windowStartMin: 480,
          windowEndMin: 540,
          chosenTimeMin: 500,
          daysOfWeek: '1,2,3,4,5,6,7',
        ),
      ],
      routineItems: [
        RoutineItemsCompanion.insert(
          id: 'rt-1',
          timeMin: 480,
          labelKey: 'breakfast',
          iconAsset: 'icon_breakfast',
        ),
      ],
      contentVersion: '7',
    );
  }

  group('startup gate', () {
    testWidgets('an unpaired tablet lands on login', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: StartupGate(services: AppServices(database: db))),
      );
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
    });

    testWidgets('a paired tablet lands on home', (tester) async {
      await db.appConfigsDao.setValue('patientId', 'pat-1');
      await db.appConfigsDao.setValue('elderName', 'Test Patient');
      await seedContent();

      await tester.pumpWidget(
        MaterialApp(home: StartupGate(services: AppServices(database: db))),
      );
      await tester.pumpAndSettle();

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);
    });

    testWidgets('pairing via code entry transitions directly to home screen',
        (tester) async {
      final gateway = FakePairingGateway(
        response: PairingResponse(status: 200, data: successBody()),
      );
      final pairingService = PairingService(
        configs: db.appConfigsDao,
        abilityRepo: AbilityRepo(db),
        gateway: gateway,
      );
      final services = AppServices(
        database: db,
        pairingService: pairingService,
      );

      await tester.pumpWidget(
        MaterialApp(home: StartupGate(services: services)),
      );
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);

      // Open CodeEntryScreen
      await tester.tap(find.byKey(const Key('enter_code_button')));
      await tester.pumpAndSettle();
      expect(find.byType(CodeEntryScreen), findsOneWidget);

      // Enter valid code from the 27-char alphabet (no B, I, O, 0, 1, 8)
      const validCode = 'ACDEFGHJ';
      for (var i = 0; i < validCode.length; i++) {
        await tester.enterText(find.byKey(Key('code_box_$i')), validCode[i]);
        await tester.pump();
      }
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('pairing_submit')));
      await tester.pumpAndSettle();

      // Tablet should now be directly on HomeScreen without needing app restart!
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);
      expect(find.byType(CodeEntryScreen), findsNothing);
    });
  });

  group('home screen', () {
    Future<void> pumpHome(WidgetTester tester) async {
      await db.appConfigsDao.setValue('patientId', 'pat-1');
      await db.appConfigsDao.setValue('elderName', 'Test Patient');
      await tester.pumpWidget(
        MaterialApp(home: HomeScreen(services: AppServices(database: db))),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows pulled medications and routine items', (tester) async {
      await seedContent();
      await pumpHome(tester);

      // The elder's own name, from AppConfigs.
      expect(find.text('Test Patient'), findsOneWidget);
      expect(find.byKey(const Key('home_content_version')), findsOneWidget);
      expect(find.textContaining('content v7'), findsOneWidget);

      // Real pulled content, not placeholders.
      expect(find.byKey(const Key('medication_med-1')), findsOneWidget);
      expect(find.text('Metformin · 500mg'), findsOneWidget);
      expect(find.text('08:20'), findsOneWidget, reason: 'chosenTimeMin 500');
      expect(find.byKey(const Key('routine_rt-1')), findsOneWidget);
      expect(find.text('breakfast'), findsOneWidget);
      expect(find.text('08:00'), findsOneWidget, reason: 'routine timeMin 480');

      expect(find.byKey(const Key('play_market_basket')), findsOneWidget);
    });

    testWidgets('an unpulled tablet says so rather than showing nothing',
        (tester) async {
      await pumpHome(tester);

      expect(find.byKey(const Key('medications_empty')), findsOneWidget);
      expect(find.byKey(const Key('routine_empty')), findsOneWidget);
    });

    testWidgets('long-pressing the title opens the debug panel',
        (tester) async {
      await seedContent();
      await pumpHome(tester);

      await tester.longPress(find.byKey(const Key('home_title')));
      await tester.pumpAndSettle();

      expect(find.byType(DebugSheet), findsOneWidget);
      expect(find.byKey(const Key('debug_fire_test_reminder')), findsOneWidget);
      expect(find.byKey(const Key('debug_health_check')), findsOneWidget);
      expect(find.byKey(const Key('debug_test_alarm')), findsOneWidget);
    });

    testWidgets('the debug trigger fires a reminder for the first medication',
        (tester) async {
      await seedContent();
      await pumpHome(tester);

      await tester.longPress(find.byKey(const Key('home_title')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('debug_fire_test_reminder')));
      await tester.pumpAndSettle();

      expect(find.byType(ReminderScreen), findsOneWidget);
      expect(find.byKey(const Key('reminder_medication_name')), findsOneWidget);
      expect(find.text('Metformin'), findsOneWidget);
    });

    testWidgets('the debug trigger says so when nothing has been pulled',
        (tester) async {
      await pumpHome(tester);

      await tester.longPress(find.byKey(const Key('home_title')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('debug_fire_test_reminder')));
      await tester.pumpAndSettle();

      expect(find.byType(ReminderScreen), findsNothing);
      expect(
        find.text('No active medications — pull content first.'),
        findsOneWidget,
      );
    });

    testWidgets('screen reader button reads aloud home instructions and toggles',
        (tester) async {
      final fakeTts = FakeTtsAdapter();
      final screenReader = ScreenReaderService(ttsAdapter: fakeTts);
      final services = AppServices(
        database: db,
        screenReaderService: screenReader,
      );

      await db.appConfigsDao.setValue('patientId', 'pat-1');
      await db.appConfigsDao.setValue('elderName', 'Test Patient');
      await tester.pumpWidget(
        MaterialApp(home: HomeScreen(services: services)),
      );
      await tester.pumpAndSettle();

      final buttonFinder = find.byKey(const Key('home_screen_reader_button'));
      expect(buttonFinder, findsOneWidget);

      await tester.tap(buttonFinder);
      await tester.pump();

      expect(screenReader.isSpeaking, isTrue);
      expect(fakeTts.speakCalls, [
        'Welcome to Smriti. You can tap the Sathi button below to talk to your companion, or view your daily reminders.'
      ]);

      await tester.tap(buttonFinder);
      await tester.pump();

      expect(screenReader.isSpeaking, isFalse);
      expect(fakeTts.stopCalls, 1);
    });
  });

  group('reminder screen', () {
    Future<AppServices> pumpReminder(
      WidgetTester tester, {
      required RecordingVoicePlayer voice,
    }) async {
      await seedContent();
      // Explicit fake: "taken" cancels ladder alarms, and that must not depend
      // on an unregistered method channel happening to return null.
      final services = AppServices(
        database: db,
        alarmScheduler: AlarmScheduler(
          contentRepo: ContentRepo(db),
          alarmApi: FakeAlarmApi(),
        ),
      );
      final medication = (await services.contentRepo.getMedications()).single;

      await tester.pumpWidget(
        MaterialApp(
          home: ReminderScreen(
            services: services,
            medication: medication,
            voicePlayer: voice,
            now: () => DateTime.fromMillisecondsSinceEpoch(1757200000000),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return services;
    }

    testWidgets('"taken" writes the outcome and pops', (tester) async {
      final voice = RecordingVoicePlayer();
      final services = await pumpReminder(tester, voice: voice);

      await tester.tap(find.byKey(const Key('reminder_taken')));
      await tester.pumpAndSettle();

      final events = await db.select(db.reminderEvents).get();
      expect(events, hasLength(1));
      expect(events.single.medicationId, 'med-1');
      expect(events.single.outcome, 'taken');
      expect(events.single.respondedAt, 1757200000000);
      expect(events.single.ladderStep, 0);
      expect(events.single.channel, 'in_app');

      // Queued for the next sync.
      expect(await services.eventRepo.unsyncedReminderEvents(), hasLength(1));
      expect(voice.stops, greaterThan(0));
    });

    testWidgets('"not now" records a snooze, not a silent dismissal',
        (tester) async {
      await pumpReminder(tester, voice: RecordingVoicePlayer());

      await tester.tap(find.byKey(const Key('reminder_not_now')));
      await tester.pumpAndSettle();

      final events = await db.select(db.reminderEvents).get();
      expect(events.single.outcome, 'snoozed');
      expect(events.single.respondedAt, isNotNull);
    });

    testWidgets('a medication with no caregiver voice plays nothing',
        (tester) async {
      final voice = RecordingVoicePlayer();
      await pumpReminder(tester, voice: voice);

      // seedContent has no voicePath, so nothing is attempted.
      expect(voice.played, isEmpty);
    });
  });

  group('alarm reschedule wiring', () {
    test('a content pull calls rescheduleAll, after the swap', () async {
      await db.appConfigsDao.setValue('patientId', 'pat-1');

      final scheduler = SpyAlarmScheduler(contentRepo: ContentRepo(db), alarmApi: FakeAlarmApi());
      final services = AppServices(database: db, alarmScheduler: scheduler);

      // Drive the real puller the services built, so the wiring under test is
      // the production one.
      final puller = ContentPuller(
        configs: db.appConfigsDao,
        contentRepo: services.contentRepo,
        mediaDownloader: MediaDownloader(
          fetcher: _NoMediaFetcher(),
          storage: _NoMediaStorage(),
        ),
        gateway: _StubContentGateway(),
        onContentChanged: services.contentPuller.onContentChanged,
      );

      final result = await puller.pull();
      expect(result.didUpdate, isTrue);

      expect(scheduler.rescheduleCalls, 1);
      // It ran after the swap, so it saw the new medication.
      expect(scheduler.lastScheduledAlarmCount, 7,
          reason: 'one medication, seven days');
    });

    test('the stub counts one alarm per medication per active day', () async {
      await seedContent();
      final scheduler = AlarmScheduler(contentRepo: ContentRepo(db), alarmApi: FakeAlarmApi());

      await scheduler.rescheduleAll();

      expect(scheduler.lastScheduledAlarmCount, 7);
    });
  });
}

class _NoMediaFetcher implements MediaFetcher {
  @override
  Future<List<int>> download(String bucket, String objectPath) async =>
      const [1];
}

class _NoMediaStorage implements MediaStorage {
  @override
  Future<String> tempDirectory() async => Directory.systemTemp.path;

  @override
  Future<String> directoryFor(MediaKind kind) async =>
      Directory.systemTemp.path;
}

class _StubContentGateway implements ContentGateway {
  @override
  Future<String?> fetchRemoteContentVersion(String patientId) async => '7';

  @override
  Future<Map<String, dynamic>> fetchContent(String patientId) async => {
        'version': 7,
        'people': const [],
        'medications': [
          {
            'id': 'med-1',
            'name': 'Metformin',
            'dose': '500mg',
            'active': true,
            'days_of_week': '1,2,3,4,5,6,7',
            'window_start_min': 480,
            'window_end_min': 540,
            'chosen_time_min': 500,
          },
        ],
        'routine': const [],
      };
}
