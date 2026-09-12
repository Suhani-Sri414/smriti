import 'package:flutter_test/flutter_test.dart';
import 'package:smriti/core/voice/voice_commander.dart';

class _FakeSpeechClient implements SpeechClient {
  bool initSuccess = true;
  void Function(String error)? onErrorListener;
  void Function(String status)? onStatusListener;
  void Function(String words, bool isFinal)? onResultListener;
  bool isListeningNow = false;
  int stopCalls = 0;

  @override
  Future<bool> initialize({
    void Function(String error)? onError,
    void Function(String status)? onStatus,
  }) async {
    onErrorListener = onError;
    onStatusListener = onStatus;
    return initSuccess;
  }

  @override
  Future<void> listen({
    required void Function(String recognizedWords, bool isFinal) onResult,
    Duration? listenFor,
    Duration? pauseFor,
    String? localeId,
  }) async {
    onResultListener = onResult;
    isListeningNow = true;
  }

  @override
  Future<void> stop() async {
    isListeningNow = false;
    stopCalls++;
  }

  void emitSpeechResult(String words, {bool isFinal = false}) {
    onResultListener?.call(words, isFinal);
  }
}

void main() {
  group('SpeechToTextVoiceCommander', () {
    late _FakeSpeechClient fakeSpeech;
    late SpeechToTextVoiceCommander commander;

    setUp(() {
      fakeSpeech = _FakeSpeechClient();
      commander = SpeechToTextVoiceCommander(
        speechClient: fakeSpeech,
        localeId: 'bn_IN',
      );
    });

    test('initializes recognizer and starts listening', () async {
      VoiceCommand? result;
      await commander.startListening(
        onResult: (cmd) => result = cmd,
        timeout: const Duration(seconds: 3),
      );

      expect(commander.isListening, isTrue);
      expect(fakeSpeech.isListeningNow, isTrue);
      expect(result, isNull);
    });

    test('emits recognized command when speech matches keywords', () async {
      VoiceCommand? result;
      await commander.startListening(
        onResult: (cmd) => result = cmd,
      );

      fakeSpeech.emitSpeechResult('khelte chai market basket');
      expect(result, VoiceCommand.play);
      expect(commander.isListening, isFalse);
    });

    test('emits recognized command for medication and routine keywords',
        () async {
      VoiceCommand? result;
      await commander.startListening(
        onResult: (cmd) => result = cmd,
      );

      fakeSpeech.emitSpeechResult('aajker dawai');
      expect(result, VoiceCommand.today);
      expect(commander.isListening, isFalse);
    });

    test('emits recognized command for family and call keywords', () async {
      VoiceCommand? result;
      await commander.startListening(
        onResult: (cmd) => result = cmd,
      );

      fakeSpeech.emitSpeechResult('call bina');
      expect(result, VoiceCommand.call);
      expect(commander.isListening, isFalse);
    });

    test('emits null on final result when words do not match any command',
        () async {
      VoiceCommand? result;
      var callbackCalled = false;
      await commander.startListening(
        onResult: (cmd) {
          result = cmd;
          callbackCalled = true;
        },
      );

      fakeSpeech.emitSpeechResult('unrelated rambling conversation',
          isFinal: true);
      expect(callbackCalled, isTrue);
      expect(result, isNull);
      expect(commander.isListening, isFalse);
    });

    test('emits null gracefully when speech initialization fails', () async {
      fakeSpeech.initSuccess = false;
      VoiceCommand? result;
      var callbackCalled = false;

      await commander.startListening(
        onResult: (cmd) {
          result = cmd;
          callbackCalled = true;
        },
      );

      expect(callbackCalled, isTrue);
      expect(result, isNull);
      expect(commander.isListening, isFalse);
    });

    test('stopListening terminates active listening session', () async {
      await commander.startListening(
        onResult: (_) {},
      );
      expect(commander.isListening, isTrue);

      await commander.stopListening();
      expect(commander.isListening, isFalse);
      expect(fakeSpeech.stopCalls, 1);
    });
  });
}
