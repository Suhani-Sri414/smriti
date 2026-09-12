import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smriti/core/app_services.dart';
import 'package:smriti/core/db/database.dart';
import 'package:smriti/core/reminders/alarm_scheduler.dart';
import 'package:smriti/core/reminders/health_check.dart';
import 'package:smriti/core/repo/content_repo.dart';
import 'package:smriti/screens/diagnostics/caregiver_pin_dialog.dart';
import 'package:smriti/screens/diagnostics/diagnostics_screen.dart';
import 'package:smriti/screens/home_screen.dart';
import 'package:smriti/screens/reminder_screen.dart';

import '../core/reminders/_fake_alarm_api.dart';
import '../core/repo/_test_db.dart';

class _FakePermissionGateway implements PermissionGateway {
  @override
  Future<CheckOutcome> requestBatteryExemption() async => CheckOutcome.granted;

  @override
  Future<CheckOutcome> requestExactAlarm() async => CheckOutcome.granted;

  @override
  Future<CheckOutcome> requestMicrophone() async => CheckOutcome.granted;

  @override
  Future<CheckOutcome> requestNotifications() async => CheckOutcome.granted;
}

class _FakeOem implements OemGateway {
  @override
  Future<String> manufacturer() async => 'samsung';

  @override
  Future<bool> openAutostartSettings(String manufacturer) async => true;
}

