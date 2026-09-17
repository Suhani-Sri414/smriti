import 'dart:io';
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
      addTearDown(() => tester.pumpWidget(const SizedBox()));
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
      addTearDown(() => tester.pumpWidget(const SizedBox()));
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

    testWidgets('displays actual uploaded photo when photo file exists for person',
        (tester) async {
      addTearDown(() => tester.pumpWidget(const SizedBox()));
      final tempDir = Directory.systemTemp.createTempSync('smriti_photo_test_');
      final testPhoto = File('${tempDir.path}/veer.png')
        ..writeAsBytesSync([
          137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82,
          0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137,
          0, 0, 0, 13, 73, 68, 65, 84, 120, 156, 99, 96, 0, 0, 0, 2,
          0, 1, 226, 33, 188, 51, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66,
          96, 130
        ]);

      try {
        await db.into(db.people).insert(
          PeopleCompanion.insert(
            id: 'p1',
            name: 'Veer',
            relationship: 'Son',
            photoPath: testPhoto.path,
            sortOrder: 0,
          ),
        );
        await db.into(db.people).insert(
          PeopleCompanion.insert(
            id: 'p2',
            name: 'Pooja',
            relationship: 'Daughter',
            photoPath: testPhoto.path,
            sortOrder: 1,
          ),
        );
        await db.into(db.people).insert(
          PeopleCompanion.insert(
            id: 'p3',
            name: 'Rahul',
            relationship: 'Grandson',
            photoPath: testPhoto.path,
            sortOrder: 2,
          ),
        );

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

        // One of the people is the target and has their photo rendered in the center
        expect(find.byType(Image), findsOneWidget);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    testWidgets('falls back to avatar initial when person genuinely has no photo',
        (tester) async {
      addTearDown(() => tester.pumpWidget(const SizedBox()));
      await db.into(db.people).insert(
        PeopleCompanion.insert(
          id: 'v1',
          name: 'Veer',
          relationship: 'Son',
          photoPath: '',
          sortOrder: 0,
        ),
      );
      await db.into(db.people).insert(
        PeopleCompanion.insert(
          id: 'v2',
          name: 'Varun',
          relationship: 'Brother',
          photoPath: '',
          sortOrder: 1,
        ),
      );
      await db.into(db.people).insert(
        PeopleCompanion.insert(
          id: 'v3',
          name: 'Vandana',
          relationship: 'Sister',
          photoPath: '',
          sortOrder: 2,
        ),
      );

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

      // No image rendered since no photos exist
      expect(find.byType(Image), findsNothing);
      // Person icon rendered on the central fallback avatar
      expect(find.byIcon(Icons.person_rounded), findsOneWidget);
      // Fallback initial "V" should be rendered (all candidate people start with V)
      expect(find.text('V'), findsOneWidget);
    });

    testWidgets(
        'preserves real database person even when database has fewer than 3 people',
        (tester) async {
      addTearDown(() => tester.pumpWidget(const SizedBox()));
      // Add only 1 person in the DB
      await db.into(db.people).insert(
        PeopleCompanion.insert(
          id: 'single_person',
          name: 'Veer',
          relationship: 'Grandson',
          photoPath: '',
          sortOrder: 0,
        ),
      );

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

      // Real person Veer is retained and playable, not dropped
      expect(find.text('Veer'), findsWidgets);
      // 3 choice options exist
      final choiceCards = find.byWidgetPredicate(
        (w) => w.key != null && w.key.toString().contains('face_option_'),
      );
      expect(choiceCards, findsNWidgets(3));
    });

    testWidgets('renders cleanly in portrait and landscape without overflow',
        (tester) async {
      addTearDown(() => tester.pumpWidget(const SizedBox()));
      final services = AppServices(database: db);
      const content = GameContent(version: '1', marketItems: []);

      // Test Landscape
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: FacesOfMyFamilyScreen(
            services: services,
            content: content,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Test Portrait
      tester.view.physicalSize = const Size(800, 1280);
      await tester.pumpWidget(
        MaterialApp(
          home: FacesOfMyFamilyScreen(
            services: services,
            content: content,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('answer options contain only text and no images or avatars',
        (tester) async {
      addTearDown(() => tester.pumpWidget(const SizedBox()));
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

      final choiceCards = find.byWidgetPredicate(
        (w) => w.key != null && w.key.toString().contains('face_option_'),
      );
      expect(choiceCards, findsNWidgets(3));

      // Verify that NO answer option has an Image or CircleAvatar inside it
      for (final card in choiceCards.evaluate()) {
        final cardFinder = find.byWidget(card.widget);
        expect(find.descendant(of: cardFinder, matching: find.byType(Image)),
            findsNothing);
        expect(
            find.descendant(of: cardFinder, matching: find.byType(CircleAvatar)),
            findsNothing);
      }
    });
  });
}
