import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'voicebot_audio_service.dart';
import 'voicebot_client.dart';
import 'voicebot_models.dart';
import 'voicebot_permissions.dart';

/// The 5 core states of the VoiceBot companion lifecycle.
enum VoiceBotState {
  idle,
  listening,
  processing,
  speaking,
  error,
}

/// A recorded conversation turn for UI display.
class VoiceBotTurn {
  const VoiceBotTurn({
    required this.userTranscript,
    required this.botResponse,
    required this.timestamp,
  });

  final String userTranscript;
  final String botResponse;
  final DateTime timestamp;
}

/// State controller managing two-way VoiceBot interaction, lifecycle, and audio.
class VoiceBotController extends ChangeNotifier {
  VoiceBotController({
    VoiceBotClient? client,
    VoiceBotAudioService? audioService,
    VoiceBotPermissions? permissions,
    Future<Directory> Function()? tempDirProvider,
    String? userId,
    String? language,
  })  : _client = client ?? VoiceBotClient(),
        _audioService = audioService ?? VoiceBotAudioService(),
        _permissions = permissions ?? VoiceBotPermissions(),
        _tempDirProvider = tempDirProvider ?? _defaultTempDirectory,
        _userId = userId ?? 'smriti_patient',
        _language = language;

  final VoiceBotClient _client;
  final VoiceBotAudioService _audioService;
  final VoiceBotPermissions _permissions;
  final Future<Directory> Function() _tempDirProvider;

  static Future<Directory> _defaultTempDirectory() async {
    try {
      return await getTemporaryDirectory();
    } catch (_) {
      return Directory.systemTemp;
    }
  }

  String _userId;
  String? _language;
  String? _sessionId;

  VoiceBotState _state = VoiceBotState.idle;
  String _currentTranscript = '';
  String _currentResponseText = '';
  String? _errorMessage;
  String? _rawErrorDetails;
  double _amplitude = 0.0;
  String? _lastRecordedWavPath;

  StreamSubscription<double>? _ampSub;
  final List<VoiceBotTurn> _turns = [];

  // Getters
  VoiceBotState get state => _state;
  String get userId => _userId;
  String? get language => _language;
  String? get sessionId => _sessionId;
  String get currentTranscript => _currentTranscript;
  String get currentResponseText => _currentResponseText;
  String? get errorMessage => _errorMessage;
  String? get rawErrorDetails => _rawErrorDetails;
  double get amplitude => _amplitude;
  List<VoiceBotTurn> get turns => List.unmodifiable(_turns);

  bool get isIdle => _state == VoiceBotState.idle;
  bool get isListening => _state == VoiceBotState.listening;
  bool get isProcessing => _state == VoiceBotState.processing;
  bool get isSpeaking => _state == VoiceBotState.speaking;
  bool get isError => _state == VoiceBotState.error;

  String _formatError(Object e) {
    if (e is VoiceBotAuthException) {
      final detail =
          (e.body != null && e.body!.isNotEmpty) ? e.body : e.message;
      return 'HTTP ${e.statusCode}: $detail';
    }
    if (e is VoiceBotApiException) {
      final detail =
          (e.body != null && e.body!.isNotEmpty) ? e.body : e.message;
      return 'HTTP ${e.statusCode}: $detail';
    }
    if (e is VoiceBotNetworkException) {
      if (e.cause != null) {
        return '${e.cause}';
      }
      return 'NetworkException: ${e.message}';
    }
    if (e is VoiceBotTimeoutException) {
      return 'Timeout: ${e.message}';
    }
    return '$e';
  }

  Future<bool> _tryAutoProvision() async {
    try {
      debugPrint(
          '[VoiceBotController] Attempting auto-provision via syncMemory for user: $_userId');
      await _client.syncMemory(userId: _userId);
      debugPrint(
          '[VoiceBotController] Auto-provision successful for user: $_userId');
      return true;
    } catch (err) {
      debugPrint('[VoiceBotController] Auto-provision failed: $err');
      return false;
    }
  }

  /// Updates user identity and language preference.
  void updateContext({String? userId, String? language}) {
    if (userId != null && userId.isNotEmpty) _userId = userId;
    if (language != null) _language = language;
    notifyListeners();
  }

