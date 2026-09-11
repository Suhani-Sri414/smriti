import 'package:flutter/widgets.dart';

import '../core/ability/estimator.dart';

/// Keys for pre-recorded voice phrases. The voice layer (task A16) maps these
/// to audio files in the active language pack; nothing here ever synthesises or
/// displays raw text to the elder.
enum PhraseKey {
  sessionStart,
  sessionEnd,
  marketBasketIntro,
  sortTheHarvestIntro,
  facesIntro,
  soundsIntro,
  tryAnother,
  wellDone,
}

/// One playable item generated for a trial.
///
/// [context] is serialised into `TrialEvents.trialContext`, so it must hold
/// whatever the report pipeline needs to reconstruct what the elder was shown
/// (list length, distractor count, and so on). [payload] carries game-specific
/// data for the widget layer and is never persisted directly.
class GameItem {
  const GameItem({
    required this.id,
    required this.difficulty,
    this.context = const {},
    this.payload = const {},
  });

  final String id;
  final double difficulty;
  final Map<String, Object?> context;
  final Map<String, Object?> payload;
}

/// What a game emits when the elder finishes a trial.
///
/// Exactly the fields listed in APP-BUILD-SPEC.md §11. Games never supply
/// `itemId`, `trialIndex`, `hintLevel` or any timestamp — the session runner
/// owns those, because it owns the session.
class TrialResult {
  const TrialResult({
    required this.correct,
    required this.itemDifficulty,
    required this.initiationMs,
    required this.movementMs,
    this.chosenId,
    this.errorClass,
    this.metrics = const {},
  });

  /// Time from item presented to first touch — the decision component.
  final int initiationMs;

  /// Time from first touch to committed answer — the motor component.
  final int movementMs;

  final bool correct;
  final double itemDifficulty;

  /// What the elder actually chose when [correct] is false.
  final String? chosenId;

  /// Coarse category of the mistake, for the report pipeline.
  final String? errorClass;

  final Map<String, Object?> metrics;
}

/// Content a game draws its items from. Today this is loaded from the mock
/// content JSON; from task A09 onward `ContentPuller` populates the same shape
/// from Drift.
class GameContent {
  const GameContent({
    required this.version,
    required this.marketItems,
  });

  factory GameContent.fromJson(Map<String, Object?> json) {
    final items = (json['marketItems'] as List<Object?>? ?? const [])
        .cast<Map<String, Object?>>()
        .map(MarketItem.fromJson)
        .toList(growable: false);
    return GameContent(
      version: json['version'] as String? ?? 'unknown',
      marketItems: items,
    );
  }

  final String version;
  final List<MarketItem> marketItems;
}

/// A single purchasable thing on the market shelf.
class MarketItem {
  const MarketItem({
    required this.id,
    required this.labelKey,
    required this.iconAsset,
    required this.category,
  });

  factory MarketItem.fromJson(Map<String, Object?> json) => MarketItem(
        id: json['id'] as String,
        labelKey: json['labelKey'] as String,
        iconAsset: json['iconAsset'] as String,
        category: json['category'] as String,
      );

  final String id;
  final String labelKey;
  final String iconAsset;

  /// Used to classify a wrong pick as semantically near or far.
  final String category;
}

/// The contract every game implements, per APP-BUILD-SPEC.md §11.
///
/// Games never touch Drift or Supabase (AGENTS.md non-negotiable #10). They
/// generate items on request and emit [TrialResult]s; the session runner owns
/// all persistence.
abstract class CognitiveGame {
  String get id;
  CognitiveDomain get primaryDomain;
  PhraseKey get introPhrase;

  /// Ghost-hand demonstration of how to play.
  Future<void> playDemo(BuildContext context);

  GameItem generateItem(double difficulty, GameContent content);

  Stream<TrialResult> get trials;
}
