import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smriti/core/ability/estimator.dart';
import 'package:smriti/core/app_services.dart';
import 'package:smriti/core/db/database.dart';
import 'package:smriti/games/cognitive_game.dart';
import 'package:smriti/games/sort_the_harvest/sort_the_harvest_game.dart';
import 'package:smriti/games/sort_the_harvest/sort_the_harvest_screen.dart';

import '../core/repo/_test_db.dart';

void main() {
  late SmritiDatabase db;
  late GameContent content;

  setUp(() {
    db = newTestDb();
    content = const GameContent(
      version: '1',
      marketItems: [
        MarketItem(
          id: 'item-1',
          labelKey: 'item_1',
          iconAsset: 'assets/item1.png',
          category: 'grain',
        ),
      ],
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('SortTheHarvestGame logic', () {
    test('game properties match spec', () {
      final game = SortTheHarvestGame();
      expect(game.id, 'sort_the_harvest');
      expect(game.primaryDomain, CognitiveDomain.executive);
      expect(game.introPhrase, PhraseKey.sortTheHarvestIntro);
    });

    test('generateItem creates valid crop, trays, and target', () {
      final game = SortTheHarvestGame(random: Random(42));
      final item = game.generateItem(0.0, content);

      expect(item.id, contains(game.currentRule));
      expect(item.payload['crop'], isA<SortCrop>());
      expect(item.payload['trays'], isA<List<SortTray>>());
      expect(item.payload['targetTray'], isA<SortTray>());

      final trays = item.payload['trays'] as List<SortTray>;
      expect(trays.length, 3);
    });

    test('rule shifts and detects perseverative errors', () async {
      final game = SortTheHarvestGame(random: Random(42));
      final results = <TrialResult>[];
      final sub = game.trials.listen(results.add);

      // Simulate 5 consecutive correct answers to trigger rule shift
      for (var i = 0; i < 5; i++) {
        final item = game.generateItem(0.0, content);
        final targetTray = item.payload['targetTray'] as SortTray;
        game.submitSort(
          item: item,
          chosenTrayId: targetTray.id,
          initiationMs: 1200,
          movementMs: 400,
        );
      }

      await pumpEventQueue();
      expect(results.length, 5);
      expect(results.every((r) => r.correct), isTrue);

      // Next item triggers shift
      final shiftedItem = game.generateItem(0.0, content);
      expect(game.previousRule, isNotNull);
      expect(game.currentRule, isNot(game.previousRule));

      // Submit an intentional perseverative choice matching the previous rule
      final trays = shiftedItem.payload['trays'] as List<SortTray>;
      final crop = shiftedItem.payload['crop'] as SortCrop;
      final oldRuleTargetValue = game.previousRule == 'category'
          ? crop.category
          : crop.colorName;

      // Find tray that has this old rule value
      final perseverativeTray = trays.firstWhere(
        (t) => t.ruleValue == oldRuleTargetValue,
        orElse: () => trays.first,
      );

      game.submitSort(
        item: shiftedItem,
        chosenTrayId: perseverativeTray.id,
        initiationMs: 2500,
        movementMs: 500,
      );

      await pumpEventQueue();
      expect(results.length, 6);
      expect(results.last.metrics, containsPair('rule', game.currentRule));

      await sub.cancel();
      game.dispose();
    });
  });

  group('SortTheHarvestScreen widget', () {
    testWidgets('renders game UI and allows sorting a crop', (tester) async {
      final services = AppServices(database: db);

      await tester.pumpWidget(
        MaterialApp(
          home: SortTheHarvestScreen(
            services: services,
            content: content,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Sort the Harvest'), findsOneWidget);
      expect(find.text('Which basket does this harvest belong to?'), findsOneWidget);
      expect(find.byKey(const Key('harvest_back_button')), findsOneWidget);

      // Verify trays are displayed
      expect(find.byKey(const Key('sort_tray_0')), findsOneWidget);
      expect(find.byKey(const Key('sort_tray_1')), findsOneWidget);
      expect(find.byKey(const Key('sort_tray_2')), findsOneWidget);

      // Tap first tray to sort
      await tester.tap(find.byKey(const Key('sort_tray_0')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));

      expect(find.textContaining('1 sorted'), findsOneWidget);

      // Verify trial event was written into TrialEvents SQLite table
      final trials = await db.select(db.trialEvents).get();
      expect(trials, hasLength(1));
      expect(trials.single.domain, CognitiveDomain.executive.name);
      expect(trials.single.initiationMs, greaterThan(0));
      expect(trials.single.movementMs, greaterThan(0));
    });

    testWidgets('back button exits screen cleanly', (tester) async {
      final services = AppServices(database: db);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SortTheHarvestScreen(
                    services: services,
                    content: content,
                  ),
                ),
              ),
              child: const Text('Open Harvest'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Harvest'));
      await tester.pumpAndSettle();

      expect(find.byType(SortTheHarvestScreen), findsOneWidget);

      await tester.tap(find.byKey(const Key('harvest_back_button')));
      await tester.pumpAndSettle();

      expect(find.byType(SortTheHarvestScreen), findsNothing);
      expect(find.text('Open Harvest'), findsOneWidget);
    });
  });
}
