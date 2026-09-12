import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smriti/core/ability/estimator.dart';
import 'package:smriti/core/app_services.dart';
import 'package:smriti/core/db/database.dart';
import 'package:smriti/games/cognitive_game.dart';
import 'package:smriti/games/market_basket/market_basket_game.dart';
import 'package:smriti/games/market_basket/market_basket_screen.dart';

import '../core/repo/_test_db.dart';

GameContent _loadTestContent() {
  final file = File('assets/mock_content/mock_content.json');
  return GameContent.fromJson(
    jsonDecode(file.readAsStringSync()) as Map<String, Object?>,
  );
}

void main() {
  late SmritiDatabase db;
  late GameContent content;

  setUp(() async {
    db = newTestDb();
    content = _loadTestContent();
  });

  tearDown(() async {
    await db.close();
  });

  group('MarketBasketGame Interface & Logic', () {
    test('game metadata conforms to CognitiveGame interface', () {
      final game = MarketBasketGame();
      expect(game.id, 'market_basket');
      expect(game.primaryDomain, CognitiveDomain.memory);
      expect(game.introPhrase, PhraseKey.marketBasketIntro);
      game.dispose();
    });

    test('generateItem creates target and shelf with near/far distractors', () {
      final game = MarketBasketGame(random: Random(42));
      final item = game.generateItem(0.0, content);

      expect(item.id, startsWith('mb_'));
      final target = (item.payload['target'] as List<Object?>).cast<MarketItem>();
      final shelf = (item.payload['shelf'] as List<Object?>).cast<MarketItem>();

      expect(target.length, greaterThanOrEqualTo(2));
      expect(shelf.length, greaterThanOrEqualTo(target.length));
      for (final t in target) {
        expect(shelf.map((s) => s.id), contains(t.id));
      }

      game.dispose();
    });
  });

  group('MarketBasketScreen Widget (Screens 04 & 05)', () {
    Widget buildSubject(AppServices services) {
      return MaterialApp(
        home: MarketBasketScreen(
          services: services,
          content: content,
        ),
      );
    }

    testWidgets('renders top bar, title, back button, hint button, and phase 1 list',
        (tester) async {
      final services = AppServices(database: db);

      await tester.pumpWidget(buildSubject(services));
      await tester.pumpAndSettle();

      // Top bar
      expect(find.byKey(const Key('mb_back_button')), findsOneWidget);
      expect(find.textContaining('Market Basket'), findsOneWidget);
      expect(find.byKey(const Key('mb_hint_button')), findsOneWidget);

      // Phase 1: Memorization list
      expect(find.byKey(const Key('mb_list')), findsOneWidget);
      expect(find.text('Remember these items for your basket'), findsOneWidget);
      expect(find.byKey(const Key('mb_ready')), findsOneWidget);
    });

    testWidgets('tapping I am ready transitions to woven mat shelf (Screen 04)',
        (tester) async {
      final services = AppServices(database: db);

      await tester.pumpWidget(buildSubject(services));
      await tester.pumpAndSettle();

      // Tap ready button
      await tester.tap(find.byKey(const Key('mb_ready')));
      await tester.pumpAndSettle();

      // Phase 2: Shelf on woven mat
      expect(find.byKey(const Key('mb_shelf')), findsOneWidget);
      expect(find.textContaining('Put the items you remember into the basket'),
          findsOneWidget);
      expect(find.byKey(const Key('mb_submit')), findsOneWidget);
    });

    testWidgets('allows picking items and toggling selection on the mat',
        (tester) async {
      final services = AppServices(database: db);

      await tester.pumpWidget(buildSubject(services));
      await tester.pumpAndSettle();

      // Go to shelf
      await tester.tap(find.byKey(const Key('mb_ready')));
      await tester.pumpAndSettle();

      // Find any item on the mat
      final itemCards = find.byWidgetPredicate(
        (w) => w.key != null && w.key.toString().contains('mb_pick_'),
      );
      expect(itemCards, findsWidgets);

      // Tap first item
      await tester.tap(itemCards.first);
      await tester.pumpAndSettle();

      expect(find.textContaining('1 of'), findsOneWidget);

      // Tap again to toggle off
      await tester.tap(itemCards.first);
      await tester.pumpAndSettle();

      expect(find.textContaining('0 of'), findsOneWidget);
    });

    testWidgets('hint escalation provides category cue and eliminates distractor',
        (tester) async {
      final services = AppServices(database: db);

      await tester.pumpWidget(buildSubject(services));
      await tester.pumpAndSettle();

      // Go to shelf
      await tester.tap(find.byKey(const Key('mb_ready')));
      await tester.pumpAndSettle();

      // Tap hint button (Level 1)
      await tester.tap(find.byKey(const Key('mb_hint_button')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Think of items from'), findsOneWidget);

      // Tap hint button again (Level 2)
      await tester.tap(find.byKey(const Key('mb_hint_button')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Look closely at the items remaining'),
          findsOneWidget);
    });

    testWidgets('submitting correct choices triggers praise state (Screen 05)',
        (tester) async {
      final services = AppServices(database: db);

      await tester.pumpWidget(buildSubject(services));
      await tester.pumpAndSettle();

      // Find target items in phase 1
      final targetWidgets = find.byWidgetPredicate(
        (w) => w.key != null && w.key.toString().contains('mb_target_'),
      );
      final targetIds = <String>[];
      for (final element in targetWidgets.evaluate()) {
        final keyStr = element.widget.key.toString();
        final id = keyStr.replaceAll("[<'mb_target_", '').replaceAll("'>]", '');
        targetIds.add(id);
      }
      expect(targetIds, isNotEmpty);

      // Move to shelf
      await tester.tap(find.byKey(const Key('mb_ready')));
      await tester.pumpAndSettle();

      // Pick all target items
      for (final id in targetIds) {
        await tester.tap(find.byKey(Key('mb_pick_$id')));
        await tester.pumpAndSettle();
      }

      // Submit
      await tester.tap(find.byKey(const Key('mb_submit')));
      await tester.pump();

      // Screen 05 praise banner
      expect(find.text('Yes! Everything is in the basket!'), findsOneWidget);

      // Wait for transition to next trial
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pumpAndSettle();

      // Returns to list for next trial
      expect(find.byKey(const Key('mb_list')), findsOneWidget);
    });

    testWidgets('submitting incorrect choices returns gentle neutral guidance (Rule 11)',
        (tester) async {
      final services = AppServices(database: db);

      await tester.pumpWidget(buildSubject(services));
      await tester.pumpAndSettle();

      // Move to shelf without picking anything (or picking wrong)
      await tester.tap(find.byKey(const Key('mb_ready')));
      await tester.pumpAndSettle();

      // Submit empty
      await tester.tap(find.byKey(const Key('mb_submit')));
      await tester.pump();

      // Rule 11 zero-shame neutral guidance
      expect(find.text('Let us check the basket together'), findsOneWidget);
      expect(find.textContaining('wrong'), findsNothing);
      expect(find.textContaining('Wrong'), findsNothing);

      // Wait for transition to next trial
      await tester.pump(const Duration(milliseconds: 1800));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('mb_list')), findsOneWidget);
    });

    testWidgets('back button exits screen cleanly', (tester) async {
      final services = AppServices(database: db);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => MarketBasketScreen(
                    services: services,
                    content: content,
                  ),
                ),
              ),
              child: const Text('Open Basket'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Basket'));
      await tester.pumpAndSettle();

      expect(find.byType(MarketBasketScreen), findsOneWidget);

      await tester.tap(find.byKey(const Key('mb_back_button')));
      await tester.pumpAndSettle();

      expect(find.byType(MarketBasketScreen), findsNothing);
      expect(find.text('Open Basket'), findsOneWidget);
    });
  });
}
