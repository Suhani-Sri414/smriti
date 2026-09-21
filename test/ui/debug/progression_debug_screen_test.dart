import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smriti/core/app_services.dart';
import 'package:smriti/core/db/database.dart';
import 'package:smriti/screens/home_screen.dart';
import 'package:smriti/ui/debug/progression_debug_screen.dart';

import '../../core/repo/_test_db.dart';

void main() {
  late SmritiDatabase db;
  late AppServices services;

  setUp(() {
    db = newTestDb();
    services = AppServices(database: db);
  });

  tearDown(() async {
    await db.close();
  });

  Widget createSubject() {
    return MaterialApp(
      home: ProgressionDebugScreen(services: services),
    );
  }

  testWidgets('renders all sections and baseline catalog levels', (tester) async {
    tester.view.physicalSize = const Size(1280, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(createSubject());
    await tester.pumpAndSettle();

    expect(find.text('Progression & Fatigue Engine Debugger'), findsOneWidget);
    expect(find.textContaining('Section B: The Time Machine'), findsOneWidget);
    expect(find.textContaining('Section A: Live Game Baselines'), findsOneWidget);
    expect(find.textContaining('Section C: Fatigue & Daily Rest Card'), findsOneWidget);
    expect(find.textContaining('Section D: Variety Nudge'), findsOneWidget);

    // Baseline catalog games should be displayed
    expect(find.text('Market Basket'), findsOneWidget);
    expect(find.text('Trace the Path'), findsOneWidget);
    expect(find.text('Sort the Harvest'), findsOneWidget);
  });

  testWidgets('Simulate Perfect Play button writes 10 trials to database', (tester) async {
    await tester.pumpWidget(createSubject());
    await tester.pumpAndSettle();

    // Find the first "Simulate Perfect" button and tap it
    final perfectButtons = find.text('Simulate Perfect');
    expect(perfectButtons, findsWidgets);

    await tester.tap(perfectButtons.first);
    await tester.pumpAndSettle();

    // Verify 10 trial events exist in SQLite for market_basket
    final trials = await (db.select(db.trialEvents)
          ..where((t) => t.gameId.equals('market_basket')))
        .get();
    expect(trials, hasLength(10));
    expect(trials.every((t) => t.correct), isTrue);
  });

  testWidgets('Simulate Poor Play button writes 10 trials to database with 30% score', (tester) async {
    await tester.pumpWidget(createSubject());
    await tester.pumpAndSettle();

    final poorButtons = find.text('Simulate Poor');
    expect(poorButtons, findsWidgets);

    await tester.tap(poorButtons.first);
    await tester.pumpAndSettle();

    final trials = await (db.select(db.trialEvents)
          ..where((t) => t.gameId.equals('market_basket')))
        .get();
    expect(trials, hasLength(10));
    final correctCount = trials.where((t) => t.correct).length;
    expect(correctCount, 3); // 30% accuracy
  });

  testWidgets('Force 4-Day Review button evaluates trials and updates baseline level', (tester) async {
    tester.view.physicalSize = const Size(1280, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(createSubject());
    await tester.pumpAndSettle();

    // Simulate perfect play first so we have trials
    final perfectButtons = find.text('Simulate Perfect');
    await tester.tap(perfectButtons.first);
    await tester.pumpAndSettle();

    // Tap "Force 4-Day Review Now"
    final forceButton = find.byKey(const Key('debug_force_review_button'));
    expect(forceButton, findsOneWidget);
    await tester.tap(forceButton);
    await tester.pumpAndSettle();

    // Dialog showing results pops up
    expect(find.text('Time Machine Review Results'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining('RAISE'),
      ),
      findsOneWidget,
    );

    // Dismiss dialog
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    // Baseline level for market_basket should now be 6.0 (raised from 5.0)
    final progress = await services.progressionRepo.getGameProgress('market_basket');
    expect(progress.level, 6.0);
  });

  testWidgets('+30m Playtime button inflates playtime and Trigger Rest Card displays modal', (tester) async {
    tester.view.physicalSize = const Size(1280, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(createSubject());
    await tester.pumpAndSettle();

    expect(find.textContaining('0.0 minutes'), findsOneWidget);

    // Tap "+30m Playtime"
    final addTimeButton = find.text('+30m Playtime');
    expect(addTimeButton, findsOneWidget);
    await tester.tap(addTimeButton);
    await tester.pumpAndSettle();

    expect(find.textContaining('30.0 minutes'), findsOneWidget);

    // Tap "Trigger Rest Card Check"
    final triggerButton = find.text('Trigger Rest Card Check');
    expect(triggerButton, findsOneWidget);
    await tester.tap(triggerButton);
    await tester.pumpAndSettle();

    // Tea break dialog pops up
    expect(find.text('Time for a Tea Break 🍵'), findsOneWidget);
    expect(find.text('Take a break'), findsOneWidget);
    expect(find.text('Keep playing'), findsOneWidget);

    // Tap "Keep playing"
    await tester.tap(find.text('Keep playing'));
    await tester.pumpAndSettle();

    // Verify override count incremented
    final restState = await services.progressionRepo.getRestState(now: DateTime.now());
    expect(restState.keepPlayingCount, 1);
  });

  testWidgets('Reset Fatigue button resets counters', (tester) async {
    tester.view.physicalSize = const Size(1280, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(createSubject());
    await tester.pumpAndSettle();

    // Add playtime first
    await tester.tap(find.text('+30m Playtime'));
    await tester.pumpAndSettle();

    // Tap Reset Fatigue
    await tester.tap(find.text('Reset Fatigue'));
    await tester.pumpAndSettle();

    expect(find.textContaining('0.0 minutes'), findsOneWidget);
    final restState = await services.progressionRepo.getRestState(now: DateTime.now());
    expect(restState.playSecondsToday, 0);
    expect(restState.keepPlayingCount, 0);
  });

  testWidgets('long-pressing version on HomeScreen opens ProgressionDebugScreen', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(services: services),
      ),
    );
    await tester.pumpAndSettle();

    final trigger = find.byKey(const Key('home_progression_debug_trigger'));
    expect(trigger, findsOneWidget);

    await tester.longPress(trigger);
    await tester.pumpAndSettle();

    expect(find.byType(ProgressionDebugScreen), findsOneWidget);
  });
}
