import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smriti/core/ability/estimator.dart';
import 'package:smriti/core/app_services.dart';
import 'package:smriti/core/db/database.dart';
import 'package:smriti/games/cognitive_game.dart';
import 'package:smriti/games/sounds_of_home/sounds_of_home_game.dart';
import 'package:smriti/games/sounds_of_home/sounds_of_home_screen.dart';

import '../core/repo/_test_db.dart';

void main() {
  late SmritiDatabase db;

  setUp(() {
    db = newTestDb();
  });

  tearDown(() async {
    await db.close();
  });

  group('SoundsOfHomeGame Logic', () {
    test('game metadata conforms to CognitiveGame interface', () {
      final game = SoundsOfHomeGame();
      expect(game.id, 'sounds_of_home');
      expect(game.primaryDomain, CognitiveDomain.attention);
      expect(game.introPhrase, PhraseKey.soundsIntro);
      game.dispose();
    });

    test('generateItem returns 1 target and 2 distractors', () {
      final game = SoundsOfHomeGame(random: Random(42));
      const content = GameContent(version: '1', marketItems: []);

      final item = game.generateItem(0.5, content);
      expect(item.id, isNotEmpty);
      expect(item.payload['target'], isA<HomeSound>());

      final options =
          (item.payload['options'] as List<Object?>).cast<HomeSound>();
      expect(options.length, 3);

      final target = item.payload['target'] as HomeSound;
      expect(options.map((o) => o.id), contains(target.id));

      game.dispose();
    });

    test('submitChoice emits correct TrialResult when answer matches', () async {
      final game = SoundsOfHomeGame(random: Random(42));
      const content = GameContent(version: '1', marketItems: []);
      final item = game.generateItem(0.0, content);
      final target = item.payload['target'] as HomeSound;

      final expectation = expectLater(
        game.trials,
        emits(
          predicate<TrialResult>((result) {
            return result.correct == true &&
                result.chosenId == null &&
                result.errorClass == null &&
                result.initiationMs == 1000 &&
                result.movementMs == 500;
          }),
        ),
      );

      game.submitChoice(
        item: item,
        chosenId: target.id,
        initiationMs: 1000,
        movementMs: 500,
      );

      await expectation;
      game.dispose();
    });

    test('submitChoice classifies error as semantic when same category is chosen',
        () async {
      const sounds = [
        HomeSound(
          id: 's1',
          label: 'Sound 1',
          category: 'kitchen',
          icon: Icons.kitchen,
          description: 'd1',
        ),
        HomeSound(
          id: 's2',
          label: 'Sound 2',
          category: 'kitchen', // same category
          icon: Icons.kitchen,
          description: 'd2',
        ),
        HomeSound(
          id: 's3',
          label: 'Sound 3',
          category: 'nature', // different category
          icon: Icons.park,
          description: 'd3',
        ),
      ];

      final game = SoundsOfHomeGame(soundList: sounds, random: Random(1));
      const content = GameContent(version: '1', marketItems: []);
      final item = game.generateItem(0.0, content);
      final target = item.payload['target'] as HomeSound;

      final distractor = sounds.firstWhere((s) => s.id != target.id);

      final expectation = expectLater(
        game.trials,
        emits(
          predicate<TrialResult>((result) {
            final expectedClass =
                distractor.category == target.category ? 'semantic' : 'random';
            return result.correct == false &&
                result.chosenId == distractor.id &&
                result.errorClass == expectedClass;
          }),
        ),
      );

      game.submitChoice(
        item: item,
        chosenId: distractor.id,
        initiationMs: 800,
        movementMs: 400,
      );

      await expectation;
      game.dispose();
    });
  });

  group('SoundsOfHomeScreen Widget', () {
    testWidgets(
        'renders game UI, prompt, replay button, and allows selecting choice',
        (tester) async {
      final services = AppServices(database: db);
      const content = GameContent(version: '1', marketItems: []);

      await tester.pumpWidget(
        MaterialApp(
          home: SoundsOfHomeScreen(
            services: services,
            content: content,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sounds of Home'), findsOneWidget);
      expect(find.text('What made this sound?'), findsOneWidget);
      expect(find.byKey(const Key('sounds_back_button')), findsOneWidget);
      expect(find.byKey(const Key('sounds_listen_button')), findsOneWidget);
      expect(find.byKey(const Key('sounds_hint_button')), findsOneWidget);

      // Verify choice cards exist
      final choiceCards = find.byWidgetPredicate(
        (w) => w.key != null && w.key.toString().contains('sound_option_'),
      );
      expect(choiceCards, findsNWidgets(3));

      // Tap listen again button
      await tester.tap(find.byKey(const Key('sounds_listen_button')));
      await tester.pump();

      // Tap hint button
      await tester.tap(find.byKey(const Key('sounds_hint_button')));
      await tester.pump();

      // Tap one choice
      await tester.tap(choiceCards.first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pump(const Duration(milliseconds: 1600));

      expect(find.byType(SoundsOfHomeScreen), findsOneWidget);
    });

    testWidgets('back button exits screen cleanly', (tester) async {
      final services = AppServices(database: db);
      const content = GameContent(version: '1', marketItems: []);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SoundsOfHomeScreen(
                    services: services,
                    content: content,
                  ),
                ),
              ),
              child: const Text('Launch Sounds'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Launch Sounds'));
      await tester.pumpAndSettle();

      expect(find.byType(SoundsOfHomeScreen), findsOneWidget);

      await tester.tap(find.byKey(const Key('sounds_back_button')));
      await tester.pumpAndSettle();

      expect(find.byType(SoundsOfHomeScreen), findsNothing);
      expect(find.text('Launch Sounds'), findsOneWidget);
    });
  });
}
