import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'voicebot_models.dart';

/// HTTP client for communicating with the Smriti ML VoiceBot companion.
class VoiceBotClient {
  VoiceBotClient({
    String? baseUrl,
    String? apiPrefix,
    String? apiKey,
    http.Client? httpClient,
  })  : _customBaseUrl = baseUrl,
        _customApiPrefix = apiPrefix,
        _customApiKey = apiKey,
        _httpClient = httpClient ?? http.Client();

  final String? _customBaseUrl;
  final String? _customApiPrefix;
  final String? _customApiKey;
  final http.Client _httpClient;

  /// Resolves the base URL from custom value, dotenv, or default.
  String get baseUrl {
    final customUrl = _customBaseUrl;
    if (customUrl != null && customUrl.isNotEmpty) {
      return customUrl;
    }
    return dotenv.isInitialized
        ? (dotenv.env['VOICEBOT_BASE_URL'] ?? 'https://15-206-144-216.nip.io')
        : 'https://15-206-144-216.nip.io';
  }

  /// Resolves the API prefix from custom value, dotenv, or default.
  String get apiPrefix {
    final customPrefix = _customApiPrefix;
    if (customPrefix != null && customPrefix.isNotEmpty) {
      return customPrefix;
    }
    return dotenv.isInitialized
        ? (dotenv.env['VOICEBOT_API_PREFIX'] ?? '/v1')
        : '/v1';
  }

  /// Resolves the API key securely from custom value or dotenv.
  String get apiKey {
    final customKey = _customApiKey;
    if (customKey != null && customKey.isNotEmpty) {
      return customKey;
    }
    return dotenv.isInitialized
        ? (dotenv.env['VOICEBOT_API_KEY'] ??
            'oTyv1KYWuagG4jSyGfrtWnB-mCM_jFHza5zAZgsjGYg')
        : 'oTyv1KYWuagG4jSyGfrtWnB-mCM_jFHza5zAZgsjGYg';
  }

  Map<String, String> get _authHeaders => {
        'x-api-key': apiKey,
        'Accept': 'application/json',
      };

  Uri _buildUri(String path, [Map<String, dynamic>? queryParams]) {
    final cleanBase = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final cleanPrefix = apiPrefix.startsWith('/') ? apiPrefix : '/$apiPrefix';
    final cleanPath = path.startsWith('/') ? path : '/$path';
    final fullUrl = '$cleanBase$cleanPrefix$cleanPath';
    return Uri.parse(fullUrl).replace(queryParameters: queryParams);
  }

  /// Check server health.
  Future<bool> checkHealth() async {
    try {
      final uri = _buildUri('/health');
      debugPrint('[VoiceBotClient] checkHealth -> GET $uri');
      final res = await _httpClient.get(uri).timeout(const Duration(seconds: 5));
      debugPrint('[VoiceBotClient] checkHealth <- ${res.statusCode}');
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('[VoiceBotClient] checkHealth error: $e');
      return false;
    }
  }

