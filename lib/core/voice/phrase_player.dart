import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../games/cognitive_game.dart';
import '../files/file_paths.dart';
import 'voice_player.dart';

/// Plays pre-recorded caregiver / language pack voice phrases.
///
/// Per APP-BUILD-SPEC.md §6 and §11:
/// - Maps [PhraseKey]s to audio files in the active language pack.
/// - If a phrase audio file is missing on disk, it is skipped silently rather
///   than throwing or surfacing error indicators to the elder (AGENTS.md #9).
abstract class PhrasePlayer {
  /// Current active language pack code (e.g. 'bn', 'en', 'me').
  String get activeLanguage;

  /// Sets the active language pack code.
  void setLanguage(String languageCode);

  /// Plays the audio file corresponding to [key] in the active language.
  Future<void> playPhrase(PhraseKey key);

  /// Stops current phrase playback.
  Future<void> stop();

  /// Releases audio player resources.
  Future<void> dispose();
}

/// Production implementation searching local disk language packs and assets.
class DiskAndAssetPhrasePlayer implements PhrasePlayer {
  DiskAndAssetPhrasePlayer({
    VoicePlayer? voicePlayer,
    String initialLanguage = 'bn',
    Future<String> Function()? languagePacksDirResolver,
  })  : _voicePlayer = voicePlayer ?? JustAudioVoicePlayer(),
        _activeLanguage = initialLanguage,
        _languagePacksDirResolver =
            languagePacksDirResolver ?? FilePaths.languagePacks;

  final VoicePlayer _voicePlayer;
  final Future<String> Function() _languagePacksDirResolver;
  String _activeLanguage;

  @override
  String get activeLanguage => _activeLanguage;

  @override
  void setLanguage(String languageCode) {
    if (languageCode.trim().isNotEmpty) {
      _activeLanguage = languageCode.trim().toLowerCase();
    }
  }

  /// Resolves the absolute path to an audio file on disk for [key], or null if
  /// not found.
  Future<String?> resolvePhrasePath(PhraseKey key) async {
    final root = await _languagePacksDirResolver();
    final keyName = key.name;
    const extensions = ['.mp3', '.m4a', '.wav', '.aac', '.ogg'];

    // 1. Try active language folder (e.g. language_packs/bn/wellDone.mp3)
    for (final ext in extensions) {
      final candidate = p.join(root, _activeLanguage, '$keyName$ext');
      if (File(candidate).existsSync()) {
        return candidate;
      }
    }

    // 2. Try default fallback folder (e.g. language_packs/default/wellDone.mp3)
    for (final ext in extensions) {
      final candidate = p.join(root, 'default', '$keyName$ext');
      if (File(candidate).existsSync()) {
        return candidate;
      }
    }

    return null;
  }

  @override
  Future<void> playPhrase(PhraseKey key) async {
    try {
      final path = await resolvePhrasePath(key);
      if (path != null && path.isNotEmpty) {
        await _voicePlayer.play(path);
      }
      // If path is null, silently skip per APP-BUILD-SPEC.md §6
    } catch (_) {
      // Zero elder leakage: swallow and continue calmly
    }
  }

  @override
  Future<void> stop() => _voicePlayer.stop();

  @override
  Future<void> dispose() => _voicePlayer.dispose();
}

/// Stand-in phrase player for tests and headless CI environments.
class SilentPhrasePlayer implements PhrasePlayer {
  SilentPhrasePlayer({this.activeLanguage = 'bn'});

  @override
  String activeLanguage;

  final List<PhraseKey> playedPhrases = [];
  int stopCalls = 0;
  bool isDisposed = false;

  @override
  void setLanguage(String languageCode) {
    activeLanguage = languageCode;
  }

  @override
  Future<void> playPhrase(PhraseKey key) async {
    playedPhrases.add(key);
  }

  @override
  Future<void> stop() async {
    stopCalls++;
  }

  @override
  Future<void> dispose() async {
    isDisposed = true;
  }
}
