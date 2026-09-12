import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:smriti/core/ability/estimator.dart';
import 'package:smriti/core/repo/ability_repo.dart';
import 'package:smriti/core/repo/event_repo.dart';
import 'package:smriti/core/voice/phrase_player.dart';
import 'package:smriti/core/voice/voice_player.dart';
import 'package:smriti/games/cognitive_game.dart';
import 'package:smriti/games/session_runner.dart';

import '../repo/_test_db.dart';

class _MockVoicePlayer implements VoicePlayer {
  final List<String> played = [];
  int stopCalls = 0;
  bool isDisposed = false;

  @override
  Future<void> play(String path) async {
    played.add(path);
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

class _TestCognitiveGame extends CognitiveGame {
  _TestCognitiveGame(this.id);

  @override
  final String id;

  final StreamController<TrialResult> _trialController =
      StreamController<TrialResult>.broadcast();

  @override
  PhraseKey get introPhrase => PhraseKey.marketBasketIntro;

  @override
  CognitiveDomain get primaryDomain => CognitiveDomain.memory;

  @override
  Stream<TrialResult> get trials => _trialController.stream;

  @override
  GameItem generateItem(double difficulty, GameContent content) {
    return GameItem(id: 'item-1', difficulty: difficulty);
  }

  @override
  Future<void> playDemo(context) async {}

  void emitResult(TrialResult result) => _trialController.add(result);

  Future<void> dispose() async {
    await _trialController.close();
  }
}

void main() {
  group('DiskAndAssetPhrasePlayer', () {
    late Directory tempDir;
    late _MockVoicePlayer voicePlayer;
    late DiskAndAssetPhrasePlayer phrasePlayer;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('phrase_player_test_');
      voicePlayer = _MockVoicePlayer();
      phrasePlayer = DiskAndAssetPhrasePlayer(
        voicePlayer: voicePlayer,
        initialLanguage: 'bn',
        languagePacksDirResolver: () async => tempDir.path,
      );
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('missing audio file skips silently without error or playback',
        () async {
      await phrasePlayer.playPhrase(PhraseKey.wellDone);
      expect(voicePlayer.played, isEmpty);
    });

    test('plays existing audio file in active language folder', () async {
      final bnDir = Directory(p.join(tempDir.path, 'bn'));
      await bnDir.create(recursive: true);
      final audioFile = File(p.join(bnDir.path, 'wellDone.mp3'));
      await audioFile.writeAsBytes(const [0x00, 0x01, 0x02]);

      await phrasePlayer.playPhrase(PhraseKey.wellDone);
      expect(voicePlayer.played, [audioFile.path]);
    });

    test('falls back to default folder when active language file is missing',
        () async {
      final defaultDir = Directory(p.join(tempDir.path, 'default'));
      await defaultDir.create(recursive: true);
      final audioFile = File(p.join(defaultDir.path, 'tryAnother.mp3'));
      await audioFile.writeAsBytes(const [0x00, 0x01, 0x02]);

      await phrasePlayer.playPhrase(PhraseKey.tryAnother);
      expect(voicePlayer.played, [audioFile.path]);
    });

    test('switches active language pack', () async {
      final enDir = Directory(p.join(tempDir.path, 'en'));
      await enDir.create(recursive: true);
      final audioFile = File(p.join(enDir.path, 'sessionStart.wav'));
      await audioFile.writeAsBytes(const [0x00, 0x01, 0x02]);

      phrasePlayer.setLanguage('en');
      expect(phrasePlayer.activeLanguage, 'en');

      await phrasePlayer.playPhrase(PhraseKey.sessionStart);
      expect(voicePlayer.played, [audioFile.path]);
    });

    test('stop and dispose delegate to underlying voice player', () async {
      await phrasePlayer.stop();
      expect(voicePlayer.stopCalls, 1);

      await phrasePlayer.dispose();
      expect(voicePlayer.isDisposed, isTrue);
    });
  });

  group('SilentPhrasePlayer', () {
    test('records played phrases accurately', () async {
      final player = SilentPhrasePlayer();
      await player.playPhrase(PhraseKey.sessionStart);
      await player.playPhrase(PhraseKey.marketBasketIntro);
      await player.playPhrase(PhraseKey.wellDone);
      await player.playPhrase(PhraseKey.sessionEnd);

      expect(player.playedPhrases, [
        PhraseKey.sessionStart,
        PhraseKey.marketBasketIntro,
        PhraseKey.wellDone,
        PhraseKey.sessionEnd,
      ]);

      await player.stop();
      expect(player.stopCalls, 1);

      await player.dispose();
      expect(player.isDisposed, isTrue);
    });
  });

  group('SessionRunner PhrasePlayer integration', () {
    late SilentPhrasePlayer phrasePlayer;
    late SessionRunner runner;
    late _TestCognitiveGame game;

    setUp(() {
      final db = newTestDb();
      final content = GameContent(version: '1', marketItems: const []);
      phrasePlayer = SilentPhrasePlayer();
      runner = SessionRunner(
        eventRepo: EventRepo(db),
        abilityRepo: AbilityRepo(db),
        content: content,
        phrasePlayer: phrasePlayer,
      );
      game = _TestCognitiveGame('market_basket');
    });

    tearDown(() async {
      await game.dispose();
    });

    test('plays sessionStart on start, feedback on trials, and sessionEnd on end',
        () async {
      await runner.start([game]);
      expect(phrasePlayer.playedPhrases, [PhraseKey.sessionStart]);

      final item1 = await runner.nextItem(game);
      expect(item1, isNotNull);

      // Correct trial -> wellDone phrase
      final f1 = runner.feedback.first;
      game.emitResult(
        const TrialResult(
          correct: true,
          itemDifficulty: 0.5,
          initiationMs: 200,
          movementMs: 300,
        ),
      );
      await f1;

      final item2 = await runner.nextItem(game);
      expect(item2, isNotNull);

      // Incorrect trial -> tryAnother phrase (neutral encouragement)
      final f2 = runner.feedback.first;
      game.emitResult(
        const TrialResult(
          correct: false,
          itemDifficulty: 0.5,
          initiationMs: 250,
          movementMs: 400,
        ),
      );
      await f2;

      expect(phrasePlayer.playedPhrases, [
        PhraseKey.sessionStart,
        PhraseKey.wellDone,
        PhraseKey.tryAnother,
      ]);

      await runner.end(completed: true);
      expect(phrasePlayer.playedPhrases, [
        PhraseKey.sessionStart,
        PhraseKey.wellDone,
        PhraseKey.tryAnother,
        PhraseKey.sessionEnd,
      ]);
    });
  });
}
