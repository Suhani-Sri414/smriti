import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smriti/core/app_services.dart';
import 'package:smriti/core/db/database.dart';
import 'package:smriti/core/reminders/alarm_scheduler.dart';
import 'package:smriti/core/reminders/notifications.dart';
import 'package:smriti/core/repo/content_repo.dart';
import 'package:smriti/core/voice/voice_commander.dart';
import 'package:smriti/screens/games_menu_screen.dart';
import 'package:smriti/screens/home_screen.dart';
import 'package:smriti/screens/voice_interaction_overlay.dart';

import '../core/reminders/_fake_alarm_api.dart';
import '../core/repo/_test_db.dart';

void main() {
  group('VoiceCommander string parser', () {
    test('parses play keywords', () {
      expect(VoiceCommander.parseText('play'), VoiceCommand.play);
      expect(VoiceCommander.parseText('Play a game'), VoiceCommand.play);
      expect(VoiceCommander.parseText('khel'), VoiceCommand.play);
      expect(VoiceCommander.parseText('market basket'), VoiceCommand.play);
    });

    test('parses today and medication keywords', () {
      expect(VoiceCommander.parseText('today'), VoiceCommand.today);
      expect(VoiceCommander.parseText('show schedule'), VoiceCommand.today);
      expect(VoiceCommander.parseText('medicine time'), VoiceCommand.today);
      expect(VoiceCommander.parseText('dawai'), VoiceCommand.today);
    });

    test('parses family and people keywords', () {
      expect(VoiceCommander.parseText('my people'), VoiceCommand.people);
      expect(VoiceCommander.parseText('family photos'), VoiceCommand.people);
      expect(VoiceCommander.parseText('parivar'), VoiceCommand.people);
    });

    test('parses call keywords', () {
      expect(VoiceCommander.parseText('call'), VoiceCommand.call);
      expect(VoiceCommander.parseText('call bina'), VoiceCommand.call);
      expect(VoiceCommander.parseText('phone'), VoiceCommand.call);
    });

    test('returns null on empty or unrecognized speech', () {
      expect(VoiceCommander.parseText(''), isNull);
      expect(VoiceCommander.parseText('   '), isNull);
      expect(VoiceCommander.parseText('xyz unknown phrase'), isNull);
    });
  });

  group('Screen 15: VoiceInteractionOverlay (Listening)', () {
    testWidgets('renders listening prompt, concentric ripples, and mic button',
        (tester) async {
      var dismissed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                const Text('Home Content Underneath'),
                VoiceInteractionOverlay(
                  state: MicOverlayState.listening,
                  contactName: 'Bina',
                  onDismiss: () => dismissed = true,
                  onCommand: (_) {},
                  onRetry: () {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      // Home content sits underneath
      expect(find.text('Home Content Underneath'), findsOneWidget);

      // Listening badge and subtitle are visible
      expect(find.byKey(const Key('voice_listening_title')), findsOneWidget);
      expect(find.text('Listening...'), findsOneWidget);
      expect(
        find.text('Say: Play, Today, My People, or Call'),
        findsOneWidget,
      );

      // Concentric ripple painter is rendered
      expect(find.byType(CustomPaint), findsWidgets);

      // Bottom highlighted mic button
      expect(
        find.byKey(const Key('voice_listening_mic_button')),
        findsOneWidget,
      );

      // Tapping close dismisses
      await tester.tap(find.byKey(const Key('voice_overlay_close')));
      expect(dismissed, isTrue);

      // Tapping scrim dismisses
      dismissed = false;
      await tester.tap(find.byKey(const Key('voice_scrim_dismiss')));
      expect(dismissed, isTrue);
    });
  });

  group('Screen 16: VoiceInteractionOverlay (No Match)', () {
    testWidgets('renders friendly prompt, 4 action tiles, and retry button',
        (tester) async {
      var dismissed = false;
      VoiceCommand? selectedCommand;
      var retried = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                const Text('Home Content Underneath'),
                VoiceInteractionOverlay(
                  state: MicOverlayState.noMatch,
                  contactName: 'Bina',
                  onDismiss: () => dismissed = true,
                  onCommand: (cmd) => selectedCommand = cmd,
                  onRetry: () => retried = true,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Friendly zero-shame title
      expect(find.byKey(const Key('voice_no_match_title')), findsOneWidget);
      expect(find.text("I didn't catch that"), findsOneWidget);
      expect(
        find.text('Tap where you would like to go, or try speaking again:'),
        findsOneWidget,
      );

      // All 4 action tiles are present
      expect(find.byKey(const Key('voice_action_play')), findsOneWidget);
      expect(find.byKey(const Key('voice_action_today')), findsOneWidget);
      expect(find.byKey(const Key('voice_action_people')), findsOneWidget);
      expect(find.byKey(const Key('voice_action_call')), findsOneWidget);

      expect(find.text('Play Games'), findsOneWidget);
      expect(find.text('See Today'), findsOneWidget);
      expect(find.text('My People'), findsOneWidget);
      expect(find.text('Call Bina'), findsOneWidget);

      // Tapping Play Games emits VoiceCommand.play
      await tester.tap(find.byKey(const Key('voice_action_play')));
      expect(selectedCommand, VoiceCommand.play);

      // Tapping See Today emits VoiceCommand.today
      await tester.tap(find.byKey(const Key('voice_action_today')));
      expect(selectedCommand, VoiceCommand.today);

      // Tapping My People emits VoiceCommand.people
      await tester.tap(find.byKey(const Key('voice_action_people')));
      expect(selectedCommand, VoiceCommand.people);

      // Tapping Call emits VoiceCommand.call
      await tester.tap(find.byKey(const Key('voice_action_call')));
      expect(selectedCommand, VoiceCommand.call);

      // Tapping "Try speaking again" invokes onRetry
      await tester.tap(find.byKey(const Key('voice_try_again')));
      expect(retried, isTrue);

      // Tapping "Back to Home" invokes onDismiss
      await tester.tap(find.byKey(const Key('voice_no_match_close')));
      expect(dismissed, isTrue);
    });

    testWidgets('zero-shame: no error, failed, warning or red states',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VoiceInteractionOverlay(
              state: MicOverlayState.noMatch,
              contactName: 'Bina',
              onDismiss: () {},
              onCommand: (_) {},
              onRetry: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Error'), findsNothing);
      expect(find.textContaining('Failed'), findsNothing);
      expect(find.textContaining('Warning'), findsNothing);
      expect(find.textContaining('Wrong'), findsNothing);
      expect(find.textContaining('Invalid'), findsNothing);
    });
  });

  group('HomeScreen Voice Interaction Integration', () {
    late SmritiDatabase db;
    late FakeVoiceCommander fakeCommander;
    late AppServices services;

    setUp(() async {
      db = newTestDb();
      fakeCommander = FakeVoiceCommander();
      services = AppServices(
        database: db,
        alarmScheduler: AlarmScheduler(
          contentRepo: ContentRepo(db),
          alarmApi: FakeAlarmApi(),
        ),
        notifier: NoopReminderNotifier(),
      );

      await db.appConfigsDao.setValue('elderName', 'Ibemhal');
      await db.appConfigsDao.setValue('primaryContactName', 'Bina');
    });

    tearDown(() async {
      await db.close();
    });

    testWidgets('tapping mic button on Home opens listening overlay',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            services: services,
            voiceCommander: fakeCommander,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Home starts with overlay idle
      expect(find.byKey(const Key('voice_listening_title')), findsNothing);

      // Tap bottom microphone button
      await tester.tap(find.byKey(const Key('home_mic_button')));
      await tester.pump();

      // Listening overlay is active
      expect(fakeCommander.isListening, isTrue);
      expect(find.byKey(const Key('voice_listening_title')), findsOneWidget);
      expect(find.text('Listening...'), findsOneWidget);
    });

    testWidgets('speaking "play" while listening navigates to GamesMenuScreen',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            services: services,
            voiceCommander: fakeCommander,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open mic
      await tester.tap(find.byKey(const Key('home_mic_button')));
      await tester.pump();

      // Simulate elder saying "play"
      fakeCommander.simulateSpeech('play');
      await tester.pumpAndSettle();

      // Overlay dismissed and GamesMenuScreen opened
      expect(find.byType(GamesMenuScreen), findsOneWidget);
      expect(find.text('Games'), findsOneWidget);
    });

    testWidgets('silence timeout transitions to Screen 16 "I didn\'t catch that"',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            services: services,
            voiceCommander: fakeCommander,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open mic
      await tester.tap(find.byKey(const Key('home_mic_button')));
      await tester.pump();

      // Simulate silence timeout
      fakeCommander.simulateTimeout();
      await tester.pumpAndSettle();

      // Transitioned to Screen 16
      expect(find.byKey(const Key('voice_no_match_title')), findsOneWidget);
      expect(find.text("I didn't catch that"), findsOneWidget);

      // Tapping "Play Games" from no match navigates to GamesMenuScreen
      await tester.tap(find.byKey(const Key('voice_action_play')));
      await tester.pumpAndSettle();

      expect(find.byType(GamesMenuScreen), findsOneWidget);
    });
  });
}
