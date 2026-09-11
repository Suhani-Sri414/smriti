import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smriti/core/ability/estimator.dart';
import 'package:smriti/core/app_services.dart';
import 'package:smriti/core/db/database.dart';
import 'package:smriti/games/cognitive_game.dart';
import 'package:smriti/games/faces_of_my_family/faces_of_my_family_game.dart';
import 'package:smriti/games/faces_of_my_family/faces_of_my_family_screen.dart';

import '../core/repo/_test_db.dart';

void main() {
  late SmritiDatabase db;

  setUp(() {
    db = newTestDb();
  });

  tearDown(() async {
    await db.close();
  });

  group('FacesOfMyFamilyGame Logic', () {
    test('game metadata conforms to CognitiveGame interface', () {
      final game = FacesOfMyFamilyGame();
      expect(game.id, 'faces_of_my_family');
      expect(game.primaryDomain, CognitiveDomain.memory);
      expect(game.introPhrase, PhraseKey.facesIntro);
      game.dispose();
    });

    test('generateItem generates 1 target and 2 distractors', () {
      final game = FacesOfMyFamilyGame(random: Random(42));
      const content = GameContent(version: '1', marketItems: []);

      final item = game.generateItem(0.5, content);
      expect(item.id, isNotEmpty);
      expect(item.payload['target'], isA<FamilyPerson>());

      final options =
          (item.payload['options'] as List<Object?>).cast<FamilyPerson>();
      expect(options.length, 3);

      final target = item.payload['target'] as FamilyPerson;
      expect(options.map((o) => o.id), contains(target.id));

      game.dispose();
    });

    test('submitChoice emits correct TrialResult when answer matches', () async {
      final game = FacesOfMyFamilyGame(random: Random(42));
      const content = GameContent(version: '1', marketItems: []);
      final item = game.generateItem(0.0, content);
      final target = item.payload['target'] as FamilyPerson;

      final expectation = expectLater(
        game.trials,
        emits(
          predicate<TrialResult>((result) {
            return result.correct == true &&
                result.chosenId == null &&
                result.errorClass == null &&
                result.initiationMs == 1200 &&
                result.movementMs == 400;
          }),
        ),
      );

      game.submitChoice(
        item: item,
        chosenId: target.id,
        initiationMs: 1200,
        movementMs: 400,
      );

      await expectation;
      game.dispose();
    });

    test('submitChoice classifies error as semantic when same generation or gender',
        () async {
      final people = [
        const FamilyPerson(
          id: 'p1',
          name: 'Person 1',
          relationship: 'Daughter',
          generation: 1,
          gender: 'female',
        ),
        const FamilyPerson(
          id: 'p2',
          name: 'Person 2',
          relationship: 'Son',
          generation: 1, // same generation
          gender: 'male',
        ),
        const FamilyPerson(
          id: 'p3',
          name: 'Person 3',
          relationship: 'Grandmother',
          generation: -1,
          gender: 'female', // same gender
        ),
      ];

      final game = FacesOfMyFamilyGame(people: people, random: Random(1));
      const content = GameContent(version: '1', marketItems: []);
      final item = game.generateItem(0.0, content);
      final target = item.payload['target'] as FamilyPerson;

      final distractor = people.firstWhere((p) => p.id != target.id);

      final expectation = expectLater(
        game.trials,
        emits(
          predicate<TrialResult>((result) {
            return result.correct == false &&
                result.chosenId == distractor.id &&
                result.errorClass == 'semantic';
          }),
        ),
      );

      game.submitChoice(
        item: item,
        chosenId: distractor.id,
        initiationMs: 900,
        movementMs: 300,
      );

      await expectation;
      game.dispose();
    });
  });

  group('FacesOfMyFamilyScreen Widget', () {
    testWidgets('renders game UI, avatar, prompt, and allows selecting choice',
        (tester) async {
      final services = AppServices(database: db);
      const content = GameContent(version: '1', marketItems: []);

      await tester.pumpWidget(
        MaterialApp(
          home: FacesOfMyFamilyScreen(
            services: services,
            content: content,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Faces of My Family'), findsOneWidget);
      expect(find.text('Who is this?'), findsOneWidget);
      expect(find.byKey(const Key('faces_back_button')), findsOneWidget);
      expect(find.byKey(const Key('faces_hint_button')), findsOneWidget);

      // Verify choice cards exist
      final choiceCards = find.byWidgetPredicate(
        (w) => w.key != null && w.key.toString().contains('face_option_'),
      );
      expect(choiceCards, findsNWidgets(3));

      // Tap hint button
      await tester.tap(find.byKey(const Key('faces_hint_button')));
      await tester.pump();

      // Tap one of the choices
      await tester.tap(choiceCards.first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1500));

      // Verify no crash and message updated
      expect(find.byType(FacesOfMyFamilyScreen), findsOneWidget);
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
                  builder: (_) => FacesOfMyFamilyScreen(
                    services: services,
                    content: content,
                  ),
                ),
              ),
              child: const Text('Launch'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Launch'));
      await tester.pumpAndSettle();

      expect(find.byType(FacesOfMyFamilyScreen), findsOneWidget);

      await tester.tap(find.byKey(const Key('faces_back_button')));
      await tester.pumpAndSettle();

      expect(find.byType(FacesOfMyFamilyScreen), findsNothing);
      expect(find.text('Launch'), findsOneWidget);
    });
  });
}
