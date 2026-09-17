import 'dart:async';
import 'dart:io';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Gateway interface for audio recording.
abstract class VoiceBotRecorderGateway {
  Future<bool> hasPermission();
  Future<void> start(String path);
  Future<String?> stop();
  Stream<double> get amplitudeStream;
  bool get isRecording;
  Future<void> dispose();
}

/// Production recorder gateway backed by `package:record`.
class RecordAudioRecorderGateway implements VoiceBotRecorderGateway {
  RecordAudioRecorderGateway({AudioRecorder? recorder})
      : _customRecorder = recorder;

  final AudioRecorder? _customRecorder;
  AudioRecorder? _lazyRecorder;

  AudioRecorder get _recorder {
    final custom = _customRecorder;
    if (custom != null) return custom;
    return _lazyRecorder ??= AudioRecorder();
  }

  bool _isRecording = false;

  @override
  bool get isRecording => _isRecording;

  @override
  Future<bool> hasPermission() async {
    try {
      return await _recorder.hasPermission();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> start(String path) async {
    // Strictly configured to output uncompressed 16kHz mono PCM 16-bit WAV (not AAC/.m4a)
    const config = RecordConfig(
      encoder: AudioEncoder.wav,
      sampleRate: 16000,
      numChannels: 1,
    );
    await _recorder.start(config, path: path);
    _isRecording = true;
  }

  @override
  Future<String?> stop() async {
    if (!_isRecording) return null;
    _isRecording = false;
    final path = await _recorder.stop();
    return path;
  }

  @override
  Stream<double> get amplitudeStream {
    try {
      return _recorder
          .onAmplitudeChanged(const Duration(milliseconds: 100))
          .map((amp) {
        // Normalise dB (-60 to 0) to 0.0 .. 1.0
        final current = amp.current.clamp(-60.0, 0.0);
        return (current + 60.0) / 60.0;
      });
    } catch (_) {
      return const Stream.empty();
    }
  }

  @override
  Future<void> dispose() async {
    _isRecording = false;
    if (_customRecorder != null || _lazyRecorder != null) {
      await _recorder.dispose();
    }
  }
}

/// Gateway interface for audio playback.
abstract class VoiceBotPlayerGateway {
  Future<void> playFile(String path);
  Future<void> playBytes(List<int> bytes);
  Future<void> stop();
  bool get isPlaying;
  Stream<bool> get isPlayingStream;
  Future<void> dispose();
}

/// Production player gateway backed by `package:just_audio`.
class JustAudioPlayerGateway implements VoiceBotPlayerGateway {
  JustAudioPlayerGateway({AudioPlayer? player})
      : _customPlayer = player;

  final AudioPlayer? _customPlayer;
  AudioPlayer? _lazyPlayer;

  AudioPlayer get _player {
    final custom = _customPlayer;
    if (custom != null) return custom;
    return _lazyPlayer ??= AudioPlayer();
  }

  final StreamController<bool> _playingController =
      StreamController<bool>.broadcast();

  @override
  bool get isPlaying => _player.playing;

  @override
  Stream<bool> get isPlayingStream => _player.playingStream;

  @override
  Future<void> playFile(String path) async {
    if (!File(path).existsSync()) return;
    await _player.setFilePath(path);
    await _player.play();
  }

  @override
  Future<void> playBytes(List<int> bytes) async {
    Directory tempDir;
    try {
      tempDir = await getTemporaryDirectory();
    } catch (_) {
      tempDir = Directory.systemTemp;
    }
    final tempFile = File(
      '${tempDir.path}/voicebot_resp_${DateTime.now().millisecondsSinceEpoch}.wav',
    );
    await tempFile.writeAsBytes(bytes);
    await playFile(tempFile.path);
  }

  @override
  Future<void> stop() {
    if (_customPlayer != null || _lazyPlayer != null) {
      return _player.stop();
    }
    return Future.value();
  }

  @override
  Future<void> dispose() async {
    if (_customPlayer != null || _lazyPlayer != null) {
      await _player.dispose();
    }
    await _playingController.close();
  }
}

/// Mock recorder gateway for unit and widget testing.
class MockVoiceBotRecorderGateway implements VoiceBotRecorderGateway {
  bool _recording = false;
  String? _currentPath;
  final StreamController<double> _ampController =
      StreamController<double>.broadcast();

  @override
  bool get isRecording => _recording;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<void> start(String path) async {
    _currentPath = path;
    _recording = true;
  }

  @override
  Future<String?> stop() async {
    if (!_recording) return null;
    _recording = false;
    if (_currentPath != null) {
      final file = File(_currentPath!);
      if (!file.parent.existsSync()) {
        file.parent.createSync(recursive: true);
      }
      if (!file.existsSync()) {
        // Minimal valid PCM WAV header + 100 bytes silence
        file.writeAsBytesSync(List.filled(144, 0));
      }
    }
    return _currentPath;
  }

  void emitAmplitude(double amp) => _ampController.add(amp);

  @override
  Stream<double> get amplitudeStream => _ampController.stream;

  @override
  Future<void> dispose() async {
    _recording = false;
    await _ampController.close();
  }
}

/// Mock player gateway for unit and widget testing.
class MockVoiceBotPlayerGateway implements VoiceBotPlayerGateway {
  bool _playing = false;
  final List<String> playedFiles = [];
  final List<List<int>> playedByteLists = [];
  final StreamController<bool> _playStream = StreamController<bool>.broadcast();

  @override
  bool get isPlaying => _playing;

  @override
  Stream<bool> get isPlayingStream => _playStream.stream;

  @override
  Future<void> playFile(String path) async {
    playedFiles.add(path);
    _playing = true;
    _playStream.add(true);
  }

  @override
  Future<void> playBytes(List<int> bytes) async {
    playedByteLists.add(bytes);
    _playing = true;
    _playStream.add(true);
  }

  @override
  Future<void> stop() async {
    _playing = false;
    _playStream.add(false);
  }

  @override
  Future<void> dispose() async {
    _playing = false;
    await _playStream.close();
  }
}

/// Unified audio service managing VoiceBot recording and playback.
class VoiceBotAudioService {
  VoiceBotAudioService({
    VoiceBotRecorderGateway? recorderGateway,
    VoiceBotPlayerGateway? playerGateway,
  })  : _recorder = recorderGateway ?? RecordAudioRecorderGateway(),
        _player = playerGateway ?? JustAudioPlayerGateway();

  final VoiceBotRecorderGateway _recorder;
  final VoiceBotPlayerGateway _player;

  bool get isRecording => _recorder.isRecording;
  bool get isPlaying => _player.isPlaying;
  Stream<double> get amplitudeStream => _recorder.amplitudeStream;
  Stream<bool> get isPlayingStream => _player.isPlayingStream;

  Future<void> startRecording(String path) => _recorder.start(path);

  Future<String?> stopRecording() async {
    return await _recorder.stop();
  }

  Future<void> playFile(String path) => _player.playFile(path);

  Future<void> playBytes(List<int> bytes) => _player.playBytes(bytes);

  Future<void> stopPlayback() => _player.stop();

  Future<void> dispose() async {
    await _recorder.dispose();
    await _player.dispose();
  }
}
