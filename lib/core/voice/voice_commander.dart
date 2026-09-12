import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Navigation and high-level commands recognizable from Home.
enum VoiceCommand {
  /// Open games menu or launch cognitive games.
  play,

  /// Open today's schedule, routines, or medications timeline.
  today,

  /// Open family and caregiver gallery (My People).
  people,

  /// Initiate family phone call confirmation.
  call,
}

/// Abstract commander for listening to elder speech on Home screen.
abstract class VoiceCommander {
  /// Whether the recognizer is currently listening for speech.
  bool get isListening;

  /// Starts listening for elder voice commands.
  ///
  /// Invokes [onResult] with the recognized [VoiceCommand], or `null` if the
  /// timeout elapsed or speech could not be confidently matched.
  Future<void> startListening({
    required ValueChanged<VoiceCommand?> onResult,
    Duration timeout = const Duration(seconds: 4),
  });

  /// Cancels listening immediately without invoking callbacks.
  Future<void> stopListening();

  /// Utility parser to match transcribed speech strings to [VoiceCommand]s.
  static VoiceCommand? parseText(String input) {
    final clean = input.trim().toLowerCase();
    if (clean.isEmpty) return null;

    // Play commands
    if (clean.contains('play') ||
        clean.contains('game') ||
        clean.contains('khel') ||
        clean.contains('basket') ||
        clean.contains('harvest') ||
        clean.contains('puzzle')) {
      return VoiceCommand.play;
    }

    // Today / Routine / Medicine commands
    if (clean.contains('today') ||
        clean.contains('routine') ||
        clean.contains('schedule') ||
        clean.contains('medicine') ||
        clean.contains('pill') ||
        clean.contains('dawai') ||
        clean.contains('aaj')) {
      return VoiceCommand.today;
    }

    // My People / Family commands
    if (clean.contains('people') ||
        clean.contains('family') ||
        clean.contains('photo') ||
        clean.contains('parivar') ||
        clean.contains('relative') ||
        clean.contains('daughter') ||
        clean.contains('son')) {
      return VoiceCommand.people;
    }

    // Call commands
    if (clean.contains('call') ||
        clean.contains('phone') ||
        clean.contains('bina') ||
        clean.contains('talk') ||
        clean.contains('ring')) {
      return VoiceCommand.call;
    }

    return null;
  }
}

/// A fake voice commander for deterministic testing and manual simulation.
class FakeVoiceCommander implements VoiceCommander {
  FakeVoiceCommander({this.autoMatchCommand, this.autoDelay});

  /// If provided, automatically emits this command after [autoDelay].
  VoiceCommand? autoMatchCommand;

  /// If provided, auto-delay before emitting [autoMatchCommand].
  Duration? autoDelay;

  ValueChanged<VoiceCommand?>? _onResult;
  Timer? _timer;
  bool _listening = false;

  @override
  bool get isListening => _listening;

  @override
  Future<void> startListening({
    required ValueChanged<VoiceCommand?> onResult,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    _listening = true;
    _onResult = onResult;

    final delay = autoDelay;
    if (delay != null) {
      _timer = Timer(delay, () {
        if (_listening) {
          _listening = false;
          _onResult?.call(autoMatchCommand);
        }
      });
    }
  }

  /// Manually emit a recognized text command during test execution.
  void simulateSpeech(String spokenText) {
    if (!_listening) return;
    _listening = false;
    _timer?.cancel();
    final cmd = VoiceCommander.parseText(spokenText);
    _onResult?.call(cmd);
  }

  /// Manually trigger a timeout without match.
  void simulateTimeout() {
    if (!_listening) return;
    _listening = false;
    _timer?.cancel();
    _onResult?.call(null);
  }

  @override
  Future<void> stopListening() async {
    _listening = false;
    _timer?.cancel();
    _onResult = null;
  }
}

/// Abstract speech-to-text service client interface for testing and platform delegation.
abstract class SpeechClient {
  Future<bool> initialize({
    void Function(String error)? onError,
    void Function(String status)? onStatus,
  });

  Future<void> listen({
    required void Function(String recognizedWords, bool isFinal) onResult,
    Duration? listenFor,
    Duration? pauseFor,
    String? localeId,
  });

  Future<void> stop();
}

/// Production implementation backed by `package:speech_to_text`.
class RealSpeechClient implements SpeechClient {
  RealSpeechClient({stt.SpeechToText? speech})
      : _speech = speech ?? stt.SpeechToText();

  final stt.SpeechToText _speech;

  @override
  Future<bool> initialize({
    void Function(String error)? onError,
    void Function(String status)? onStatus,
  }) async {
    return _speech.initialize(
      onError: onError != null ? (e) => onError(e.errorMsg) : null,
      onStatus: onStatus != null ? (s) => onStatus(s) : null,
    );
  }

  @override
  Future<void> listen({
    required void Function(String recognizedWords, bool isFinal) onResult,
    Duration? listenFor,
    Duration? pauseFor,
    String? localeId,
  }) async {
    await _speech.listen(
      onResult: (result) =>
          onResult(result.recognizedWords, result.finalResult),
      listenFor: listenFor,
      pauseFor: pauseFor,
      localeId: localeId,
      listenOptions: stt.SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
      ),
    );
  }

  @override
  Future<void> stop() => _speech.stop();
}

/// Hardware speech recognition commander backed by `package:speech_to_text`.
class SpeechToTextVoiceCommander implements VoiceCommander {
  SpeechToTextVoiceCommander({
    SpeechClient? speechClient,
    this.localeId,
  }) : _speech = speechClient ?? RealSpeechClient();

  final SpeechClient _speech;
  final String? localeId;

  bool _initialized = false;
  bool _isListening = false;
  ValueChanged<VoiceCommand?>? _onResult;
  Timer? _fallbackTimer;

  @override
  bool get isListening => _isListening;

  /// Initializes speech recognition engine with system speech services.
  Future<bool> initialize() async {
    if (_initialized) return true;
    try {
      _initialized = await _speech.initialize(
        onError: (_) {
          _finishListening(null);
        },
        onStatus: (status) {
          if (status == 'notListening' || status == 'done') {
            if (_isListening) {
              _finishListening(null);
            }
          }
        },
      );
      return _initialized;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> startListening({
    required ValueChanged<VoiceCommand?> onResult,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    _onResult = onResult;
    _fallbackTimer?.cancel();

    final available = await initialize();
    if (!available) {
      // Speech service unavailable or mic permission denied -> zero elder errors
      _finishListening(null);
      return;
    }

    _isListening = true;

    // Safety fallback timer so recognition never hangs
    _fallbackTimer = Timer(timeout + const Duration(milliseconds: 500), () {
      if (_isListening) {
        _finishListening(null);
      }
    });

    try {
      await _speech.listen(
        onResult: (words, isFinal) {
          final command = VoiceCommander.parseText(words);
          if (command != null) {
            _finishListening(command);
          } else if (isFinal) {
            _finishListening(null);
          }
        },
        listenFor: timeout,
        pauseFor: const Duration(seconds: 2),
        localeId: localeId,
      );
    } catch (_) {
      _finishListening(null);
    }
  }

  void _finishListening(VoiceCommand? command) {
    if (!_isListening && _onResult == null) return;
    _isListening = false;
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
    final callback = _onResult;
    _onResult = null;
    try {
      _speech.stop();
    } catch (_) {}
    callback?.call(command);
  }

  @override
  Future<void> stopListening() async {
    _isListening = false;
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
    _onResult = null;
    try {
      await _speech.stop();
    } catch (_) {}
  }
}


