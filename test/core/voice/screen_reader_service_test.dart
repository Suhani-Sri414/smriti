import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:smriti/core/voice/screen_reader_service.dart';

class FakeTtsAdapter implements TtsAdapter {
  double? speechRate;
  double? volume;
  double? pitch;
  String? language;

  List<String> speakCalls = [];
  int stopCalls = 0;

  VoidCallback? startHandler;
  VoidCallback? completionHandler;
  VoidCallback? cancelHandler;
  void Function(dynamic message)? errorHandler;

  @override
  Future<dynamic> setSpeechRate(double rate) async => speechRate = rate;

  @override
  Future<dynamic> setVolume(double volume) async => this.volume = volume;

  @override
  Future<dynamic> setPitch(double pitch) async => this.pitch = pitch;

  @override
  Future<dynamic> setLanguage(String language) async => this.language = language;

  @override
  Future<dynamic> speak(String text) async {
    speakCalls.add(text);
    startHandler?.call();
    return 1;
  }

  @override
  Future<dynamic> stop() async {
    stopCalls++;
    cancelHandler?.call();
    return 1;
  }

  @override
  void setStartHandler(VoidCallback callback) => startHandler = callback;

  @override
  void setCompletionHandler(VoidCallback callback) =>
      completionHandler = callback;

  @override
  void setCancelHandler(VoidCallback callback) => cancelHandler = callback;

  @override
  void setErrorHandler(void Function(dynamic message) callback) =>
      errorHandler = callback;
}

void main() {
  late FakeTtsAdapter fakeTts;
  late ScreenReaderService service;

  setUp(() {
    fakeTts = FakeTtsAdapter();
    service = ScreenReaderService(
      ttsAdapter: fakeTts,
      speechRate: 0.42,
      pitch: 1.0,
      volume: 1.0,
      defaultLanguage: 'en-US',
    );
  });

  tearDown(() {
    service.dispose();
  });

  group('ScreenReaderService', () {
    test('initializes with cognitive accessibility parameters', () async {
      await service.initialize();

      expect(fakeTts.speechRate, 0.42);
      expect(fakeTts.pitch, 1.0);
      expect(fakeTts.volume, 1.0);
      expect(fakeTts.language, 'en-US');
    });

    test('speak updates isSpeaking and delegates to adapter', () async {
      expect(service.isSpeaking, isFalse);

      await service.speak('Welcome to Smriti');

      expect(fakeTts.speakCalls, ['Welcome to Smriti']);
      expect(service.isSpeaking, isTrue);
    });

    test('speak ignores empty text', () async {
      await service.speak('   ');

      expect(fakeTts.speakCalls, isEmpty);
      expect(service.isSpeaking, isFalse);
    });

    test('stop halts playback and updates isSpeaking', () async {
      await service.speak('Hello');
      expect(service.isSpeaking, isTrue);

      await service.stop();

      expect(fakeTts.stopCalls, 1);
      expect(service.isSpeaking, isFalse);
    });

    test('completion handler sets isSpeaking to false', () async {
      await service.speak('Hello');
      expect(service.isSpeaking, isTrue);

      fakeTts.completionHandler?.call();

      expect(service.isSpeaking, isFalse);
    });

    test('error handler sets isSpeaking to false', () async {
      await service.speak('Hello');
      expect(service.isSpeaking, isTrue);

      fakeTts.errorHandler?.call('Engine error');

      expect(service.isSpeaking, isFalse);
    });

    test('calling speak while speaking stops previous speech first', () async {
      await service.speak('First phrase');
      expect(service.isSpeaking, isTrue);

      await service.speak('Second phrase');

      expect(fakeTts.stopCalls, 1);
      expect(fakeTts.speakCalls, ['First phrase', 'Second phrase']);
      expect(service.isSpeaking, isTrue);
    });
  });
}
