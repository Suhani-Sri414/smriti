import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smriti/core/voicebot/voicebot_audio_service.dart';
import 'package:smriti/core/voicebot/voicebot_client.dart';
import 'package:smriti/core/voicebot/voicebot_controller.dart';
import 'package:smriti/core/voicebot/voicebot_permissions.dart';

class MockPermissionGateway implements MicrophonePermissionGateway {
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
  group('VoiceBotController', () {
    late MockVoiceBotRecorderGateway mockRecorder;
    late MockVoiceBotPlayerGateway mockPlayer;
    late MockPermissionGateway mockPermissionsGateway;
    late VoiceBotAudioService audioService;
    late VoiceBotPermissions permissions;

    setUp(() {
      mockRecorder = MockVoiceBotRecorderGateway();
      mockPlayer = MockVoiceBotPlayerGateway();
      mockPermissionsGateway = MockPermissionGateway();
      audioService = VoiceBotAudioService(
        recorderGateway: mockRecorder,
        playerGateway: mockPlayer,
      );
      permissions = VoiceBotPermissions(gateway: mockPermissionsGateway);
    });

    test('initial state is idle and turns list is empty', () {
      final controller = VoiceBotController(
        audioService: audioService,
        permissions: permissions,
      );
      expect(controller.state, VoiceBotState.idle);
      expect(controller.isIdle, isTrue);
      expect(controller.turns, isEmpty);
    });

    test('startListening transitions to listening when permission is granted',
        () async {
      final controller = VoiceBotController(
        audioService: audioService,
        permissions: permissions,
      );

      await controller.startListening();

      expect(controller.state, VoiceBotState.listening);
      expect(controller.isListening, isTrue);
      expect(mockRecorder.isRecording, isTrue);
    });

    test('amplitude updates when recorder emits amplitude', () async {
      final controller = VoiceBotController(
        audioService: audioService,
        permissions: permissions,
      );

      await controller.startListening();
      mockRecorder.emitAmplitude(0.75);
      await Future<void>.delayed(Duration.zero);

      expect(controller.amplitude, 0.75);
    });

    test('startListening transitions to error if permission is denied',
        () async {
      mockPermissionsGateway.granted = false;
      final controller = VoiceBotController(
        audioService: audioService,
        permissions: permissions,
      );

      await controller.startListening();

      expect(controller.state, VoiceBotState.error);
      expect(controller.isError, isTrue);
      expect(controller.errorMessage, contains('Microphone access is needed'));
      expect(mockRecorder.isRecording, isFalse);
    });

    test('stopAndProcess uploads WAV and transitions through processing to idle',
        () async {
      final mockHttp = MockClient((request) async {
        if (request.url.path.contains('/conversation/voice')) {
          final jsonResp = {
            'request_id': 'req-voice-1',
            'session_id': 'sess-voice-1',
            'response_text': 'I hear you loud and clear!',
            'transcript': 'Testing voicebot',
            'language': 'en',
            'job_id': 'job-tts-1',
          };
          return http.Response(jsonEncode(jsonResp), 200);
        } else if (request.url.path.contains('/voice/jobs/job-tts-1')) {
          final jsonResp = {
            'job_id': 'job-tts-1',
            'status': 'completed',
            'language': 'en',
            'audio_id': 'aud-tts-1',
          };
          return http.Response(jsonEncode(jsonResp), 200);
        } else if (request.url.path.contains('/audio/aud-tts-1')) {
          return http.Response.bytes([1, 2, 3, 4], 200);
        }
        return http.Response('Not found', 404);
      });

      final client = VoiceBotClient(
        baseUrl: 'https://mock-voicebot.local',
        apiPrefix: '/v1',
        apiKey: 'key',
        httpClient: mockHttp,
      );

      final controller = VoiceBotController(
        client: client,
        audioService: audioService,
        permissions: permissions,
      );

      await controller.startListening();
      expect(controller.state, VoiceBotState.listening);

      await controller.stopAndProcess();

      expect(controller.state, VoiceBotState.idle);
      expect(controller.currentTranscript, 'Testing voicebot');
      expect(controller.currentResponseText, 'I hear you loud and clear!');
      expect(controller.turns.length, 1);
      expect(controller.turns.first.botResponse, 'I hear you loud and clear!');
      expect(mockPlayer.playedByteLists.length, 1);
    });

    test('cancel resets controller back to idle', () async {
      final controller = VoiceBotController(
        audioService: audioService,
        permissions: permissions,
      );

      await controller.startListening();
      expect(controller.state, VoiceBotState.listening);

      await controller.cancel();
      expect(controller.state, VoiceBotState.idle);
      expect(mockRecorder.isRecording, isFalse);
    });

    test('stopAndProcess exposes raw error details on HTTP 401 auth failure',
        () async {
      final mockHttp = MockClient((request) async {
        return http.Response(jsonEncode({'detail': 'Invalid API key'}), 401);
      });

      final client = VoiceBotClient(
        baseUrl: 'https://mock-voicebot.local',
        httpClient: mockHttp,
      );

      final controller = VoiceBotController(
        client: client,
        audioService: audioService,
        permissions: permissions,
      );

      await controller.startListening();
      await controller.stopAndProcess();

      expect(controller.state, VoiceBotState.error);
      expect(controller.rawErrorDetails, contains('HTTP 401: {"detail":"Invalid API key"}'));
      expect(controller.errorMessage, contains('HTTP 401: {"detail":"Invalid API key"}'));
    });

    test('stopAndProcess auto-provisions on HTTP 403 unauthorized and succeeds on retry',
        () async {
      var callCount = 0;
      var memorySyncCalled = false;

      final mockHttp = MockClient((request) async {
        if (request.url.path.contains('/memory/sync')) {
          memorySyncCalled = true;
          return http.Response(jsonEncode({'success': true, 'status': 'applied'}), 200);
        } else if (request.url.path.contains('/conversation/voice')) {
          callCount++;
          if (callCount == 1) {
            return http.Response(
              jsonEncode({'detail': 'user_id is not authorized for this API credential'}),
              403,
            );
          }
          final jsonResp = {
            'request_id': 'req-retry-ok',
            'session_id': 'sess-retry-ok',
            'response_text': 'Welcome after provisioning!',
            'transcript': 'Hello',
            'language': 'en',
          };
          return http.Response(jsonEncode(jsonResp), 200);
        }
        return http.Response('Not found', 404);
      });

      final client = VoiceBotClient(
        baseUrl: 'https://mock-voicebot.local',
        httpClient: mockHttp,
      );

      final controller = VoiceBotController(
        client: client,
        audioService: audioService,
        permissions: permissions,
      );

      await controller.startListening();
      await controller.stopAndProcess();

      expect(memorySyncCalled, isTrue);
      expect(controller.state, VoiceBotState.idle);
      expect(controller.currentResponseText, 'Welcome after provisioning!');
      expect(controller.errorMessage, isNull);
      expect(controller.rawErrorDetails, isNull);
    });

    test('stopAndProcess exposes raw error details on HTTP 422 validation failure',
        () async {
      final mockHttp = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'detail': [
              {'type': 'missing', 'loc': ['body', 'audio_wav'], 'msg': 'Field required'}
            ]
          }),
          422,
        );
      });

      final client = VoiceBotClient(
        baseUrl: 'https://mock-voicebot.local',
        httpClient: mockHttp,
      );

      final controller = VoiceBotController(
        client: client,
        audioService: audioService,
        permissions: permissions,
      );

      await controller.startListening();
      await controller.stopAndProcess();

      expect(controller.state, VoiceBotState.error);
      expect(controller.rawErrorDetails, contains('HTTP 422:'));
      expect(controller.rawErrorDetails, contains('audio_wav'));
    });

    test('stopAndProcess sets error when recorded audio bytes are empty without calling client',
        () async {
      var clientCalled = false;
      final mockHttp = MockClient((request) async {
        clientCalled = true;
        return http.Response('OK', 200);
      });

      final client = VoiceBotClient(
        baseUrl: 'https://mock-voicebot.local',
        httpClient: mockHttp,
      );

      final emptyRecorder = _EmptyRecorderGateway();

      final controller = VoiceBotController(
        client: client,
        audioService: VoiceBotAudioService(
          recorderGateway: emptyRecorder,
          playerGateway: mockPlayer,
        ),
        permissions: permissions,
      );

      await controller.startListening();
      await controller.stopAndProcess();

      expect(controller.state, VoiceBotState.error);
      expect(controller.errorMessage, 'Audio file saved empty');
      expect(clientCalled, isFalse);
    });
  });
}

class _EmptyRecorderGateway implements VoiceBotRecorderGateway {
  String? _path;
  bool _isRecording = false;

  @override
  bool get isRecording => _isRecording;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<void> start(String path) async {
    _path = path;
    _isRecording = true;
  }

  @override
  Future<String?> stop() async {
    _isRecording = false;
    if (_path != null) {
      final f = File(_path!);
      if (!f.parent.existsSync()) {
        f.parent.createSync(recursive: true);
      }
      f.writeAsBytesSync([]);
    }
    return _path;
  }

  @override
  Stream<double> get amplitudeStream => const Stream.empty();

  @override
  Future<void> dispose() async {}
}