  /// Sends one voice turn with WAV audio bytes (POST /v1/conversation/voice).
  Future<VoiceResponse> sendVoiceTurn({
    required List<int> audioWavBytes,
    required String userId,
    String? sessionId,
    String? language,
    bool speak = true,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final uri = _buildUri('/conversation/voice');
    try {
      final request = http.MultipartRequest('POST', uri);

      request.headers.addAll(_authHeaders);
      request.fields['user_id'] = userId;
      if (sessionId != null && sessionId.isNotEmpty) {
        request.fields['session_id'] = sessionId;
      }
      if (language != null && language.isNotEmpty) {
        request.fields['language'] = language;
      }
      request.fields['speak'] = speak.toString();

      request.files.add(
        http.MultipartFile.fromBytes(
          'audio_wav',
          audioWavBytes,
          filename: 'audio.wav',
          contentType: MediaType('audio', 'wav'),
        ),
      );

      debugPrint('[VoiceBotClient] >>> SENDING VOICE TURN:');
      debugPrint('  URI: $uri');
      debugPrint('  Headers: ${request.headers}');
      debugPrint('  Fields: ${request.fields}');
      debugPrint('  Audio WAV bytes: ${audioWavBytes.length}');

      final streamedRes = await _httpClient.send(request).timeout(timeout);
      final res = await http.Response.fromStream(streamedRes);

      debugPrint('[VoiceBotClient] <<< VOICE TURN RESPONSE:');
      debugPrint('  Status code: ${res.statusCode}');
      debugPrint('  Response headers: ${res.headers}');
      debugPrint('  Response body: ${res.body}');

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return VoiceResponse.fromJson(data);
      }

      _handleErrorResponse(res);
      throw VoiceBotApiException(
        statusCode: res.statusCode,
        message: 'Unknown error',
        body: res.body,
      );
    } on VoiceBotException catch (e) {
      debugPrint('[VoiceBotClient] !!! VoiceBotException in sendVoiceTurn: $e');
      rethrow;
    } on TimeoutException catch (e) {
      debugPrint('[VoiceBotClient] !!! TimeoutException in sendVoiceTurn: $e');
      throw const VoiceBotTimeoutException(
        'Voice request timed out. Please check your network.',
      );
    } catch (e, st) {
      debugPrint('[VoiceBotClient] !!! Network/Unexpected error in sendVoiceTurn to $uri: $e\n$st');
      throw VoiceBotNetworkException('Failed to communicate with voice server', e);
    }
  }

  /// Proactive welcome turn (POST /v1/conversation/welcome).
  Future<WelcomeResponse> sendWelcome({
    required String userId,
    String? sessionId,
    String? language,
    bool speak = false,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final uri = _buildUri('/conversation/welcome');
    try {
      final body = jsonEncode({
        'user_id': userId,
        if (sessionId != null && sessionId.isNotEmpty) 'session_id': sessionId,
        if (language != null && language.isNotEmpty) 'language': language,
        'speak': speak,
      });

      debugPrint('[VoiceBotClient] >>> SENDING WELCOME:');
      debugPrint('  URI: $uri');
      debugPrint('  Headers: $_authHeaders');
      debugPrint('  Body: $body');

      final res = await _httpClient
          .post(
            uri,
            headers: {
              ..._authHeaders,
              'Content-Type': 'application/json',
            },
            body: body,
          )
          .timeout(timeout);

      debugPrint('[VoiceBotClient] <<< WELCOME RESPONSE:');
      debugPrint('  Status code: ${res.statusCode}');
      debugPrint('  Response body: ${res.body}');

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return WelcomeResponse.fromJson(data);
      }

      _handleErrorResponse(res);
      throw VoiceBotApiException(
        statusCode: res.statusCode,
        message: 'Welcome request failed',
        body: res.body,
      );
    } on VoiceBotException catch (e) {
      debugPrint('[VoiceBotClient] !!! VoiceBotException in sendWelcome: $e');
      rethrow;
    } on TimeoutException catch (e) {
      debugPrint('[VoiceBotClient] !!! TimeoutException in sendWelcome: $e');
      throw const VoiceBotTimeoutException('Welcome request timed out');
    } catch (e, st) {
      debugPrint('[VoiceBotClient] !!! Network/Unexpected error in sendWelcome to $uri: $e\n$st');
      throw VoiceBotNetworkException('Failed to send welcome request', e);
    }
  }

