import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/ability/estimator.dart';
import '../cognitive_game.dart';
import '../ghost_hand.dart';

/// One produce item to be sorted in Sort the Harvest.
class SortCrop {
  const SortCrop({
    required this.id,
    required this.name,
    required this.category,
    required this.colorName,
    required this.color,
    required this.icon,
  });

  final String id;
  final String name;
  final String category; // 'grain', 'spice', 'vegetable'
  final String colorName; // 'green', 'yellow', 'red'
  final Color color;
  final IconData icon;
}

/// A target sorting basket/tray.
class SortTray {
  const SortTray({
    required this.id,
    required this.label,
    required this.ruleType,
    required this.ruleValue,
    required this.color,
  });

  final String id;
  final String label;
  final String ruleType; // 'color' or 'category'
  final String ruleValue;
  final Color color;
}

/// Sort the Harvest: Wisconsin card sorting analogue adapted for rural elders.
///
/// Primary domain: Executive function (set-shifting, cognitive flexibility).
/// The elder sorts regional produce into trays. An implicit sorting rule
/// (by color or by category) is active. After a sequence of correct sorts,
/// the rule shifts, requiring the elder to shift cognitive sets.
///
/// Spec table:
/// - `itemId`: `ruleId_itemId`
/// - `errorClass`: `perseverative` if sorted according to the old rule,
///   `random` otherwise.
/// - `metrics`: `{"switch_cost_ms": n, "rule": currentRule}`.
class SortTheHarvestGame implements CognitiveGame {
  SortTheHarvestGame({Random? random, GhostHandController? ghostHand})
      : _random = random ?? Random(),
        ghostHand = ghostHand ?? GhostHandController();

  final Random _random;
  final GhostHandController ghostHand;
  final _trials = StreamController<TrialResult>.broadcast();

  @override
  String get id => 'sort_the_harvest';

  @override
  CognitiveDomain get primaryDomain => CognitiveDomain.executive;

  @override
  PhraseKey get introPhrase => PhraseKey.sortTheHarvestIntro;

  @override
  Stream<TrialResult> get trials => _trials.stream;

  static const List<SortCrop> defaultCrops = [
    SortCrop(
      id: 'paddy',
      name: 'Paddy',
      category: 'grain',
      colorName: 'yellow',
      color: Color(0xFFD9A036),
      icon: Icons.grass_rounded,
    ),
    SortCrop(
      id: 'mustard',
      name: 'Mustard',
      category: 'grain',
      colorName: 'yellow',
      color: Color(0xFFE2B024),
      icon: Icons.grain_rounded,
    ),
    SortCrop(
      id: 'red_chili',
      name: 'Red Chili',
      category: 'spice',
      colorName: 'red',
      color: Color(0xFFC8382B),
      icon: Icons.local_fire_department_rounded,
    ),
    SortCrop(
      id: 'ginger',
      name: 'Ginger',
      category: 'spice',
      colorName: 'yellow',
      color: Color(0xFFC29B38),
      icon: Icons.spa_rounded,
    ),
    SortCrop(
      id: 'bamboo',
      name: 'Bamboo Shoot',
      category: 'vegetable',
      colorName: 'green',
      color: Color(0xFF4A8C4B),
      icon: Icons.forest_rounded,
    ),
    SortCrop(
      id: 'cabbage',
      name: 'Cabbage',
      category: 'vegetable',
      colorName: 'green',
      color: Color(0xFF388E3C),
      icon: Icons.eco_rounded,
    ),
    SortCrop(
      id: 'tomato',
      name: 'Tomato',
      category: 'vegetable',
      colorName: 'red',
      color: Color(0xFFD32F2F),
      icon: Icons.circle_rounded,
    ),
  ];

  String _currentRule = 'category'; // 'category' or 'color'
  String? _previousRule;
  int _consecutiveCorrect = 0;
  DateTime? _ruleShiftedAt;

  String get currentRule => _currentRule;
  String? get previousRule => _previousRule;

  @override
  Future<void> playDemo(BuildContext context) {
    return ghostHand.play(const [
      Offset(0.5, 0.4),
      Offset(0.3, 0.75),
    ]);
  }

