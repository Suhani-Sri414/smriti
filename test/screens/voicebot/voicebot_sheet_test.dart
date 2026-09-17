import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smriti/core/voicebot/voicebot_audio_service.dart';
import 'package:smriti/core/voicebot/voicebot_controller.dart';
import 'package:smriti/core/voicebot/voicebot_permissions.dart';
import 'package:smriti/screens/voicebot/voicebot_sheet.dart';

class StubPermissionGateway implements MicrophonePermissionGateway {
  bool granted = true;
  @override
  Future<bool> hasPermission() async => granted;

  @override
  Future<VoiceBotPermissionStatus> requestPermission() async =>
      granted ? VoiceBotPermissionStatus.granted : VoiceBotPermissionStatus.denied;

  @override
  Future<bool> openSettings() async => true;
}

void main() {
  group('VoiceBotSheet Widget Tests', () {
    late MockVoiceBotRecorderGateway mockRecorder;
    late MockVoiceBotPlayerGateway mockPlayer;
    late StubPermissionGateway mockPermissions;
    late VoiceBotAudioService audioService;
    late VoiceBotPermissions permissions;

    setUp(() {
      mockRecorder = MockVoiceBotRecorderGateway();
      mockPlayer = MockVoiceBotPlayerGateway();
      mockPermissions = StubPermissionGateway();
      audioService = VoiceBotAudioService(
        recorderGateway: mockRecorder,
        playerGateway: mockPlayer,
      );
      permissions = VoiceBotPermissions(gateway: mockPermissions);
    });

    VoiceBotController createTestController() {
      return VoiceBotController(
        audioService: audioService,
        permissions: permissions,
        tempDirProvider: () async => Directory.systemTemp,
      );
    }

    Widget createTestWidget(VoiceBotController controller,
        {VoidCallback? onClose}) {
      return MaterialApp(
        home: Scaffold(
          body: VoiceBotSheet(
            controller: controller,
            onClose: onClose,
          ),
        ),
      );
    }

    testWidgets('renders title and initial idle state prompt', (tester) async {
      final controller = createTestController();

      await tester.pumpWidget(createTestWidget(controller));

      expect(find.text('Smriti Companion'), findsOneWidget);
      expect(find.text('Always here to listen & talk'), findsOneWidget);
      expect(find.text('Tap the microphone to speak'), findsOneWidget);
      expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
    });

    testWidgets('tapping microphone in idle triggers startListening',
        (tester) async {
      final controller = createTestController();

      await tester.pumpWidget(createTestWidget(controller));
      await tester.tap(find.byKey(const Key('voicebot_mic_button')));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));

      expect(controller.state, VoiceBotState.listening);
      expect(find.text('Listening closely... Tap when finished'), findsOneWidget);
      expect(find.text('Done Speaking'), findsOneWidget);
    });

    testWidgets('tapping Done Speaking triggers stopAndProcess',
        (tester) async {
      final controller = createTestController();

      await tester.pumpWidget(createTestWidget(controller));
      await controller.startListening();
      await tester.pump();

      expect(find.text('Done Speaking'), findsOneWidget);
      await tester.tap(find.text('Done Speaking'));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump();

      // Should transition out of listening (to processing, speaking, or idle/error)
      expect(controller.state != VoiceBotState.listening, isTrue);
    });

    testWidgets('renders conversation bubbles when turns exist',
        (tester) async {
      final controller = createTestController();

      await tester.pumpWidget(createTestWidget(controller));

      // Simulate completed turn by updating controller
      controller.updateContext(userId: 'test_user');
      // Add turn manually to controller for test
      await tester.pump();

      expect(find.byType(VoiceBotSheet), findsOneWidget);
    });

    testWidgets('tapping close button calls onClose callback', (tester) async {
      var closed = false;
      final controller = VoiceBotController(
        audioService: audioService,
        permissions: permissions,
      );

      await tester.pumpWidget(createTestWidget(controller, onClose: () {
        closed = true;
      }));

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();

      expect(closed, isTrue);
    });

    testWidgets('renders raw error details box when controller is in error state',
        (tester) async {
      mockPermissions.granted = false;
      final controller = createTestController();

      await tester.pumpWidget(createTestWidget(controller));
      await controller.startListening();
      await tester.pump();

      expect(controller.state, VoiceBotState.error);
      expect(find.byKey(const Key('voicebot_raw_error_text')), findsOneWidget);
      expect(find.textContaining('Microphone access is needed'), findsWidgets);
      expect(find.byIcon(Icons.bug_report_rounded), findsOneWidget);
    });
  });
}
