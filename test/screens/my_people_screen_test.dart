import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smriti/core/app_services.dart';
import 'package:smriti/core/db/database.dart';
import 'package:smriti/core/files/file_paths.dart';
import 'package:smriti/core/voice/voice_player.dart';
import 'package:smriti/core/voice/voice_recorder.dart';
import 'package:smriti/screens/my_people_screen.dart';

import '../core/repo/_test_db.dart';

class _RecordingPlayer implements VoicePlayer {
  final List<String> played = [];

  @override
  Future<void> play(String path) async {
    played.add(path);
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

void main() {
  late SmritiDatabase db;
  late _RecordingPlayer player;
  late StubVoiceRecorder recorder;
  late Directory tempDir;

  setUp(() async {
    db = newTestDb();
    player = _RecordingPlayer();
    recorder = StubVoiceRecorder();
    tempDir = await Directory.systemTemp.createTemp('smriti_people_test_');
    FilePaths.documentsDirectoryOverride = tempDir.path;
  });

  tearDown(() async {
    FilePaths.documentsDirectoryOverride = null;
    await db.close();
    try {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  Future<void> seedPeople(int count) async {
    final names = [
      'Bina',
      'Thoibi',
      'Tomba',
      'Memcha',
      'Ibotombi',
      'Sanahal',
      'Ningol',
      'Chaoba',
      'Leima',
    ];
    for (var i = 0; i < count; i++) {
      final name = i < names.length ? names[i] : 'Person $i';
      await db.into(db.people).insert(
            PeopleCompanion.insert(
              id: 'p-$i',
              name: name,
              relationship: 'Family',
              photoPath: '',
              sortOrder: i,
              voicePath: Value('people/voice/p-$i.m4a'),
            ),
          );
    }
  }

  Widget createSubject({required AppServices services}) {
    return MaterialApp(
      home: MyPeopleScreen(
        services: services,
        voicePlayer: player,
        voiceRecorder: recorder,
      ),
    );
  }

  testWidgets('shows empty state when no people in db', (tester) async {
    final services = AppServices(database: db);
    await tester.pumpWidget(createSubject(services: services));
    await tester.pumpAndSettle();

    expect(find.text('Your family'), findsOneWidget);
    expect(find.byKey(const Key('people_empty')), findsOneWidget);
    expect(find.byKey(const Key('people_home_button')), findsOneWidget);
  });

  testWidgets('renders all 9 family members without scrolling', (tester) async {
    await seedPeople(9);
    final services = AppServices(database: db);
    await tester.pumpWidget(createSubject(services: services));
    await tester.pumpAndSettle();

    expect(find.text('Your family'), findsOneWidget);
    expect(find.text('Bina'), findsOneWidget);
    expect(find.text('Thoibi'), findsOneWidget);
    expect(find.text('Tomba'), findsOneWidget);
    expect(find.text('Memcha'), findsOneWidget);
    expect(find.text('Ibotombi'), findsOneWidget);
    expect(find.text('Sanahal'), findsOneWidget);
    expect(find.text('Ningol'), findsOneWidget);
    expect(find.text('Chaoba'), findsOneWidget);
    expect(find.text('Leima'), findsOneWidget);

    expect(find.byKey(const Key('people_home_button')), findsOneWidget);
  });

  testWidgets('home button pops the screen', (tester) async {
    final services = AppServices(database: db);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => MyPeopleScreen(services: services),
              ),
            ),
            child: const Text('Open People'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open People'));
    await tester.pumpAndSettle();

    expect(find.byType(MyPeopleScreen), findsOneWidget);

    await tester.tap(find.byKey(const Key('people_home_button')));
    await tester.pumpAndSettle();

    expect(find.byType(MyPeopleScreen), findsNothing);
    expect(find.text('Open People'), findsOneWidget);
  });

  testWidgets('tapping a person opens detail dialog and plays voice',
      (tester) async {
    await seedPeople(1);
    final services = AppServices(database: db);
    await tester.pumpWidget(createSubject(services: services));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('person_card_p-0')));
    await tester.pumpAndSettle();

    expect(find.text("Hear Bina's message"), findsOneWidget);
    expect(find.text('Leave a message for Bina'), findsOneWidget);

    await tester.tap(find.byKey(const Key('play_person_voice')));
    await tester.pumpAndSettle();

    expect(player.played, contains('people/voice/p-0.m4a'));
  });

  testWidgets('recording a memo inserts a row into VoiceMemos table',
      (tester) async {
    await seedPeople(1);
    final services = AppServices(database: db);
    await tester.pumpWidget(createSubject(services: services));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('person_card_p-0')));
    await tester.pumpAndSettle();

    // Start recording
    await tester.tap(find.byKey(const Key('record_memo_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(recorder.isRecording, isTrue);
    expect(find.textContaining('Stop recording'), findsOneWidget);

    // Stop recording
    await tester.tap(find.byKey(const Key('record_memo_button')));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(recorder.isRecording, isFalse);

    // Verify row in VoiceMemos
    final memos = await db.select(db.voiceMemos).get();
    expect(memos, hasLength(1));
    expect(memos.single.contextTag, 'p-0');
    expect(memos.single.durationMs, greaterThan(0));
    expect(memos.single.uploaded, isFalse);
  });
}
