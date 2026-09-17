import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Adapter interface for Text-to-Speech engines, enabling clean unit and widget
/// testing without hardware or native method channel dependencies.
abstract class TtsAdapter {
  Future<dynamic> setSpeechRate(double rate);
  Future<dynamic> setVolume(double volume);
  Future<dynamic> setPitch(double pitch);
  Future<dynamic> setLanguage(String language);
  Future<dynamic> speak(String text);
  Future<dynamic> stop();
  void setStartHandler(VoidCallback callback);
  void setCompletionHandler(VoidCallback callback);
  void setCancelHandler(VoidCallback callback);
  void setErrorHandler(void Function(dynamic message) callback);
}

/// Production TTS adapter backed by the `flutter_tts` plugin.
class FlutterTtsAdapter implements TtsAdapter {
  FlutterTtsAdapter([FlutterTts? tts]) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;

  @override
  Future<dynamic> setSpeechRate(double rate) => _tts.setSpeechRate(rate);

  @override
  Future<dynamic> setVolume(double volume) => _tts.setVolume(volume);

  @override
  Future<dynamic> setPitch(double pitch) => _tts.setPitch(pitch);

  @override
  Future<dynamic> setLanguage(String language) => _tts.setLanguage(language);

  @override
  Future<dynamic> speak(String text) => _tts.speak(text);

  @override
  Future<dynamic> stop() => _tts.stop();

  @override
  void setStartHandler(VoidCallback callback) => _tts.setStartHandler(callback);

  @override
  void setCompletionHandler(VoidCallback callback) =>
      _tts.setCompletionHandler(callback);

  @override
  void setCancelHandler(VoidCallback callback) =>
      _tts.setCancelHandler(callback);

  @override
  void setErrorHandler(void Function(dynamic message) callback) =>
      _tts.setErrorHandler(callback);
}

/// Local Text-to-Speech (TTS) service configured for cognitive accessibility.
///
/// Designed specifically for dementia and elderly users:
/// - Speech rate is calibrated slightly slower (0.42) for high speech intelligibility
///   and reduced cognitive processing load.
/// - Full volume and natural pitch ensure maximum acoustic clarity.
/// - Exposes reactive speech state via [isSpeakingNotifier] for visual indicators.
class ScreenReaderService {
  ScreenReaderService({
    TtsAdapter? ttsAdapter,
    double speechRate = 0.42,
    double pitch = 1.0,
    double volume = 1.0,
    String defaultLanguage = 'en-US',
  })  : _tts = ttsAdapter ?? FlutterTtsAdapter(),
        _speechRate = speechRate,
        _pitch = pitch,
        _volume = volume,
        _defaultLanguage = defaultLanguage {
    _init();
  }

  final TtsAdapter _tts;
  final double _speechRate;
  final double _pitch;
  final double _volume;
  final String _defaultLanguage;

  final ValueNotifier<bool> _isSpeaking = ValueNotifier<bool>(false);

  /// Reactive listenable indicating whether the service is currently speaking.
  ValueListenable<bool> get isSpeakingNotifier => _isSpeaking;

  /// Current speaking state.
  bool get isSpeaking => _isSpeaking.value;

  bool _isInitialized = false;

  void _init() {
    _tts.setStartHandler(() {
      _isSpeaking.value = true;
    });
    _tts.setCompletionHandler(() {
      _isSpeaking.value = false;
    });
    _tts.setCancelHandler(() {
      _isSpeaking.value = false;
    });
    _tts.setErrorHandler((dynamic message) {
      debugPrint('[ScreenReaderService] TTS error: $message');
      _isSpeaking.value = false;
    });
  }

  /// Configures the TTS engine parameters for cognitive accessibility.
  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      await _tts.setVolume(_volume);
      await _tts.setPitch(_pitch);
      await _tts.setSpeechRate(_speechRate);
      await _tts.setLanguage(_defaultLanguage);
      _isInitialized = true;
    } catch (e) {
      debugPrint('[ScreenReaderService] Warning during initialize: $e');
    }
  }

  /// Speaks the provided [text] aloud at a calm, cognitive-accessible rate.
  ///
  /// If already speaking, previous speech is stopped before the new text starts.
  Future<void> speak(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    try {
      if (!_isInitialized) {
        await initialize();
      }
      if (_isSpeaking.value) {
        await stop();
      }
      _isSpeaking.value = true;
      await _tts.speak(trimmed);
    } catch (e) {
      debugPrint('[ScreenReaderService] speak failed: $e');
      _isSpeaking.value = false;
    }
  }

  /// Stops speech playback immediately and resets speaking state.
  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (e) {
      debugPrint('[ScreenReaderService] stop failed: $e');
    } finally {
      _isSpeaking.value = false;
    }
  }

  /// Releases resources and resets speaking state.
  void dispose() {
    unawaited(stop());
    _isSpeaking.dispose();
  }
}
