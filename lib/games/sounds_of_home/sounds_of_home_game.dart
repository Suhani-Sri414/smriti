import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/ability/estimator.dart';
import '../cognitive_game.dart';
import '../ghost_hand.dart';

/// One environmental sound used in Sounds of Home.
class HomeSound {
  const HomeSound({
    required this.id,
    required this.label,
    required this.category,
    required this.icon,
    required this.description,
    this.color = const Color(0xFF9A6C17),
  });

  final String id;
  final String label;
  final String category; // 'nature', 'kitchen', 'animals', 'community', 'craft'
  final IconData icon;
  final String description;
  final Color color;
}

/// Sounds of Home: Auditory attention & environmental sound identification.
///
/// Primary domain: Attention (auditory selective attention & discrimination).
/// The elder listens to familiar domestic and regional sounds, and selects
/// the source from 3 clear, illustrated cards.
///
/// Spec adherence:
/// - `itemId`: `targetSoundId`
/// - `errorClass`: `semantic` if a sound from the same environmental category
///   is selected, `random` otherwise.
/// - `metrics`: `{"category": target.category, "distractorCount": 2}`.
class SoundsOfHomeGame implements CognitiveGame {
  SoundsOfHomeGame({
    List<HomeSound>? soundList,
    Random? random,
    GhostHandController? ghostHand,
  })  : sounds = (soundList != null && soundList.length >= 3)
            ? soundList
            : defaultSounds,
        _random = random ?? Random(),
        ghostHand = ghostHand ?? GhostHandController();

  final List<HomeSound> sounds;
  final Random _random;
  final GhostHandController ghostHand;
  final _trials = StreamController<TrialResult>.broadcast();

  @override
  String get id => 'sounds_of_home';

  @override
  CognitiveDomain get primaryDomain => CognitiveDomain.attention;

  @override
  PhraseKey get introPhrase => PhraseKey.soundsIntro;

  @override
  Stream<TrialResult> get trials => _trials.stream;

  static const List<HomeSound> defaultSounds = [
    HomeSound(
      id: 'rooster',
      label: 'Rooster Crowing',
      category: 'animals',
      icon: Icons.wb_sunny_rounded,
      description: 'Morning wake-up call at sunrise',
      color: Color(0xFFC85A17),
    ),
    HomeSound(
      id: 'temple_bell',
      label: 'Temple Bell',
      category: 'community',
      icon: Icons.notifications_active_rounded,
      description: 'Evening prayer bell chime',
      color: Color(0xFFB57C1E),
    ),
    HomeSound(
      id: 'tin_rain',
      label: 'Rain on Tin Roof',
      category: 'nature',
      icon: Icons.water_drop_rounded,
      description: 'Gentle monsoon rain shower',
      color: Color(0xFF2C6B8D),
    ),
    HomeSound(
      id: 'tea_kettle',
      label: 'Tea Kettle Whistle',
      category: 'kitchen',
      icon: Icons.local_cafe_rounded,
      description: 'Water boiling for morning chai',
      color: Color(0xFF8A3C23),
    ),
    HomeSound(
      id: 'handloom',
      label: 'Handloom Weaving',
      category: 'craft',
      icon: Icons.texture_rounded,
      description: 'Rhythmic click-clack of loom shuttle',
      color: Color(0xFF2B4C38),
    ),
    HomeSound(
      id: 'train_whistle',
      label: 'Train Whistle',
      category: 'community',
      icon: Icons.train_rounded,
      description: 'Train horn echoing in distance',
      color: Color(0xFF4A3469),
    ),
    HomeSound(
      id: 'birds',
      label: 'Birds Singing',
      category: 'animals',
      icon: Icons.flutter_dash_rounded,
      description: 'Myna birds chirping in garden',
      color: Color(0xFF386144),
    ),
    HomeSound(
      id: 'mortar_pestle',
      label: 'Mortar & Pestle',
      category: 'kitchen',
      icon: Icons.kitchen_rounded,
      description: 'Grinding spices for dinner',
      color: Color(0xFF6B4226),
    ),
  ];

  @override
  Future<void> playDemo(BuildContext context) {
    return ghostHand.play(const [
      Offset(0.5, 0.4),
      Offset(0.5, 0.8),
    ]);
  }

  @override
  GameItem generateItem(double difficulty, GameContent content) {
    // Pick target sound
    final targetIndex = _random.nextInt(sounds.length);
    final target = sounds[targetIndex];

    final candidatePool =
        sounds.where((s) => s.id != target.id).toList()..shuffle(_random);

    List<HomeSound> distractors;
    if (difficulty >= 0.5) {
      final sameCategory =
          candidatePool.where((s) => s.category == target.category).toList();
      if (sameCategory.isNotEmpty) {
        final dist1 = sameCategory.first;
        final remaining =
            candidatePool.where((s) => s.id != dist1.id).toList();
        distractors = [dist1, remaining.first];
      } else {
        distractors = candidatePool.take(2).toList();
      }
    } else {
      // Lower difficulty -> distractors from different categories
      final differentCategory =
          candidatePool.where((s) => s.category != target.category).toList();
      if (differentCategory.length >= 2) {
        distractors = differentCategory.take(2).toList();
      } else {
        distractors = candidatePool.take(2).toList();
      }
    }

    final options = [target, ...distractors]..shuffle(_random);

    return GameItem(
      id: target.id,
      difficulty: difficulty,
      context: {
        'targetId': target.id,
        'targetLabel': target.label,
        'category': target.category,
        'distractorIds': distractors.map((d) => d.id).toList(),
      },
      payload: {
        'target': target,
        'options': options,
      },
    );
  }

  /// Evaluates the elder's choice and emits a [TrialResult].
  void submitChoice({
    required GameItem item,
    required String chosenId,
    required int initiationMs,
    required int movementMs,
  }) {
    final target = item.payload['target'] as HomeSound;
    final isCorrect = chosenId == target.id;

    String? errorClass;
    if (!isCorrect) {
      final chosen = sounds.firstWhere(
        (s) => s.id == chosenId,
        orElse: () => HomeSound(
          id: chosenId,
          label: '',
          category: '',
          icon: Icons.help_outline,
          description: '',
        ),
      );
      if (chosen.category == target.category) {
        errorClass = 'semantic';
      } else {
        errorClass = 'random';
      }
    }

    _trials.add(
      TrialResult(
        correct: isCorrect,
        itemDifficulty: item.difficulty,
        initiationMs: initiationMs,
        movementMs: movementMs,
        chosenId: isCorrect ? null : chosenId,
        errorClass: errorClass,
        metrics: {
          'targetId': target.id,
          'chosenId': chosenId,
          'category': target.category,
        },
      ),
    );
  }

  void dispose() {
    _trials.close();
    ghostHand.dispose();
  }
}
