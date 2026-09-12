import 'dart:async';
import 'package:flutter/foundation.dart';

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