  @override
  GameItem generateItem(double difficulty, GameContent content) {
    // Shift rule after 3-5 consecutive correct trials
    final shiftThreshold = (4 - (difficulty.round() % 2)).clamp(3, 5);
    if (_consecutiveCorrect >= shiftThreshold) {
      _previousRule = _currentRule;
      _currentRule = _currentRule == 'category' ? 'color' : 'category';
      _consecutiveCorrect = 0;
      _ruleShiftedAt = DateTime.now();
    }

    // Pick target crop
    final crop = defaultCrops[_random.nextInt(defaultCrops.length)];

    // Generate trays
    final List<SortTray> trays;
    if (_currentRule == 'category') {
      trays = const [
        SortTray(
          id: 'tray_vegetable',
          label: 'Vegetables',
          ruleType: 'category',
          ruleValue: 'vegetable',
          color: Color(0xFF3B7A57),
        ),
        SortTray(
          id: 'tray_spice',
          label: 'Spices',
          ruleType: 'category',
          ruleValue: 'spice',
          color: Color(0xFFB85D2A),
        ),
        SortTray(
          id: 'tray_grain',
          label: 'Grains',
          ruleType: 'category',
          ruleValue: 'grain',
          color: Color(0xFFD49C24),
        ),
      ];
    } else {
      trays = const [
        SortTray(
          id: 'tray_green',
          label: 'Green',
          ruleType: 'color',
          ruleValue: 'green',
          color: Color(0xFF388E3C),
        ),
        SortTray(
          id: 'tray_yellow',
          label: 'Golden / Yellow',
          ruleType: 'color',
          ruleValue: 'yellow',
          color: Color(0xFFD4A024),
        ),
        SortTray(
          id: 'tray_red',
          label: 'Red',
          ruleType: 'color',
          ruleValue: 'red',
          color: Color(0xFFC62828),
        ),
      ];
    }

    final targetTray = trays.firstWhere(
      (t) => _currentRule == 'category'
          ? t.ruleValue == crop.category
          : t.ruleValue == crop.colorName,
      orElse: () => trays.first,
    );

    return GameItem(
      id: '${_currentRule}_${crop.id}',
      difficulty: difficulty,
      context: {
        'rule': _currentRule,
        'cropId': crop.id,
        'cropName': crop.name,
        'cropCategory': crop.category,
        'cropColor': crop.colorName,
        'targetTrayId': targetTray.id,
        'previousRule': _previousRule,
      },
      payload: {
        'crop': crop,
        'trays': trays,
        'targetTray': targetTray,
      },
    );
  }

  void submitSort({
    required GameItem item,
    required String chosenTrayId,
    required int initiationMs,
    required int movementMs,
  }) {
    final crop = item.payload['crop'] as SortCrop;
    final targetTray = item.payload['targetTray'] as SortTray;
    final trays = (item.payload['trays'] as List<Object?>).cast<SortTray>();

    final correct = chosenTrayId == targetTray.id;

    if (correct) {
      _consecutiveCorrect++;
    } else {
      _consecutiveCorrect = 0;
    }

    // Check error classification:
    // If wrong, was it perseverative (i.e. matching the old rule)?
    String? errorClass;
    if (!correct) {
      final chosenTray = trays.firstWhere(
        (t) => t.id == chosenTrayId,
        orElse: () => targetTray,
      );

      bool isPerseverative = false;
      if (_previousRule != null) {
        if (_previousRule == 'category' &&
            chosenTray.ruleValue == crop.category) {
          isPerseverative = true;
        } else if (_previousRule == 'color' &&
            chosenTray.ruleValue == crop.colorName) {
          isPerseverative = true;
        }
      }

      errorClass = isPerseverative ? 'perseverative' : 'random';
    }

    // Switch cost in ms if this was shortly after a rule switch
    int? switchCostMs;
    if (_ruleShiftedAt != null) {
      final elapsedSinceShift =
          DateTime.now().difference(_ruleShiftedAt!).inMilliseconds;
      if (elapsedSinceShift < 15000) {
        switchCostMs = initiationMs;
      }
    }

    final metrics = <String, Object?>{
      'rule': _currentRule,
      if (switchCostMs != null) 'switch_cost_ms': switchCostMs,
      if (errorClass != null) 'error_class': errorClass,
    };

    _trials.add(
      TrialResult(
        correct: correct,
        itemDifficulty: item.difficulty,
        initiationMs: initiationMs,
        movementMs: movementMs,
        chosenId: chosenTrayId,
        errorClass: errorClass,
        metrics: metrics,
      ),
    );
  }

  void dispose() {
    _trials.close();
  }
}
