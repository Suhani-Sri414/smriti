import 'dart:async';
import 'dart:io';

/// Records an elder's voice memo to local disk.
///
/// Abstracted so screens can be widget-tested without hardware/mic backend
/// dependencies.
abstract class VoiceRecorder {
  Future<void> start(String path);

  /// Stops recording and returns duration in milliseconds.
  Future<int> stop();

  bool get isRecording;

  Future<void> dispose();
}

/// Stand-in recorder used for tests and platforms without mic setup.
/// Generates a valid placeholder audio file on disk so `File.existsSync()`
/// holds true for downstream sync.
class StubVoiceRecorder implements VoiceRecorder {
  bool _recording = false;
  DateTime? _startedAt;
  String? _path;

  @override
  bool get isRecording => _recording;

  @override
  Future<void> start(String path) async {
    _path = path;
    _recording = true;
    _startedAt = DateTime.now();
  }

  @override
  Future<int> stop() async {
    if (!_recording) return 0;
    _recording = false;
    final duration = DateTime.now()
        .difference(_startedAt ?? DateTime.now())
        .inMilliseconds;

    if (_path != null) {
      final file = File(_path!);
      if (!file.parent.existsSync()) {
        file.parent.createSync(recursive: true);
      }
      if (!file.existsSync()) {
        file.writeAsBytesSync(const [0x00, 0x00]);
      }
    }
    return duration.clamp(500, 60000);
  }

  @override
  Future<void> dispose() async {
    _recording = false;
  }
}