  /// Fetches the status of an asynchronous TTS synthesis job (GET /v1/voice/jobs/{job_id}).
  Future<VoiceJobStatus> getJobStatus(
    String jobId, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final uri = _buildUri('/voice/jobs/$jobId');
    try {
      debugPrint('[VoiceBotClient] >>> GET JOB STATUS: $uri');
      final res = await _httpClient
          .get(uri, headers: _authHeaders)
          .timeout(timeout);

      debugPrint('[VoiceBotClient] <<< JOB STATUS RESPONSE:');
      debugPrint('  Status code: ${res.statusCode}');
      debugPrint('  Response body: ${res.body}');

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return VoiceJobStatus.fromJson(data);
      }

      _handleErrorResponse(res);
      throw VoiceBotApiException(
        statusCode: res.statusCode,
        message: 'Failed to get job status',
        body: res.body,
      );
    } on VoiceBotException catch (e) {
      debugPrint('[VoiceBotClient] !!! VoiceBotException in getJobStatus: $e');
      rethrow;
    } on TimeoutException catch (e) {
      debugPrint('[VoiceBotClient] !!! TimeoutException in getJobStatus: $e');
      throw const VoiceBotTimeoutException('Job status request timed out');
    } catch (e, st) {
      debugPrint('[VoiceBotClient] !!! Network/Unexpected error in getJobStatus for $uri: $e\n$st');
      throw VoiceBotNetworkException('Failed to fetch job status', e);
    }
  }

  /// Polls a TTS job until it completes or reaches a terminal state.
  Future<VoiceJobStatus> pollJobUntilComplete(
    String jobId, {
    Duration timeout = const Duration(seconds: 25),
    Duration pollInterval = const Duration(milliseconds: 600),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final status = await getJobStatus(jobId);
      if (status.isCompleted || status.isFailed || status.isCancelled) {
        return status;
      }
      await Future.delayed(pollInterval);
    }
    throw VoiceBotTimeoutException(
      'TTS synthesis job ($jobId) timed out after ${timeout.inSeconds}s',
    );
  }

  /// Downloads synthesized audio bytes (GET /v1/audio/{audio_id}).
  Future<List<int>> downloadAudio(
    String audioId, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final uri = _buildUri('/audio/$audioId');
    try {
      debugPrint('[VoiceBotClient] >>> DOWNLOADING AUDIO: $uri');
      final res = await _httpClient
          .get(
            uri,
            headers: {
              'x-api-key': apiKey,
              'Accept': '*/*',
            },
          )
          .timeout(timeout);

      debugPrint('[VoiceBotClient] <<< DOWNLOAD AUDIO RESPONSE:');
      debugPrint('  Status code: ${res.statusCode}');
      debugPrint('  Audio bytes length: ${res.bodyBytes.length}');

      if (res.statusCode == 200) {
        return res.bodyBytes;
      }

      _handleErrorResponse(res);
      throw VoiceBotApiException(
        statusCode: res.statusCode,
        message: 'Failed to download audio',
        body: res.body,
      );
    } on VoiceBotException catch (e) {
      debugPrint('[VoiceBotClient] !!! VoiceBotException in downloadAudio: $e');
      rethrow;
    } on TimeoutException catch (e) {
      debugPrint('[VoiceBotClient] !!! TimeoutException in downloadAudio: $e');
      throw const VoiceBotTimeoutException('Audio download timed out');
    } catch (e, st) {
      debugPrint('[VoiceBotClient] !!! Network/Unexpected error in downloadAudio from $uri: $e\n$st');
      throw VoiceBotNetworkException('Failed to download synthesized audio', e);
    }
  }

  /// Text turn fallback (POST /v1/conversation).
  Future<VoiceResponse> sendTextTurn({
    required String text,
    required String userId,
    String? sessionId,
    String? language,
    bool speak = false,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final uri = _buildUri('/conversation');
    try {
      final body = jsonEncode({
        'message': text,
        'user_id': userId,
        if (sessionId != null && sessionId.isNotEmpty) 'session_id': sessionId,
        if (language != null && language.isNotEmpty) 'language': language,
        'speak': speak,
      });

      debugPrint('[VoiceBotClient] >>> SENDING TEXT TURN:');
      debugPrint('  URI: $uri');
      debugPrint('  Headers: $_authHeaders');
      debugPrint('  Body: $body');

      final res = await _httpClient
          .post(
            uri,
            headers: {
              ..._authHeaders,
              'Content-Type': 'application/json',
            },
            body: body,
          )
          .timeout(timeout);

      debugPrint('[VoiceBotClient] <<< TEXT TURN RESPONSE:');
      debugPrint('  Status code: ${res.statusCode}');
      debugPrint('  Response body: ${res.body}');

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return VoiceResponse.fromJson(data);
      }

      _handleErrorResponse(res);
      throw VoiceBotApiException(
        statusCode: res.statusCode,
        message: 'Text turn failed',
        body: res.body,
      );
    } on VoiceBotException catch (e) {
      debugPrint('[VoiceBotClient] !!! VoiceBotException in sendTextTurn: $e');
      rethrow;
    } on TimeoutException catch (e) {
      debugPrint('[VoiceBotClient] !!! TimeoutException in sendTextTurn: $e');
      throw const VoiceBotTimeoutException('Text conversation request timed out');
    } catch (e, st) {
      debugPrint('[VoiceBotClient] !!! Network/Unexpected error in sendTextTurn to $uri: $e\n$st');
      throw VoiceBotNetworkException('Failed to send text turn', e);
    }
  }

  /// Syncs patient memory and provisions the user ID (POST /v1/memory/sync).
  Future<Map<String, dynamic>> syncMemory({
    required String userId,
    String? displayName,
    List<Map<String, dynamic>> familyMembers = const [],
    List<Map<String, dynamic>> medicines = const [],
    List<Map<String, dynamic>> dailyRoutines = const [],
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final uri = _buildUri('/memory/sync');
    try {
      final body = jsonEncode({
        'user_id': userId,
        if (displayName != null && displayName.isNotEmpty)
          'display_name': displayName,
        'family_members': familyMembers,
        'medicines': medicines,
        'daily_routines': dailyRoutines,
      });

      debugPrint('[VoiceBotClient] >>> SYNCING MEMORY:');
      debugPrint('  URI: $uri');
      debugPrint('  Headers: $_authHeaders');
      debugPrint('  Body: $body');

      final res = await _httpClient
          .post(
            uri,
            headers: {
              ..._authHeaders,
              'Content-Type': 'application/json',
            },
            body: body,
          )
          .timeout(timeout);

      debugPrint('[VoiceBotClient] <<< SYNC MEMORY RESPONSE:');
      debugPrint('  Status code: ${res.statusCode}');
      debugPrint('  Response body: ${res.body}');

      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }

      _handleErrorResponse(res);
      throw VoiceBotApiException(
        statusCode: res.statusCode,
        message: 'Memory sync failed',
        body: res.body,
      );
    } on VoiceBotException catch (e) {
      debugPrint('[VoiceBotClient] !!! VoiceBotException in syncMemory: $e');
      rethrow;
    } on TimeoutException catch (e) {
      debugPrint('[VoiceBotClient] !!! TimeoutException in syncMemory: $e');
      throw const VoiceBotTimeoutException('Memory sync request timed out');
    } catch (e, st) {
      debugPrint('[VoiceBotClient] !!! Network/Unexpected error in syncMemory to $uri: $e\n$st');
      throw VoiceBotNetworkException('Failed to sync memory', e);
    }
  }

  void _handleErrorResponse(http.Response res) {
    debugPrint('[VoiceBotClient] _handleErrorResponse: status=${res.statusCode}, body=${res.body}');
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw VoiceBotAuthException(
        statusCode: res.statusCode,
        message: 'Authentication failed: check x-api-key or user permissions (status: ${res.statusCode}, body: ${res.body})',
        body: res.body,
      );
    }
    throw VoiceBotApiException(
      statusCode: res.statusCode,
      message: 'Server error (${res.statusCode}): ${res.body}',
      body: res.body,
    );
  }

  void dispose() {
    _httpClient.close();
  }
}