  /// Proactively requests a welcome greeting from the VoiceBot.
  Future<void> sendWelcome() async {
    if (_state != VoiceBotState.idle) return;
    _setState(VoiceBotState.processing);

    try {
      final welcome = await _client.sendWelcome(
        userId: _userId,
        sessionId: _sessionId,
        language: _language,
        speak: true,
      );

      _sessionId = welcome.sessionId;
      _currentResponseText = welcome.responseText;
      _turns.add(
        VoiceBotTurn(
          userTranscript: '',
          botResponse: welcome.responseText,
          timestamp: DateTime.now(),
        ),
      );

      if (welcome.jobId != null && welcome.jobId!.isNotEmpty) {
        await _pollAndPlayTts(welcome.jobId!);
      } else {
        _setState(VoiceBotState.idle);
      }
    } on VoiceBotAuthException catch (e) {
      debugPrint('[VoiceBotController] sendWelcome AuthException: $e');
      if (e.statusCode == 403 &&
          (e.body?.contains('not authorized') ?? false)) {
        final provisioned = await _tryAutoProvision();
        if (provisioned) {
          try {
            final welcome = await _client.sendWelcome(
              userId: _userId,
              sessionId: _sessionId,
              language: _language,
              speak: true,
            );
            _sessionId = welcome.sessionId;
            _currentResponseText = welcome.responseText;
            _turns.add(
              VoiceBotTurn(
                userTranscript: '',
                botResponse: welcome.responseText,
                timestamp: DateTime.now(),
              ),
            );
            if (welcome.jobId != null && welcome.jobId!.isNotEmpty) {
              await _pollAndPlayTts(welcome.jobId!);
            } else {
              _setState(VoiceBotState.idle);
            }
            return;
          } catch (retryErr) {
            _rawErrorDetails = _formatError(retryErr);
            _errorMessage = _rawErrorDetails;
            _setState(VoiceBotState.error);
            return;
          }
        }
      }
      _rawErrorDetails = _formatError(e);
      _errorMessage = _rawErrorDetails;
      _setState(VoiceBotState.error);
    } catch (e) {
      debugPrint('[VoiceBotController] sendWelcome error: $e');
      _rawErrorDetails = _formatError(e);
      if (e is VoiceBotApiException || e is VoiceBotNetworkException) {
        _errorMessage = _rawErrorDetails;
        _setState(VoiceBotState.error);
      } else {
        _setState(VoiceBotState.idle);
      }
    }
  }

  /// Begins recording user speech after verifying microphone permission.
  Future<void> startListening() async {
    if (_state == VoiceBotState.listening) return;

    // 1. Permission check
    final hasPerm = await _permissions.hasMicrophonePermission();
    if (!hasPerm) {
      final status = await _permissions.requestMicrophonePermission();
      if (status != VoiceBotPermissionStatus.granted) {
        _errorMessage =
            'Microphone access is needed so your companion can hear you. Please allow microphone access.';
        _setState(VoiceBotState.error);
        return;
      }
    }

    try {
      // 2. Prepare WAV file path
      final tempDir = await _tempDirProvider();
      final path =
          '${tempDir.path}/voicebot_input_${DateTime.now().millisecondsSinceEpoch}.wav';
      _lastRecordedWavPath = path;

      // 3. Start audio recorder
      await _audioService.startRecording(path);

      _ampSub?.cancel();
      _ampSub = _audioService.amplitudeStream.listen((amp) {
        _amplitude = amp;
        notifyListeners();
      });

      _errorMessage = null;
      _rawErrorDetails = null;
      _setState(VoiceBotState.listening);
    } catch (e) {
      _rawErrorDetails = _formatError(e);
      _errorMessage = _rawErrorDetails;
      _setState(VoiceBotState.error);
    }
  }

