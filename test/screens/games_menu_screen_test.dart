import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smriti/core/app_services.dart';
import 'package:smriti/core/db/database.dart';
import 'package:smriti/games/faces_of_my_family/faces_of_my_family_screen.dart';
import 'package:smriti/games/market_basket/market_basket_screen.dart';
import 'package:smriti/games/sort_the_harvest/sort_the_harvest_screen.dart';
import 'package:smriti/games/sounds_of_home/sounds_of_home_screen.dart';
import 'package:smriti/screens/games_menu_screen.dart';

import '../core/repo/_test_db.dart';

void main() {
  late SmritiDatabase db;

  setUp(() {
    db = newTestDb();
  });

  tearDown(() async {
    await db.close();
  });

  Widget createSubject({required AppServices services}) {
    return MaterialApp(
      home: GamesMenuScreen(services: services),
    );
  }

  testWidgets('renders top bar and all four game cards', (tester) async {
    final services = AppServices(database: db);
    await tester.pumpWidget(createSubject(services: services));
    await tester.pumpAndSettle();

    expect(find.text('Games'), findsOneWidget);
    expect(find.byKey(const Key('games_back_button')), findsOneWidget);

    expect(find.byKey(const Key('game_card_market_basket')), findsOneWidget);
    expect(find.text('Market Basket'), findsOneWidget);
    expect(find.text('Remember what to buy'), findsOneWidget);

    expect(find.byKey(const Key('game_card_faces')), findsOneWidget);
    expect(find.text('Faces of My Family'), findsOneWidget);
    expect(find.text('Recognize family members'), findsOneWidget);

    expect(find.byKey(const Key('game_card_sort_harvest')), findsOneWidget);
    expect(find.text('Sort the Harvest'), findsOneWidget);
    expect(find.text('Sort into the right tray'), findsOneWidget);

    expect(find.byKey(const Key('game_card_sounds')), findsOneWidget);
    expect(find.text('Sounds of Home'), findsOneWidget);
    expect(find.text('Listen and identify sounds'), findsOneWidget);
  });

  testWidgets('tapping back button pops the screen', (tester) async {
    final services = AppServices(database: db);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => GamesMenuScreen(services: services),
              ),
            ),
            child: const Text('Open Games'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Games'));
    await tester.pumpAndSettle();

    expect(find.byType(GamesMenuScreen), findsOneWidget);

    await tester.tap(find.byKey(const Key('games_back_button')));
    await tester.pumpAndSettle();

    expect(find.byType(GamesMenuScreen), findsNothing);
    expect(find.text('Open Games'), findsOneWidget);
  });

  testWidgets('tapping Market Basket opens MarketBasketScreen', (tester) async {
    final services = AppServices(database: db);
    await tester.pumpWidget(createSubject(services: services));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('game_card_market_basket')));
    await tester.pumpAndSettle();

    expect(find.byType(MarketBasketScreen), findsOneWidget);
  });

  testWidgets('tapping Sort the Harvest opens SortTheHarvestScreen',
      (tester) async {
    final services = AppServices(database: db);
    await tester.pumpWidget(createSubject(services: services));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('game_card_sort_harvest')));
    await tester.pumpAndSettle();

    expect(find.byType(SortTheHarvestScreen), findsOneWidget);
  });

  testWidgets('tapping Faces of My Family opens FacesOfMyFamilyScreen',
      (tester) async {
    final services = AppServices(database: db);
    await tester.pumpWidget(createSubject(services: services));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('game_card_faces')));
    await tester.pumpAndSettle();

    expect(find.byType(FacesOfMyFamilyScreen), findsOneWidget);
  });

  testWidgets('tapping Sounds of Home opens SoundsOfHomeScreen',
      (tester) async {
    final services = AppServices(database: db);
    await tester.pumpWidget(createSubject(services: services));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('game_card_sounds')));
    await tester.pumpAndSettle();

    expect(find.byType(SoundsOfHomeScreen), findsOneWidget);
  });
}
