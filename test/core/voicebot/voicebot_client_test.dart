import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smriti/core/voicebot/voicebot_client.dart';
import 'package:smriti/core/voicebot/voicebot_models.dart';

void main() {
  group('VoiceBotClient', () {
    const testBaseUrl = 'https://mock-voicebot.local';
    const testPrefix = '/v1';
    const testApiKey = 'test_secret_key_123';

    test('sendVoiceTurn sends multipart request with required headers and fields',
        () async {
      final mockHttp = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.toString(),
            'https://mock-voicebot.local/v1/conversation/voice');
        expect(request.headers['x-api-key'], testApiKey);

        final jsonResp = {
          'request_id': 'req-1',
          'session_id': 'sess-100',
          'response_text': 'Nomoskar! How can I help you today?',
          'transcript': 'Hello companion',
          'language': 'as',
          'job_id': 'job-456',
          'job_status': 'QUEUED',
          'kind': 'CONVERSATION',
        };

        return http.Response(jsonEncode(jsonResp), 200, headers: {
          'content-type': 'application/json',
        });
      });

      final client = VoiceBotClient(
        baseUrl: testBaseUrl,
        apiPrefix: testPrefix,
        apiKey: testApiKey,
        httpClient: mockHttp,
      );

      final audioBytes = List<int>.generate(100, (i) => i % 256);
      final response = await client.sendVoiceTurn(
        audioWavBytes: audioBytes,
        userId: 'patient-42',
        sessionId: 'sess-100',
        language: 'as',
        speak: true,
      );

      expect(response.requestId, 'req-1');
      expect(response.sessionId, 'sess-100');
      expect(response.responseText, 'Nomoskar! How can I help you today?');
      expect(response.transcript, 'Hello companion');
      expect(response.language, 'as');
      expect(response.jobId, 'job-456');
      expect(response.hasTtsJob, isTrue);
    });

    test('getJobStatus parses asynchronous TTS status correctly', () async {
      final mockHttp = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.toString(),
            'https://mock-voicebot.local/v1/voice/jobs/job-123');
        expect(request.headers['x-api-key'], testApiKey);

        final jsonResp = {
          'job_id': 'job-123',
          'status': 'completed',
          'language': 'as',
          'audio_id': 'aud-999',
          'audio_url': 'https://mock-voicebot.local/v1/audio/aud-999',
        };
        return http.Response(jsonEncode(jsonResp), 200);
      });

      final client = VoiceBotClient(
        baseUrl: testBaseUrl,
        apiPrefix: testPrefix,
        apiKey: testApiKey,
        httpClient: mockHttp,
      );

      final status = await client.getJobStatus('job-123');
      expect(status.jobId, 'job-123');
      expect(status.status, 'completed');
      expect(status.isCompleted, isTrue);
      expect(status.audioId, 'aud-999');
    });

    test('pollJobUntilComplete loops until job completes', () async {
      var callCount = 0;
      final mockHttp = MockClient((request) async {
        callCount++;
        final statusString = callCount < 3 ? 'processing' : 'completed';
        final jsonResp = {
          'job_id': 'job-poll-1',
          'status': statusString,
          'language': 'as',
          'audio_id': callCount >= 3 ? 'aud-poll-done' : null,
        };
        return http.Response(jsonEncode(jsonResp), 200);
      });

      final client = VoiceBotClient(
        baseUrl: testBaseUrl,
        apiPrefix: testPrefix,
        apiKey: testApiKey,
        httpClient: mockHttp,
      );

      final status = await client.pollJobUntilComplete(
        'job-poll-1',
        pollInterval: const Duration(milliseconds: 10),
      );

      expect(status.isCompleted, isTrue);
      expect(status.audioId, 'aud-poll-done');
      expect(callCount, 3);
    });

    test('downloadAudio returns raw audio bytes', () async {
      final expectedBytes = [0x52, 0x49, 0x46, 0x46, 0x24, 0x00, 0x00];
      final mockHttp = MockClient((request) async {
        expect(request.url.toString(),
            'https://mock-voicebot.local/v1/audio/aud-555');
        return http.Response.bytes(expectedBytes, 200);
      });

      final client = VoiceBotClient(
        baseUrl: testBaseUrl,
        apiPrefix: testPrefix,
        apiKey: testApiKey,
        httpClient: mockHttp,
      );

      final downloaded = await client.downloadAudio('aud-555');
      expect(downloaded, expectedBytes);
    });

    test('sendWelcome posts proactive welcome greeting turn', () async {
      final mockHttp = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.toString(),
            'https://mock-voicebot.local/v1/conversation/welcome');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['user_id'], 'user-welcome-1');
        expect(body['speak'], isTrue);

        final jsonResp = {
          'request_id': 'req-welcome',
          'session_id': 'sess-welcome',
          'response_text': 'Good morning! How are you feeling today?',
          'language': 'en',
          'job_id': 'job-welcome-tts',
        };
        return http.Response(jsonEncode(jsonResp), 200);
      });

      final client = VoiceBotClient(
        baseUrl: testBaseUrl,
        apiPrefix: testPrefix,
        apiKey: testApiKey,
        httpClient: mockHttp,
      );

      final resp = await client.sendWelcome(
        userId: 'user-welcome-1',
        speak: true,
      );

      expect(resp.responseText, 'Good morning! How are you feeling today?');
      expect(resp.sessionId, 'sess-welcome');
      expect(resp.jobId, 'job-welcome-tts');
    });

    test('401 response throws VoiceBotAuthException', () async {
      final mockHttp = MockClient((request) async {
        return http.Response(jsonEncode({'detail': 'Invalid API key'}), 401);
      });

      final client = VoiceBotClient(
        baseUrl: testBaseUrl,
        apiPrefix: testPrefix,
        apiKey: testApiKey,
        httpClient: mockHttp,
      );

      expect(
        () => client.getJobStatus('job-bad-key'),
        throwsA(isA<VoiceBotAuthException>()),
      );
    });

    test('500 response throws VoiceBotApiException', () async {
      final mockHttp = MockClient((request) async {
        return http.Response(
            jsonEncode({'detail': 'Internal server error'}), 500);
      });

      final client = VoiceBotClient(
        baseUrl: testBaseUrl,
        apiPrefix: testPrefix,
        apiKey: testApiKey,
        httpClient: mockHttp,
      );

      expect(
        () => client.getJobStatus('job-crash'),
        throwsA(isA<VoiceBotApiException>()),
      );
    });

    test('syncMemory sends POST to /v1/memory/sync with payload and headers',
        () async {
      final mockHttp = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.toString(),
            'https://mock-voicebot.local/v1/memory/sync');
        expect(request.headers['x-api-key'], testApiKey);
        expect(request.headers['Content-Type'], 'application/json');

        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['user_id'], 'elder-uuid-1');
        expect(body['display_name'], 'Ibemhal Devi');

        final jsonResp = {
          'success': true,
          'user_id': 'elder-uuid-1',
          'status': 'applied',
        };
        return http.Response(jsonEncode(jsonResp), 200);
      });

      final client = VoiceBotClient(
        baseUrl: testBaseUrl,
        apiPrefix: testPrefix,
        apiKey: testApiKey,
        httpClient: mockHttp,
      );

      final result = await client.syncMemory(
        userId: 'elder-uuid-1',
        displayName: 'Ibemhal Devi',
      );

      expect(result['success'], isTrue);
      expect(result['status'], 'applied');
    });
  });
}