  /// Stops recording, uploads WAV to VoiceBot API, polls TTS, and plays audio.
  Future<void> stopAndProcess() async {
    if (_state != VoiceBotState.listening) return;

    _ampSub?.cancel();
    _amplitude = 0.0;
    _setState(VoiceBotState.processing);

    List<int> wavBytes = const [];
    try {
      // 1. Explicitly await the recorder stop
      final path = await _audioService.stopRecording();

      // 2. OS Flush Delay: Allow physical device filesystem buffer to finish flushing to disk
      await Future.delayed(const Duration(milliseconds: 200));

      final recordedPath = path ?? _lastRecordedWavPath;

      // 3. Verify file existence and read bytes synchronously
      if (recordedPath == null || !File(recordedPath).existsSync()) {
        debugPrint(
            '[VoiceBotController] Audio file does not exist at: $recordedPath');
        _errorMessage = 'Audio file saved empty';
        _rawErrorDetails = 'Audio file does not exist on disk: $recordedPath';
        _setState(VoiceBotState.error);
        return;
      }

      final file = File(recordedPath);
      final bytes = file.readAsBytesSync();
      debugPrint('Audio file size: ${bytes.length} bytes');

      if (bytes.isEmpty) {
        debugPrint('[VoiceBotController] Audio file saved empty (0 bytes).');
        _errorMessage = 'Audio file saved empty';
        _rawErrorDetails =
            'Audio file saved empty (0 bytes on disk: $recordedPath)';
        _setState(VoiceBotState.error);
        return;
      }

      wavBytes = bytes;

      // Upload turn to /v1/conversation/voice
      final response = await _client.sendVoiceTurn(
        audioWavBytes: wavBytes,
        userId: _userId,
        sessionId: _sessionId,
        language: _language,
        speak: true,
      );

      _sessionId = response.sessionId;
      _currentTranscript = response.transcript;
      _currentResponseText = response.responseText;
      _errorMessage = null;
      _rawErrorDetails = null;

      _turns.add(
        VoiceBotTurn(
          userTranscript: response.transcript,
          botResponse: response.responseText,
          timestamp: DateTime.now(),
        ),
      );

      // Check if TTS job needs polling
      if (response.hasTtsJob) {
        await _pollAndPlayTts(response.jobId!);
      } else {
        _setState(VoiceBotState.idle);
      }
    } on VoiceBotAuthException catch (e) {
      debugPrint(
          '[VoiceBotController] VoiceBotAuthException: status=${e.statusCode}, message=${e.message}, body=${e.body}');
      if (e.statusCode == 403 &&
          (e.body?.contains('not authorized') ?? false)) {
        final provisioned = await _tryAutoProvision();
        if (provisioned) {
          try {
            final retryResponse = await _client.sendVoiceTurn(
              audioWavBytes: wavBytes,
              userId: _userId,
              sessionId: _sessionId,
              language: _language,
              speak: true,
            );
            _sessionId = retryResponse.sessionId;
            _currentTranscript = retryResponse.transcript;
            _currentResponseText = retryResponse.responseText;
            _errorMessage = null;
            _rawErrorDetails = null;

            _turns.add(
              VoiceBotTurn(
                userTranscript: retryResponse.transcript,
                botResponse: retryResponse.responseText,
                timestamp: DateTime.now(),
              ),
            );

            if (retryResponse.hasTtsJob) {
              await _pollAndPlayTts(retryResponse.jobId!);
            } else {
              _setState(VoiceBotState.idle);
            }
            return;
          } catch (retryErr) {
            _rawErrorDetails = _formatError(retryErr);
            _errorMessage = _rawErrorDetails;
            _setState(VoiceBotState.error);
            return;
          }
        }
      }
      _rawErrorDetails = _formatError(e);
      _errorMessage = _rawErrorDetails;
      _setState(VoiceBotState.error);
    } on VoiceBotApiException catch (e) {
      debugPrint(
          '[VoiceBotController] VoiceBotApiException: status=${e.statusCode}, message=${e.message}, body=${e.body}');
      _rawErrorDetails = _formatError(e);
      _errorMessage = _rawErrorDetails;
      _setState(VoiceBotState.error);
    } on VoiceBotTimeoutException catch (e) {
      debugPrint('[VoiceBotController] VoiceBotTimeoutException: ${e.message}');
      _rawErrorDetails = _formatError(e);
      _errorMessage = _rawErrorDetails;
      _setState(VoiceBotState.error);
    } on VoiceBotNetworkException catch (e) {
      debugPrint(
          '[VoiceBotController] VoiceBotNetworkException: ${e.message}, cause=${e.cause}');
      _rawErrorDetails = _formatError(e);
      _errorMessage = _rawErrorDetails;
      _setState(VoiceBotState.error);
    } catch (e, st) {
      debugPrint(
          '[VoiceBotController] Unexpected error in stopAndProcess: $e\n$st');
      _rawErrorDetails = _formatError(e);
      _errorMessage = _rawErrorDetails;
      _setState(VoiceBotState.error);
    }
  }

  /// Polls the TTS job and plays the resulting audio.
  Future<void> _pollAndPlayTts(String jobId) async {
    try {
      final job = await _client.pollJobUntilComplete(jobId);
      if (job.isCompleted && job.audioId != null && job.audioId!.isNotEmpty) {
        final audioBytes = await _client.downloadAudio(job.audioId!);
        _setState(VoiceBotState.speaking);
        await _audioService.playBytes(audioBytes);
      }
    } catch (e) {
      debugPrint('[VoiceBotController] TTS poll or play failed: $e');
      _rawErrorDetails = _formatError(e);
    } finally {
      _setState(VoiceBotState.idle);
    }
  }

  /// Cancels any ongoing recording or playback and returns to idle.
  Future<void> cancel() async {
    _ampSub?.cancel();
    _amplitude = 0.0;
    if (_audioService.isRecording) {
      await _audioService.stopRecording();
    }
    if (_audioService.isPlaying) {
      await _audioService.stopPlayback();
    }
    _errorMessage = null;
    _rawErrorDetails = null;
    _setState(VoiceBotState.idle);
  }

  /// Clears conversation history and starts a fresh session.
  void resetSession() {
    _sessionId = null;
    _currentTranscript = '';
    _currentResponseText = '';
    _errorMessage = null;
    _rawErrorDetails = null;
    _turns.clear();
    _setState(VoiceBotState.idle);
  }

  void _setState(VoiceBotState next) {
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _ampSub?.cancel();
    _audioService.dispose();
    _client.dispose();
    super.dispose();
  }
}
