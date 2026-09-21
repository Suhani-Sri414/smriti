import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';

import '../../core/ability/estimator.dart';
import '../../core/progression/game_level_profiles.dart';
import '../../core/progression/level_scale.dart';
import '../cognitive_game.dart';
import '../ghost_hand.dart';

/// Market Basket: the elder is shown a short shopping list, the list is hidden,
/// then they pick those things off the market shelf.
///
/// Primary domain is memory - the load is holding the list across the delay.
/// Difficulty raises the list length first, then the number of same-category
/// distractors on the shelf, since a distractor from the same category is much
/// harder to reject than one from a different aisle.
///
/// This game never touches Drift or Supabase. It generates items on request and
/// emits [TrialResult]s (AGENTS.md #10).
class MarketBasketGame implements CognitiveGame {
  MarketBasketGame({Random? random, GhostHandController? ghostHand})
      : _random = random ?? Random(),
        ghostHand = ghostHand ?? GhostHandController();

  final Random _random;
  final GhostHandController ghostHand;
  final _trials = StreamController<TrialResult>.broadcast();

  @override
  String get id => 'market_basket';

  @override
  CognitiveDomain get primaryDomain => CognitiveDomain.memory;

  @override
  PhraseKey get introPhrase => PhraseKey.marketBasketIntro;

  @override
  Stream<TrialResult> get trials => _trials.stream;

  /// Ghost hand traces: look at the list, then tap two things on the shelf.
  @override
  Future<void> playDemo(BuildContext context) {
    return ghostHand.play(const [
      Offset(0.5, 0.2),
      Offset(0.3, 0.7),
      Offset(0.7, 0.7),
    ]);
  }

  /// List length for a given difficulty, held to a humane range.
  static int listLengthFor(double difficulty) {
    final effectiveLevel = difficulty > 2.5
        ? difficulty
        : LevelScale.difficultyToLevel(difficulty);
    final params = GameLevelProfiles.marketBasket.paramsAt(effectiveLevel);
    return (params['targetCount'] ?? (3 + difficulty.round()))
        .toInt()
        .clamp(2, 6);
  }

  /// Extra same-category items on the shelf, which are the hard distractors.
  static int nearDistractorsFor(double difficulty) {
    final effectiveLevel = difficulty > 2.5
        ? difficulty
        : LevelScale.difficultyToLevel(difficulty);
    final params = GameLevelProfiles.marketBasket.paramsAt(effectiveLevel);
    final poolSize = (params['poolSize'] ?? 4).toInt();
    final targetCount = (params['targetCount'] ?? 2).toInt();
    return (poolSize - targetCount - 2).clamp(0, 3);
  }

  @override
  GameItem generateItem(double difficulty, GameContent content) {
    final catalogue = content.marketItems;
    if (catalogue.isEmpty) {
      throw StateError('Market Basket needs at least one item in content');
    }

    final listLength = min(listLengthFor(difficulty), catalogue.length);
    final pool = [...catalogue]..shuffle(_random);
    final target = pool.take(listLength).toList(growable: false);

    final targetIds = target.map((i) => i.id).toSet();
    final targetCategories = target.map((i) => i.category).toSet();

    final remaining =
        pool.where((i) => !targetIds.contains(i.id)).toList(growable: false);
    final near = remaining
        .where((i) => targetCategories.contains(i.category))
        .take(nearDistractorsFor(difficulty))
        .toList(growable: false);
    final nearIds = near.map((i) => i.id).toSet();
    final far = remaining
        .where((i) => !nearIds.contains(i.id))
        .take(max(0, listLength + 2 - near.length))
        .toList(growable: false);

    final shelf = [...target, ...near, ...far]..shuffle(_random);

    return GameItem(
      id: 'mb_${target.map((i) => i.id).join('-')}',
      difficulty: difficulty,
      // Everything the report pipeline needs to reconstruct the trial.
      context: {
        'listLength': listLength,
        'shelfSize': shelf.length,
        'nearDistractors': near.length,
        'farDistractors': far.length,
        'targetIds': target.map((i) => i.id).toList(),
        'contentVersion': content.version,
      },
      payload: {
        'target': target,
        'shelf': shelf,
      },
    );
  }

  /// Called by the widget layer when the elder finishes picking.
  ///
  /// [initiationMs] is time to first touch, [movementMs] the time spent
  /// picking after that; the runner sums them into `responseTimeMs`.
  void submit({
    required GameItem item,
    required List<String> chosenIds,
    required int initiationMs,
    required int movementMs,
  }) {
    final targetIds =
        (item.context['targetIds']! as List<Object?>).cast<String>().toSet();
    final shelf = (item.payload['shelf']! as List<Object?>).cast<MarketItem>();
    final byId = {for (final i in shelf) i.id: i};

    final chosen = chosenIds.toSet();
    final missed = targetIds.difference(chosen);
    final intrusions = chosen.difference(targetIds);
    final repeats = chosenIds.length - chosen.length;

    final correct = missed.isEmpty && intrusions.isEmpty;

    // What the elder actually picked wrongly, and how wrong it was.
    String? chosenId;
    String? errorClass;
    if (!correct) {
      if (intrusions.isNotEmpty) {
        chosenId = intrusions.first;
        final targetCategories =
            targetIds.map((id) => byId[id]?.category).toSet();
        errorClass = targetCategories.contains(byId[chosenId]?.category)
            ? 'semantic_near'
            : 'semantic_far';
      } else {
        // Nothing wrong was picked, the list was just incomplete.
        chosenId = missed.first;
        errorClass = 'omission';
      }
      if (repeats > 0) errorClass = 'perseveration';
    }

    _trials.add(
      TrialResult(
        correct: correct,
        itemDifficulty: item.difficulty,
        initiationMs: initiationMs,
        movementMs: movementMs,
        chosenId: chosenId,
        errorClass: errorClass,
        metrics: {
          'picked': chosenIds.length,
          'targets': targetIds.length,
          'missed': missed.length,
          'intrusions': intrusions.length,
          'repeats': repeats,
        },
      ),
    );
  }

  Future<void> dispose() => _trials.close();
}
