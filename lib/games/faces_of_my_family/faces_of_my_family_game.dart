import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/ability/estimator.dart';
import '../cognitive_game.dart';
import '../ghost_hand.dart';

/// A person/relative used in Faces of My Family.
class FamilyPerson {
  const FamilyPerson({
    required this.id,
    required this.name,
    required this.relationship,
    this.photoPath,
    this.avatarColor = const Color(0xFF213A5C),
    this.generation = 1,
    this.gender = 'female',
    this.memoryPrompt,
  });

  final String id;
  final String name;
  final String relationship;
  final String? photoPath;
  final Color avatarColor;
  final int generation; // 0 = peer/spouse, 1 = children, 2 = grandchildren
  final String gender; // 'female' or 'male'
  final String? memoryPrompt;

  String get label => '$name ($relationship)';
}

/// Faces of My Family: Long-term / semantic family recognition game.
///
/// Primary domain: Memory (long-term semantic face-name association).
/// The elder is shown a familiar family member's portrait or avatar and chooses
/// who it is from 3 large, accessible candidate cards.
///
/// Spec adherence:
/// - `itemId`: `targetPersonId`
/// - `errorClass`: `semantic` if a family member from the same generation or
///   gender is selected, `random` otherwise.
/// - `metrics`: details target, chosen, relationship, and generation.
class FacesOfMyFamilyGame implements CognitiveGame {
  FacesOfMyFamilyGame({
    List<FamilyPerson>? people,
    Random? random,
    GhostHandController? ghostHand,
  })  : people = (people != null && people.length >= 3)
            ? people
            : defaultFamilyPeople,
        _random = random ?? Random(),
        ghostHand = ghostHand ?? GhostHandController();

  final List<FamilyPerson> people;
  final Random _random;
  final GhostHandController ghostHand;
  final _trials = StreamController<TrialResult>.broadcast();

  @override
  String get id => 'faces_of_my_family';

  @override
  CognitiveDomain get primaryDomain => CognitiveDomain.memory;

  @override
  PhraseKey get introPhrase => PhraseKey.facesIntro;

  @override
  Stream<TrialResult> get trials => _trials.stream;

  static const List<FamilyPerson> defaultFamilyPeople = [
    FamilyPerson(
      id: 'bina',
      name: 'Bina',
      relationship: 'Daughter',
      avatarColor: Color(0xFF213A5C),
      generation: 1,
      gender: 'female',
      memoryPrompt: 'Visited on Sunday with tea',
    ),
    FamilyPerson(
      id: 'thoibi',
      name: 'Thoibi',
      relationship: 'Granddaughter',
      avatarColor: Color(0xFF8A3C23),
      generation: 2,
      gender: 'female',
      memoryPrompt: 'Loves your handmade scarves',
    ),
    FamilyPerson(
      id: 'tomba',
      name: 'Tomba',
      relationship: 'Son',
      avatarColor: Color(0xFF2B4C38),
      generation: 1,
      gender: 'male',
      memoryPrompt: 'Calls every evening at 6',
    ),
    FamilyPerson(
      id: 'meera',
      name: 'Meera',
      relationship: 'Daughter',
      avatarColor: Color(0xFF8D5B1E),
      generation: 1,
      gender: 'female',
      memoryPrompt: 'Brings fresh mangoes from garden',
    ),
    FamilyPerson(
      id: 'chaoba',
      name: 'Chaoba',
      relationship: 'Grandson',
      avatarColor: Color(0xFF4A3469),
      generation: 2,
      gender: 'male',
      memoryPrompt: 'Studying in college in Imphal',
    ),
    FamilyPerson(
      id: 'sanatombi',
      name: 'Sanatombi',
      relationship: 'Sister',
      avatarColor: Color(0xFF2C5E6B),
      generation: 0,
      gender: 'female',
      memoryPrompt: 'Your elder sister in the village',
    ),
  ];

  @override
  Future<void> playDemo(BuildContext context) {
    return ghostHand.play(const [
      Offset(0.5, 0.45),
      Offset(0.25, 0.8),
    ]);
  }

  @override
  GameItem generateItem(double difficulty, GameContent content) {
    // Pick target person
    final targetIndex = _random.nextInt(people.length);
    final target = people[targetIndex];

    // Pick 2 distractors based on difficulty:
    // Higher difficulty -> distractors share generation or gender (harder semantic discrimination)
    // Lower difficulty -> distractors are clearly distinct
    final candidatePool =
        people.where((p) => p.id != target.id).toList()..shuffle(_random);

    List<FamilyPerson> distractors;
    if (difficulty >= 0.5) {
      final closeMatches = candidatePool
          .where((p) =>
              p.generation == target.generation || p.gender == target.gender)
          .toList();
      if (closeMatches.length >= 2) {
        distractors = closeMatches.take(2).toList();
      } else {
        distractors = candidatePool.take(2).toList();
      }
    } else {
      distractors = candidatePool.take(2).toList();
    }

    final options = [target, ...distractors]..shuffle(_random);

    return GameItem(
      id: target.id,
      difficulty: difficulty,
      context: {
        'targetId': target.id,
        'targetName': target.name,
        'targetRelationship': target.relationship,
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
    final target = item.payload['target'] as FamilyPerson;
    final isCorrect = chosenId == target.id;

    String? errorClass;
    if (!isCorrect) {
      final chosen = people.firstWhere(
        (p) => p.id == chosenId,
        orElse: () => FamilyPerson(id: chosenId, name: '', relationship: ''),
      );
      if (chosen.generation == target.generation ||
          chosen.gender == target.gender) {
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
          'targetRelationship': target.relationship,
          'targetGeneration': target.generation,
        },
      ),
    );
  }

  void dispose() {
    _trials.close();
    ghostHand.dispose();
  }
}
