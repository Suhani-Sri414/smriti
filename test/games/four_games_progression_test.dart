import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smriti/core/app_services.dart';
import 'package:smriti/core/db/database.dart';
import 'package:smriti/core/progression/difficulty_source.dart';
import 'package:smriti/core/progression/game_level_profiles.dart';
import 'package:smriti/core/progression/level_scale.dart';
import 'package:smriti/core/progression/progression_state.dart';
import 'package:smriti/core/progression/trial_scoring.dart';
import 'package:smriti/games/cognitive_game.dart';
import 'package:smriti/games/faces_of_my_family/faces_of_my_family_game.dart';
import 'package:smriti/games/market_basket/market_basket_game.dart';
import 'package:smriti/games/session_runner.dart';
import 'package:smriti/games/sort_the_harvest/sort_the_harvest_game.dart';
import 'package:smriti/games/sounds_of_home/sounds_of_home_game.dart';
import 'package:smriti/screens/home_screen.dart';
import 'package:smriti/ui/debug/progression_debug_screen.dart';
import 'package:smriti/ui/widgets/rest_card_dialog.dart';

import '../core/repo/_test_db.dart';

void main() {
  late SmritiDatabase db;
  late AppServices services;
  const content = GameContent(
    version: '1',
    marketItems: [
      MarketItem(
        id: 'item-1',
        labelKey: 'apple',
        iconAsset: 'assets/apple.png',
        category: 'fruits',
      ),
      MarketItem(
        id: 'item-2',
        labelKey: 'banana',
        iconAsset: 'assets/banana.png',
        category: 'fruits',
      ),
      MarketItem(
        id: 'item-3',
        labelKey: 'carrot',
        iconAsset: 'assets/carrot.png',
        category: 'vegetables',
      ),
      MarketItem(
        id: 'item-4',
        labelKey: 'spinach',
        iconAsset: 'assets/spinach.png',
        category: 'vegetables',
      ),
      MarketItem(
        id: 'item-5',
        labelKey: 'rice',
        iconAsset: 'assets/rice.png',
        category: 'grains',
      ),
      MarketItem(
        id: 'item-6',
        labelKey: 'wheat',
        iconAsset: 'assets/wheat.png',
        category: 'grains',
      ),
    ],
  );

  setUp(() {
    db = newTestDb();
    services = AppServices(database: db);
  });

  tearDown(() async {
    await db.close();
  });

  group('Four Games Dynamic Parameter Generation', () {
    test('Market Basket scales listLength and nearDistractors with level', () {
      final game = MarketBasketGame(random: Random(42));
      final lowLevelParams = GameLevelProfiles.marketBasket.paramsAt(1.0);
      final highLevelParams = GameLevelProfiles.marketBasket.paramsAt(9.0);

      expect(lowLevelParams['targetCount'], 2.0);
      expect(highLevelParams['targetCount'], greaterThan(3.0));

      final lowItem = game.generateItem(LevelScale.levelToDifficulty(1.0), content);
      final highItem = game.generateItem(LevelScale.levelToDifficulty(9.0), content);

      final lowTargets = (lowItem.payload['target'] as List).length;
      final highTargets = (highItem.payload['target'] as List).length;

      expect(lowTargets, 2);
      expect(highTargets, greaterThanOrEqualTo(3));
      game.dispose();
    });

    test('Faces of My Family scales candidateCount (2 to 4) with level', () {
      final game = FacesOfMyFamilyGame(random: Random(42));
      final lowLevelParams = GameLevelProfiles.facesOfFamily.paramsAt(1.0);
      final highLevelParams = GameLevelProfiles.facesOfFamily.paramsAt(9.0);

      expect(lowLevelParams['candidateCount'], 2.0);
      expect(highLevelParams['candidateCount'], 4.0);

      final lowItem = game.generateItem(LevelScale.levelToDifficulty(1.0), content);
      final highItem = game.generateItem(LevelScale.levelToDifficulty(9.0), content);

      final lowOptions = (lowItem.payload['options'] as List).length;
      final highOptions = (highItem.payload['options'] as List).length;

      expect(lowOptions, 2);
      expect(highOptions, 4);
      game.dispose();
    });

    test('Sort the Harvest generates 2 trays at L <= 2.5 and 3 trays at L >= 3.0', () {
      final game = SortTheHarvestGame(random: Random(42));

      final lowItem = game.generateItem(LevelScale.levelToDifficulty(1.0), content);
      final midItem = game.generateItem(LevelScale.levelToDifficulty(5.0), content);

      final lowTrays = (lowItem.payload['trays'] as List).length;
      final midTrays = (midItem.payload['trays'] as List).length;

      expect(lowTrays, 2);
      expect(midTrays, 3);
      game.dispose();
    });

    test('Sounds of Home scales distractorSimilarity with level', () {
      final game = SoundsOfHomeGame(random: Random(42));
      final lowParams = GameLevelProfiles.soundsHome.paramsAt(1.0);
      final highParams = GameLevelProfiles.soundsHome.paramsAt(7.0);

      expect(lowParams['distractorSimilarity'], 0.0);
      expect(highParams['distractorSimilarity'], greaterThanOrEqualTo(0.4));

      final lowItem = game.generateItem(LevelScale.levelToDifficulty(1.0), content);
      final highItem = game.generateItem(LevelScale.levelToDifficulty(7.0), content);

      expect(lowItem.payload['options'], isNotEmpty);
      expect(highItem.payload['options'], isNotEmpty);
      game.dispose();
    });
  });

  group('In-Session Staircase Adaptation', () {
    test('3 consecutive hits increase offset by +0.5 clamped at +1.0', () {
      final staircase = StaircaseDifficultySource(baseLevel: 5.0);
      expect(staircase.currentLevel('market_basket'), 5.0);

      // 2 hits -> no change yet
      staircase.recordTrialResult(gameId: 'market_basket', correct: true);
      staircase.recordTrialResult(gameId: 'market_basket', correct: true);
      expect(staircase.currentLevel('market_basket'), 5.0);

      // 3rd hit -> +0.5
      staircase.recordTrialResult(gameId: 'market_basket', correct: true);
      expect(staircase.currentLevel('market_basket'), 5.5);
      expect(staircase.sessionOffset, 0.5);

      // 3 more hits -> +1.0
      staircase.recordTrialResult(gameId: 'market_basket', correct: true);
      staircase.recordTrialResult(gameId: 'market_basket', correct: true);
      staircase.recordTrialResult(gameId: 'market_basket', correct: true);
      expect(staircase.currentLevel('market_basket'), 6.0);
      expect(staircase.sessionOffset, 1.0);

      // 3 more hits -> clamped at +1.0 max
      staircase.recordTrialResult(gameId: 'market_basket', correct: true);
      staircase.recordTrialResult(gameId: 'market_basket', correct: true);
      staircase.recordTrialResult(gameId: 'market_basket', correct: true);
      expect(staircase.currentLevel('market_basket'), 6.0);
      expect(staircase.sessionOffset, 1.0);
    });

    test('2 consecutive misses decrease offset by -0.5 clamped at -1.0', () {
      final staircase = StaircaseDifficultySource(baseLevel: 5.0);

      // 1 miss -> no change yet
      staircase.recordTrialResult(gameId: 'market_basket', correct: false);
      expect(staircase.currentLevel('market_basket'), 5.0);

      // 2nd miss -> -0.5
      staircase.recordTrialResult(gameId: 'market_basket', correct: false);
      expect(staircase.currentLevel('market_basket'), 4.5);
      expect(staircase.sessionOffset, -0.5);

      // 2 more misses -> -1.0
      staircase.recordTrialResult(gameId: 'market_basket', correct: false);
      staircase.recordTrialResult(gameId: 'market_basket', correct: false);
      expect(staircase.currentLevel('market_basket'), 4.0);
      expect(staircase.sessionOffset, -1.0);

      // 2 more misses -> clamped at -1.0
      staircase.recordTrialResult(gameId: 'market_basket', correct: false);
      staircase.recordTrialResult(gameId: 'market_basket', correct: false);
      expect(staircase.currentLevel('market_basket'), 4.0);
      expect(staircase.sessionOffset, -1.0);

      // resetSession resets offset to 0.0
      staircase.resetSession();
      expect(staircase.sessionOffset, 0.0);
      expect(staircase.currentLevel('market_basket'), 5.0);
    });
  });

  group('Continuous Partial-Credit Scoring & Drift Persistence', () {
    test('TrialScoring computes partial credit correctly', () {
      // Multi-item recall: 3 targets, 1 missed, 0 intrusions -> 2/3 = 0.666...
      final basketScore = TrialScoring.computeTrialScore(
        gameId: 'market_basket',
        correct: false,
        metrics: {'targets': 3, 'missed': 1, 'intrusions': 0},
      );
      expect(basketScore, closeTo(0.666, 0.01));

      // Semantic near-miss error (e.g. Faces or Sounds) -> 0.5
      final semanticScore = TrialScoring.computeTrialScore(
        gameId: 'faces_of_my_family',
        correct: false,
        metrics: {'error_class': 'semantic'},
      );
      expect(semanticScore, 0.5);

      // Perseverative rule-shift error in Sort the Harvest -> 0.3
      final perseverativeScore = TrialScoring.computeTrialScore(
        gameId: 'sort_the_harvest',
        correct: false,
        metrics: {'error_class': 'perseverative'},
      );
      expect(perseverativeScore, 0.3);

      // Random error -> 0.0
      final randomScore = TrialScoring.computeTrialScore(
        gameId: 'faces_of_my_family',
        correct: false,
        metrics: {'error_class': 'random'},
      );
      expect(randomScore, 0.0);

      // Fully correct -> 1.0
      final correctScore = TrialScoring.computeTrialScore(
        gameId: 'sounds_of_home',
        correct: true,
      );
      expect(correctScore, 1.0);
    });

    test('SessionRunner records continuous score and persists to Drift SQLite', () async {
      final runner = SessionRunner(
        eventRepo: services.eventRepo,
        abilityRepo: services.abilityRepo,
        progressionService: services.progressionService,
        content: content,
      );

      final game = SoundsOfHomeGame(random: Random(42));
      await runner.start([game]);

      final item = await runner.nextItem(game);
      expect(item, isNotNull);

      // Submit correct choice
      final target = item!.payload['target'] as HomeSound;
      game.submitChoice(
        item: item,
        chosenId: target.id,
        initiationMs: 200,
        movementMs: 300,
      );

      // Allow async stream handling in SessionRunner to process
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Query TrialEvents from Drift
      final trials = await db.select(db.trialEvents).get();
      expect(trials, isNotEmpty);
      final lastTrial = trials.last;
      expect(lastTrial.correct, isTrue);

      final metrics = jsonDecode(lastTrial.metrics ?? '{}') as Map<String, dynamic>;
      expect(metrics['score'], 1.0);

      await runner.end(completed: true);
      game.dispose();
    });
  });

  group('Fatigue Check & Rest Card Modal', () {
    testWidgets('maybeShowRestCardDialog displays tea break modal and handles actions', (tester) async {
      // Simulate 31 minutes of play today (1860s >= 1800s threshold)
      final now = DateTime.now();
      final dateKey = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      await services.progressionRepo.saveRestState(
        RestState(
          dateKey: dateKey,
          playSecondsToday: 1860,
        ),
      );

      final restState = await services.progressionRepo.getRestState();
      expect(restState.shouldRest(), isTrue);

      bool? userChoice;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () async {
                  userChoice = await maybeShowRestCardDialog(
                    ctx,
                    progressionService: services.progressionService,
                  );
                },
                child: const Text('Check Rest'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Check Rest'));
      await tester.pumpAndSettle();

      expect(find.text('Time for a Tea Break 🍵'), findsOneWidget);
      expect(find.byKey(const Key('rest_card_keep_playing_button')), findsOneWidget);
      expect(find.byKey(const Key('rest_card_take_break_button')), findsOneWidget);

      // Tap "Keep playing"
      await tester.tap(find.byKey(const Key('rest_card_keep_playing_button')));
      await tester.pumpAndSettle();

      expect(userChoice, isTrue);
      final updatedState = await services.progressionRepo.getRestState();
      expect(updatedState.keepPlayingCount, 1);
    });
  });

  group('HomeScreen kDebugMode Safety Gate', () {
    test('kDebugMode evaluates to true in test runner', () {
      expect(kDebugMode, isTrue);
    });

    testWidgets('long press opens ProgressionDebugScreen when kDebugMode is enabled', (tester) async {
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
  });
}
