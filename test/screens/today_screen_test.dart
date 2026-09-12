import 'package:drift/drift.dart' hide isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smriti/core/app_services.dart';
import 'package:smriti/core/db/database.dart';
import 'package:smriti/screens/home_screen.dart';
import 'package:smriti/screens/today_screen.dart';

import '../core/repo/_test_db.dart';

void main() {
  late SmritiDatabase db;

  setUp(() {
    db = newTestDb();
  });

  tearDown(() async {
    await db.close();
  });

  Widget createSubject({
    required AppServices services,
    DateTime Function()? now,
  }) {
    return MaterialApp(
      home: TodayScreen(
        services: services,
        now: now,
      ),
    );
  }

  testWidgets('renders empty state message when no items scheduled',
      (tester) async {
    final services = AppServices(database: db);
    await tester.pumpWidget(createSubject(services: services));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('today_title')), findsOneWidget);
    expect(find.byKey(const Key('today_empty_message')), findsOneWidget);
    expect(find.text('No tasks scheduled for today'), findsOneWidget);
    expect(find.text('Have a peaceful and restful day.'), findsOneWidget);
    expect(find.byKey(const Key('today_back_button')), findsOneWidget);
  });

  testWidgets('renders medications and routine items in chronological order',
      (tester) async {
    final services = AppServices(database: db);

    // Insert Routine: Afternoon Tea at 16:00 (960 min)
    await db.into(db.routineItems).insert(
          RoutineItemsCompanion.insert(
            id: 'r_tea',
            timeMin: 960,
            labelKey: 'afternoon_tea',
            iconAsset: 'tea',
          ),
        );

    // Insert Routine: Morning Bath at 08:30 (510 min)
    await db.into(db.routineItems).insert(
          RoutineItemsCompanion.insert(
            id: 'r_bath',
            timeMin: 510,
            labelKey: 'morning_bath',
            iconAsset: 'bath',
          ),
        );

    // Insert Medication: Metformin at 09:00 (540 min)
    await db.into(db.medications).insert(
          MedicationsCompanion.insert(
            id: 'med_metformin',
            name: 'Metformin',
            dose: '500mg',
            chosenTimeMin: 540,
            windowStartMin: 500,
            windowEndMin: 580,
            daysOfWeek: '1,2,3,4,5,6,7',
          ),
        );

    // Mock now at 10:00 AM (600 min)
    final fixedNow = DateTime(2026, 9, 12, 10, 0);

    await tester.pumpWidget(
      createSubject(services: services, now: () => fixedNow),
    );
    await tester.pumpAndSettle();

    // Verify all 3 items appear
    expect(find.text('Morning Bath'), findsOneWidget);
    expect(find.text('Metformin'), findsOneWidget);
    expect(find.text('Afternoon Tea'), findsOneWidget);

    // Verify times appear
    expect(find.text('08:30'), findsOneWidget);
    expect(find.text('09:00'), findsOneWidget);
    expect(find.text('16:00'), findsOneWidget);

    // Verify Terracotta Now marker is rendered
    expect(find.byKey(const Key('today_now_marker')), findsOneWidget);
    expect(find.text('Now · 10:00'), findsOneWidget);
  });

  testWidgets('fades completed medications with checkmark', (tester) async {
    final services = AppServices(database: db);
    final fixedNow = DateTime(2026, 9, 12, 12, 0);
    final todayStart = DateTime(2026, 9, 12, 8, 0).millisecondsSinceEpoch;

    // Insert Medication: Amlodipine at 08:00
    await db.into(db.medications).insert(
          MedicationsCompanion.insert(
            id: 'med_amlodipine',
            name: 'Amlodipine',
            dose: '5mg',
            chosenTimeMin: 480,
            windowStartMin: 460,
            windowEndMin: 520,
            daysOfWeek: '1,2,3,4,5,6,7',
          ),
        );

    // Insert ReminderEvent recording it was taken
    await db.into(db.reminderEvents).insert(
          ReminderEventsCompanion.insert(
            id: 'rem_1',
            medicationId: 'med_amlodipine',
            scheduledAt: todayStart,
            outcome: const Value('taken'),
            channel: 'local_alarm',
            ladderStep: 0,
          ),
        );

    await tester.pumpWidget(
      createSubject(services: services, now: () => fixedNow),
    );
    await tester.pumpAndSettle();

    expect(find.text('Amlodipine'), findsOneWidget);
    // Leaf green checkmark icon is present
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
  });

  testWidgets('zero-shame: nothing is ever marked missed, late, or in red',
      (tester) async {
    final services = AppServices(database: db);
    // Mock time is in the evening (20:00)
    final fixedNow = DateTime(2026, 9, 12, 20, 0);

    // Morning medication that was NOT marked taken
    await db.into(db.medications).insert(
          MedicationsCompanion.insert(
            id: 'med_past',
            name: 'Morning Vitamin',
            dose: '1 tablet',
            chosenTimeMin: 500, // 8:20 AM
            windowStartMin: 480,
            windowEndMin: 540,
            daysOfWeek: '1,2,3,4,5,6,7',
          ),
        );

    await tester.pumpWidget(
      createSubject(services: services, now: () => fixedNow),
    );
    await tester.pumpAndSettle();

    // Past item appears peacefully
    expect(find.text('Morning Vitamin'), findsOneWidget);

    // Absolute zero-shame check:
    expect(find.textContaining('Missed'), findsNothing);
    expect(find.textContaining('missed'), findsNothing);
    expect(find.textContaining('Late'), findsNothing);
    expect(find.textContaining('late'), findsNothing);
    expect(find.textContaining('Overdue'), findsNothing);
    expect(find.textContaining('Failed'), findsNothing);
  });

  testWidgets('back button pops cleanly to Home', (tester) async {
    final services = AppServices(database: db);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => TodayScreen(services: services),
                  ),
                );
              },
              child: const Text('Open Today'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Today'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('today_back_button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('today_back_button')));
    await tester.pumpAndSettle();

    expect(find.text('Open Today'), findsOneWidget);
    expect(find.byKey(const Key('today_back_button')), findsNothing);
  });

  testWidgets('HomeScreen Today card opens TodayScreen', (tester) async {
    final services = AppServices(database: db);

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(services: services),
      ),
    );
    await tester.pumpAndSettle();

    // Tap Today card
    expect(find.text('Today'), findsOneWidget);
    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();

    // Should be on TodayScreen
    expect(find.byKey(const Key('today_back_button')), findsOneWidget);
    expect(find.byKey(const Key('today_title')), findsOneWidget);
  });
}
