import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smriti/core/app_services.dart';
import 'package:smriti/core/db/database.dart';
import 'package:smriti/games/market_basket/market_basket_screen.dart';
import 'package:smriti/screens/games_menu_screen.dart';
import 'package:smriti/screens/ghost_demo_screen.dart';

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
    String gameId = 'market_basket',
    String? sessionId,
    VoidCallback? onStartGame,
    VoidCallback? onBack,
    Duration demoStepDuration = const Duration(milliseconds: 1),
    bool autoStartDemo = true,
  }) {
    return MaterialApp(
      home: GhostDemoScreen(
        services: services,
        gameId: gameId,
        sessionId: sessionId,
        onStartGame: onStartGame,
        onBack: onBack,
        demoStepDuration: demoStepDuration,
        autoStartDemo: autoStartDemo,
      ),
    );
  }

  testWidgets(
      'renders Screen 03 header, guidance banner, stage preview, and controls',
      (tester) async {
    final services = AppServices(database: db);
    await tester.pumpWidget(createSubject(services: services));
    await tester.pumpAndSettle();

    // Screen 03 prototype identity
    expect(find.text('03'), findsOneWidget);
    expect(find.text('Game host — ghost demo'), findsOneWidget);
    expect(find.text('Market Basket'), findsOneWidget);

    // Non-verbal guidance banner
    expect(find.text('Watch first'), findsOneWidget);
    expect(
      find.text(
          'Before any round, a ghost hand plays one move so the rule is never explained in words.'),
      findsOneWidget,
    );

    // Stage preview elements for Market Basket
    expect(find.text('Market Basket — Remember these goods'), findsOneWidget);
    expect(find.text('Assam Tea'), findsOneWidget);
    expect(find.text('Aromatic Rice'), findsOneWidget);
    expect(find.text('Fresh Ginger'), findsOneWidget);

    // Buttons
    expect(find.byKey(const Key('ghost_demo_back_button')), findsOneWidget);
    expect(find.byKey(const Key('ghost_demo_watch_again_button')), findsOneWidget);
    expect(find.byKey(const Key('ghost_demo_play_button')), findsOneWidget);
    expect(find.text('Watch again'), findsOneWidget);
    expect(find.text('I\'m ready'), findsOneWidget);

    // Ghost hand overlay is mounted
    expect(find.byKey(const Key('ghost_demo_overlay')), findsOneWidget);
    expect(find.byKey(const Key('ghost_hand_visual')), findsOneWidget);
  });

  testWidgets('tapping back button calls onBack or pops screen', (tester) async {
    final services = AppServices(database: db);
    bool backCalled = false;

    await tester.pumpWidget(
      createSubject(
        services: services,
        onBack: () => backCalled = true,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('ghost_demo_back_button')));
    await tester.pumpAndSettle();

    expect(backCalled, isTrue);
  });

  testWidgets(
      'tapping Watch again triggers demo replay and increments demoReplays in SQLite',
      (tester) async {
    final services = AppServices(database: db);
    const testSessionId = 'test-session-03';

    // Insert active session row in SQLite
    await services.eventRepo.insertSession(
      SessionsCompanion.insert(
        id: testSessionId,
        startedAt: DateTime.now().millisecondsSinceEpoch,
        gameIds: 'market_basket',
      ),
    );

    await tester.pumpWidget(
      createSubject(
        services: services,
        sessionId: testSessionId,
        demoStepDuration: const Duration(milliseconds: 1),
      ),
    );
    await tester.pumpAndSettle();

    // Initial replay count on session row should be 0
    var session = await services.eventRepo.getSession(testSessionId);
    expect(session!.demoReplays, 0);

    // Tap "Watch again"
    await tester.tap(find.byKey(const Key('ghost_demo_watch_again_button')));
    await tester.pumpAndSettle();

    // demoReplays bumped to 1
    session = await services.eventRepo.getSession(testSessionId);
    expect(session!.demoReplays, 1);
    expect(find.text('Watched 1 time'), findsOneWidget);

    // Tap "Watch again" second time
    await tester.tap(find.byKey(const Key('ghost_demo_watch_again_button')));
    await tester.pumpAndSettle();

    // demoReplays bumped to 2
    session = await services.eventRepo.getSession(testSessionId);
    expect(session!.demoReplays, 2);
    expect(find.text('Watched 2 times'), findsOneWidget);
  });

  testWidgets('tapping I\'m ready button triggers onStartGame callback',
      (tester) async {
    final services = AppServices(database: db);
    bool startCalled = false;

    await tester.pumpWidget(
      createSubject(
        services: services,
        onStartGame: () => startCalled = true,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('ghost_demo_play_button')));
    await tester.pumpAndSettle();

    expect(startCalled, isTrue);
  });

  testWidgets('tapping I\'m ready button replaces route with MarketBasketScreen',
      (tester) async {
    final services = AppServices(database: db);

    await tester.pumpWidget(
      MaterialApp(
        home: GhostDemoScreen(
          services: services,
          gameId: 'market_basket',
          demoStepDuration: const Duration(milliseconds: 1),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('ghost_demo_play_button')));
    await tester.pumpAndSettle();

    expect(find.byType(MarketBasketScreen), findsOneWidget);
  });

  testWidgets('renders stage preview correctly for Sort the Harvest',
      (tester) async {
    final services = AppServices(database: db);
    await tester.pumpWidget(
      createSubject(services: services, gameId: 'sort_the_harvest'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sort the Harvest'), findsOneWidget);
    expect(find.text('Left Tray: Greens & Leaves'), findsOneWidget);
    expect(find.text('Right Tray: Roots & Tubers'), findsOneWidget);
    expect(find.text('Bitter Gourd'), findsOneWidget);
  });

  testWidgets('renders stage preview correctly for Faces of My Family',
      (tester) async {
    final services = AppServices(database: db);
    await tester.pumpWidget(
      createSubject(services: services, gameId: 'faces_of_my_family'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Faces of My Family'), findsOneWidget);
    expect(find.text('Who is this?'), findsOneWidget);
    expect(find.text('Bina'), findsOneWidget);
    expect(find.text('Pari'), findsOneWidget);
    expect(find.text('Deepak'), findsOneWidget);
  });

  testWidgets('renders stage preview correctly for Sounds of Home',
      (tester) async {
    final services = AppServices(database: db);
    await tester.pumpWidget(
      createSubject(services: services, gameId: 'sounds_of_home'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sounds of Home'), findsOneWidget);
    expect(find.text('Listen to the sound...'), findsOneWidget);
    expect(find.text('Temple Bell'), findsOneWidget);
    expect(find.text('Monsoon Rain'), findsOneWidget);
    expect(find.text('Morning Hornbill'), findsOneWidget);
  });

  testWidgets('GamesMenuScreen with showGhostDemo=true routes to GhostDemoScreen',
      (tester) async {
    final services = AppServices(database: db);
    await tester.pumpWidget(
      MaterialApp(
        home: GamesMenuScreen(
          services: services,
          showGhostDemo: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('game_card_market_basket')));
    await tester.pumpAndSettle();

    expect(find.byType(GhostDemoScreen), findsOneWidget);
    expect(find.text('03'), findsOneWidget);
    expect(find.text('Game host — ghost demo'), findsOneWidget);
  });
}
