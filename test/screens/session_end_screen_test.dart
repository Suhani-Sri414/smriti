import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smriti/core/app_services.dart';
import 'package:smriti/core/db/database.dart';
import 'package:smriti/screens/session_end_screen.dart';

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
    String? gameTitle,
  }) {
    return MaterialApp(
      home: SessionEndScreen(
        services: services,
        gameTitle: gameTitle,
      ),
    );
  }

  testWidgets('renders default elder name and warm zero-shame message',
      (tester) async {
    final services = AppServices(database: db);
    await tester.pumpWidget(createSubject(services: services));
    await tester.pump();

    // Default name is Ibemhal
    expect(find.byKey(const Key('session_end_greeting')), findsOneWidget);
    expect(find.text('Thank you, Ibemhal'), findsOneWidget);
    expect(
        find.text('You spent wonderful time playing today.'), findsOneWidget);
    expect(find.text('Everything is calm and at peace.'), findsOneWidget);

    // Rule 11 zero-shame invariants: no score, no stars, no streak, no numbers
    expect(find.textContaining('Score'), findsNothing);
    expect(find.textContaining('Points'), findsNothing);
    expect(find.textContaining('Streak'), findsNothing);
    expect(find.textContaining('Correct'), findsNothing);
    expect(find.textContaining('Wrong'), findsNothing);
    expect(find.textContaining('%'), findsNothing);

    // Both primary action buttons present
    expect(find.byKey(const Key('session_end_home_button')), findsOneWidget);
    expect(find.byKey(const Key('session_end_games_button')), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Other Games'), findsOneWidget);
  });

  testWidgets('loads configured elder name from AppConfigs', (tester) async {
    final services = AppServices(database: db);
    await db.appConfigsDao.setValue('elderName', 'Memcha Devi');

    await tester.pumpWidget(createSubject(services: services));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Thank you, Memcha Devi'), findsOneWidget);
  });

  testWidgets('renders game title tag when supplied', (tester) async {
    final services = AppServices(database: db);
    await tester.pumpWidget(
      createSubject(services: services, gameTitle: 'Market Basket'),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Market Basket'), findsOneWidget);
  });

  testWidgets('tapping Other Games button pops back to previous route',
      (tester) async {
    final services = AppServices(database: db);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SessionEndScreen(
                      services: services,
                      gameTitle: 'Sort the Harvest',
                    ),
                  ),
                );
              },
              child: const Text('Launch End Screen'),
            ),
          ),
        ),
      ),
    );

    // Open Screen 09
    await tester.tap(find.text('Launch End Screen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('session_end_games_button')), findsOneWidget);

    // Tap Other Games
    await tester.tap(find.byKey(const Key('session_end_games_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Back on initial route
    expect(find.text('Launch End Screen'), findsOneWidget);
    expect(find.byKey(const Key('session_end_games_button')), findsNothing);
  });

  testWidgets('tapping Home button pops to root route', (tester) async {
    final services = AppServices(database: db);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                // First level: Games Menu
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (menuContext) => Scaffold(
                      body: ElevatedButton(
                        onPressed: () {
                          // Second level: Session End Screen
                          Navigator.of(menuContext).push(
                            MaterialPageRoute(
                              builder: (_) => SessionEndScreen(
                                services: services,
                              ),
                            ),
                          );
                        },
                        child: const Text('In Games Menu'),
                      ),
                    ),
                  ),
                );
              },
              child: const Text('Root Home'),
            ),
          ),
        ),
      ),
    );

    // Navigate to Menu
    await tester.tap(find.text('Root Home'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('In Games Menu'), findsOneWidget);

    // Navigate to Session End Screen
    await tester.tap(find.text('In Games Menu'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('session_end_home_button')), findsOneWidget);

    // Tap Home button
    await tester.tap(find.byKey(const Key('session_end_home_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Popped all the way back to Root Home
    expect(find.text('Root Home'), findsOneWidget);
    expect(find.text('In Games Menu'), findsNothing);
    expect(find.byKey(const Key('session_end_home_button')), findsNothing);
  });
}