void main() {
  late SmritiDatabase db;
  late AppServices services;
  late FakeAlarmApi alarmApi;
  late AlarmScheduler scheduler;

  setUp(() {
    db = newTestDb();
    alarmApi = FakeAlarmApi();
    scheduler = AlarmScheduler(
      contentRepo: ContentRepo(db),
      alarmApi: alarmApi,
    );
    services = AppServices(
      database: db,
      alarmScheduler: scheduler,
    );
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> seedData() async {
    await db.appConfigsDao.setValue('patientId', 'pat-999');
    await db.appConfigsDao.setValue('deviceId', 'dev-abc-123');
    await db.appConfigsDao.setValue('elderName', 'Memcha Devi');
    await db.appConfigsDao.setValue('primaryContactName', 'Chaoba');
    await db.appConfigsDao.setValue('primaryContactPhone', '+919876543210');
    await db.appConfigsDao.setValue('contentVersion', '12');
    await db.appConfigsDao.setValue('lastSyncAt', '1757200000000');
    await db.appConfigsDao.setValue('clockSkewMs', '250');
    await db.appConfigsDao.setValue('lastSyncError', '');

    await ContentRepo(db).replaceContent(
      people: [],
      medications: [
        MedicationsCompanion.insert(
          id: 'med-1',
          name: 'Donepezil',
          dose: '5mg',
          windowStartMin: 480,
          windowEndMin: 540,
          chosenTimeMin: 500,
          daysOfWeek: '1,2,3,4,5,6,7',
        ),
      ],
      routineItems: [],
      contentVersion: '12',
    );
  }

  group('CaregiverPinDialog', () {
    testWidgets('default PIN 1234 succeeds and closes dialog returning true',
        (tester) async {
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await CaregiverPinDialog.show(context, services);
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.byType(CaregiverPinDialog), findsOneWidget);

      // Enter digits 1, 2, 3, 4
      await tester.tap(find.byKey(const Key('pin_digit_1')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('pin_digit_2')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('pin_digit_3')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('pin_digit_4')));
      await tester.pumpAndSettle();

      expect(find.byType(CaregiverPinDialog), findsNothing);
      expect(result, isTrue);
    });

    testWidgets('wrong PIN shows error message and clears entry',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => CaregiverPinDialog.show(context, services),
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Enter wrong PIN: 9, 9, 9, 9
      await tester.tap(find.byKey(const Key('pin_digit_9')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('pin_digit_9')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('pin_digit_9')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('pin_digit_9')));
      await tester.pumpAndSettle();

      expect(find.byType(CaregiverPinDialog), findsOneWidget);
      expect(find.byKey(const Key('pin_error_text')), findsOneWidget);
      expect(find.text('Incorrect PIN. Please try again.'), findsOneWidget);
    });

    testWidgets('reads custom configured PIN from AppConfigs', (tester) async {
      await db.appConfigsDao.setValue('caregiverPin', '8888');

      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await CaregiverPinDialog.show(context, services);
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Old PIN '1234' should now fail
      await tester.tap(find.byKey(const Key('pin_digit_1')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('pin_digit_2')));
      await tester.tap(find.byKey(const Key('pin_digit_3')));
      await tester.tap(find.byKey(const Key('pin_digit_4')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('pin_error_text')), findsOneWidget);

      // Now enter '8888'
      await tester.tap(find.byKey(const Key('pin_digit_8')));
      await tester.tap(find.byKey(const Key('pin_digit_8')));
      await tester.tap(find.byKey(const Key('pin_digit_8')));
      await tester.tap(find.byKey(const Key('pin_digit_8')));
      await tester.pumpAndSettle();

      expect(find.byType(CaregiverPinDialog), findsNothing);
      expect(result, isTrue);
    });
  });

  void configureLandscapeTablet(WidgetTester tester) {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
  }

  group('DiagnosticsScreen', () {
    testWidgets('renders identity and sync metrics correctly', (tester) async {
      configureLandscapeTablet(tester);
      await seedData();

      await tester.pumpWidget(
        MaterialApp(
          home: DiagnosticsScreen(services: services),
        ),
      );
      await tester.pumpAndSettle();

      // Check Scaffold & Identity
      expect(find.byKey(const Key('diagnostics_screen')), findsOneWidget);
      expect(find.byKey(const Key('diag_patient_id')), findsOneWidget);
      expect(find.text('pat-999'), findsOneWidget);
      expect(find.byKey(const Key('diag_device_id')), findsOneWidget);
      expect(find.text('dev-abc-123'), findsOneWidget);

      // Check Sync metrics
      expect(find.byKey(const Key('diag_content_version')), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      expect(find.byKey(const Key('diag_clock_skew')), findsOneWidget);
      expect(find.text('250 ms'), findsOneWidget);
      expect(find.byKey(const Key('diag_pending_count')), findsOneWidget);
      expect(find.text('0 records (0 events, 0 memos)'), findsOneWidget);
      expect(find.byKey(const Key('diagnostics_sync_now_button')), findsOneWidget);

      // Check Reminders & Actions
      expect(find.byKey(const Key('diag_meds_count')), findsOneWidget);
      expect(find.text('1 active'), findsOneWidget);
      expect(find.byKey(const Key('diagnostics_fire_test_reminder_button')),
          findsOneWidget);
      expect(find.byKey(const Key('diagnostics_reschedule_alarms_button')),
          findsOneWidget);
      expect(find.byKey(const Key('diagnostics_change_pin_button')),
          findsOneWidget);
    });

    testWidgets('Sync Now button triggers manual sync and updates banner',
        (tester) async {
      configureLandscapeTablet(tester);
      await seedData();

      await tester.pumpWidget(
        MaterialApp(
          home: DiagnosticsScreen(services: services),
        ),
      );
      await tester.pumpAndSettle();

      final syncBtn = find.byKey(const Key('diagnostics_sync_now_button'));
      expect(syncBtn, findsOneWidget);

      await tester.tap(syncBtn);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('diagnostics_status_banner')), findsOneWidget);
    });

    testWidgets('Fire test reminder button opens ReminderScreen',
        (tester) async {
      configureLandscapeTablet(tester);
      await seedData();

      await tester.pumpWidget(
        MaterialApp(
          home: DiagnosticsScreen(services: services),
        ),
      );
      await tester.pumpAndSettle();

      final fireBtn =
          find.byKey(const Key('diagnostics_fire_test_reminder_button'));
      await tester.tap(fireBtn);
      await tester.pumpAndSettle();

      expect(find.byType(ReminderScreen), findsOneWidget);
      expect(find.text('Donepezil'), findsOneWidget);
    });

    testWidgets('Reschedule all alarms calls scheduler', (tester) async {
      configureLandscapeTablet(tester);
      await seedData();

      await tester.pumpWidget(
        MaterialApp(
          home: DiagnosticsScreen(services: services),
        ),
      );
      await tester.pumpAndSettle();

      final rescheduleBtn =
          find.byKey(const Key('diagnostics_reschedule_alarms_button'));
      await tester.tap(rescheduleBtn);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('diagnostics_status_banner')), findsOneWidget);
      expect(find.textContaining('Alarms rescheduled:'), findsOneWidget);
    });

    testWidgets('Re-run Health Check executes check and renders report',
        (tester) async {
      configureLandscapeTablet(tester);
      await seedData();

      final healthCheck = SetupHealthCheck(
        configs: db.appConfigsDao,
        scheduler: scheduler,
        permissions: _FakePermissionGateway(),
        oem: _FakeOem(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: DiagnosticsScreen(
            services: services,
            healthCheck: healthCheck,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final healthBtn =
          find.byKey(const Key('diagnostics_rerun_health_check_button'));
      await tester.ensureVisible(healthBtn);
      await tester.tap(healthBtn);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('diag_health_status')), findsOneWidget);
      expect(find.byKey(const Key('diagnostics_status_banner')), findsOneWidget);
    });

    testWidgets('Change PIN dialog updates caregiverPin in AppConfigs',
        (tester) async {
      configureLandscapeTablet(tester);
      await seedData();

      await tester.pumpWidget(
        MaterialApp(
          home: DiagnosticsScreen(services: services),
        ),
      );
      await tester.pumpAndSettle();

      final changePinBtn =
          find.byKey(const Key('diagnostics_change_pin_button'));
      await tester.ensureVisible(changePinBtn);
      await tester.tap(changePinBtn);
      await tester.pumpAndSettle();

      expect(find.text('Update Caregiver PIN'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('new_pin_input')), '7777');
      await tester.pump();

      await tester.tap(find.byKey(const Key('save_new_pin_button')));
      await tester.pumpAndSettle();

      expect(find.text('Caregiver PIN updated successfully.'), findsOneWidget);
      expect(await db.appConfigsDao.getValue('caregiverPin'), '7777');
    });
  });

  group('HomeScreen kiosk exit corner integration', () {
    testWidgets('long-pressing corner opens PIN dialog then DiagnosticsScreen',
        (tester) async {
      configureLandscapeTablet(tester);
      await seedData();

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(services: services),
        ),
      );
      await tester.pumpAndSettle();

      // Long-press the hidden kiosk exit corner
      await tester.longPress(find.byKey(const Key('kiosk_exit_corner')));
      await tester.pumpAndSettle();

      expect(find.byType(CaregiverPinDialog), findsOneWidget);

      // Enter default PIN '1234'
      await tester.tap(find.byKey(const Key('pin_digit_1')));
      await tester.tap(find.byKey(const Key('pin_digit_2')));
      await tester.tap(find.byKey(const Key('pin_digit_3')));
      await tester.tap(find.byKey(const Key('pin_digit_4')));
      await tester.pumpAndSettle();

      expect(find.byType(DiagnosticsScreen), findsOneWidget);
      expect(find.text('Device & System Diagnostics'), findsOneWidget);
    });

    testWidgets('opening diagnostics from debug sheet via PIN', (tester) async {
      configureLandscapeTablet(tester);
      await seedData();

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(services: services),
        ),
      );
      await tester.pumpAndSettle();

      // Long press title to open DebugSheet
      await tester.longPress(find.byKey(const Key('home_title')));
      await tester.pumpAndSettle();

      final openDiagBtn = find.byKey(const Key('debug_open_diagnostics'));
      expect(openDiagBtn, findsOneWidget);
      await tester.tap(openDiagBtn);
      await tester.pumpAndSettle();

      expect(find.byType(CaregiverPinDialog), findsOneWidget);

      // Enter default PIN '1234'
      await tester.tap(find.byKey(const Key('pin_digit_1')));
      await tester.tap(find.byKey(const Key('pin_digit_2')));
      await tester.tap(find.byKey(const Key('pin_digit_3')));
      await tester.tap(find.byKey(const Key('pin_digit_4')));
      await tester.pumpAndSettle();

      expect(find.byType(DiagnosticsScreen), findsOneWidget);
    });
  });
}
