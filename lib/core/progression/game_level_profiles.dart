import 'difficulty_axis.dart';

/// Declarative profiles for cognitive game archetypes.
///
/// Configured according to the specifications in PROGRESSION_SYSTEM_GUIDE.md §3.4.
class GameLevelProfiles {
  const GameLevelProfiles._();

  /// Market Basket (Memory)
  static const LevelProfile marketBasket = LevelProfile(
    gameId: 'market_basket',
    axes: [
      DifficultyAxis(
        name: 'targetCount',
        start: 2.0,
        perLevel: 0.40,
        limit: 6.0,
        startLevel: 1.0,
        rounding: AxisRounding.floor,
      ),
      DifficultyAxis(
        name: 'poolSize',
        start: 4.0,
        perLevel: 0.60,
        limit: 12.0,
        startLevel: 1.0,
        rounding: AxisRounding.floor,
      ),
      DifficultyAxis(
        name: 'delaySeconds',
        start: 0.0,
        perLevel: 0.75,
        limit: 5.0,
        startLevel: 3.0,
        rounding: AxisRounding.round,
      ),
    ],
  );

  /// Trace the Path (Visuospatial)
  static const LevelProfile tracePath = LevelProfile(
    gameId: 'trace_path',
    axes: [
      DifficultyAxis(
        name: 'nodeCount',
        start: 3.0,
        perLevel: 0.70,
        limit: 8.0,
        startLevel: 1.0,
        rounding: AxisRounding.floor,
      ),
      DifficultyAxis(
        name: 'decoyCount',
        start: 0.0,
        perLevel: 0.40,
        limit: 3.0,
        startLevel: 3.0,
        rounding: AxisRounding.floor,
      ),
    ],
  );

  /// Faces of My Family (Semantic Memory)
  static const LevelProfile facesOfFamily = LevelProfile(
    gameId: 'faces_of_my_family',
    axes: [
      DifficultyAxis(
        name: 'distractorSimilarity',
        start: 0.0,
        perLevel: 0.20,
        limit: 1.0,
        startLevel: 1.0,
        rounding: AxisRounding.none,
      ),
      DifficultyAxis(
        name: 'candidateCount',
        start: 2.0,
        perLevel: 0.25,
        limit: 4.0,
        startLevel: 1.0,
        rounding: AxisRounding.floor,
      ),
      DifficultyAxis(
        name: 'promptDelaySeconds',
        start: 0.0,
        perLevel: 0.5,
        limit: 3.0,
        startLevel: 3.0,
        rounding: AxisRounding.round,
      ),
    ],
  );

  /// Sort the Harvest (Executive)
  static const LevelProfile sortHarvest = LevelProfile(
    gameId: 'sort_the_harvest',
    axes: [
      DifficultyAxis(
        name: 'categoryCount',
        start: 2.0,
        perLevel: 0.25,
        limit: 4.0,
        startLevel: 1.0,
        rounding: AxisRounding.floor,
      ),
      DifficultyAxis(
        name: 'distractorRatio',
        start: 0.0,
        perLevel: 0.08,
        limit: 0.40,
        startLevel: 2.0,
        rounding: AxisRounding.none,
      ),
      DifficultyAxis(
        name: 'ruleShiftFrequency',
        start: 5.0,
        perLevel: -0.4,
        limit: 3.0,
        startLevel: 2.0,
        rounding: AxisRounding.floor,
      ),
    ],
  );

  /// Lamps Festival (Working Memory)
  static const LevelProfile lampsFestival = LevelProfile(
    gameId: 'lamps_festival',
    axes: [
      DifficultyAxis(
        name: 'sequenceSpan',
        start: 2.0,
        perLevel: 0.40,
        limit: 6.0,
        startLevel: 1.0,
        rounding: AxisRounding.floor,
      ),
      DifficultyAxis(
        name: 'flashDurationMs',
        start: 800.0,
        perLevel: -50.0,
        limit: 400.0,
        startLevel: 2.0,
        rounding: AxisRounding.round,
      ),
    ],
  );

  /// Sounds of Home (Attention)
  static const LevelProfile soundsHome = LevelProfile(
    gameId: 'sounds_of_home',
    axes: [
      DifficultyAxis(
        name: 'targetRatio',
        start: 0.60,
        perLevel: -0.04,
        limit: 0.30,
        startLevel: 1.0,
        rounding: AxisRounding.none,
      ),
      DifficultyAxis(
        name: 'interStimulusMs',
        start: 2200.0,
        perLevel: -150.0,
        limit: 1100.0,
        startLevel: 1.5,
        rounding: AxisRounding.round,
      ),
      DifficultyAxis(
        name: 'distractorSimilarity',
        start: 0.0,
        perLevel: 0.20,
        limit: 1.0,
        startLevel: 1.0,
        rounding: AxisRounding.none,
      ),
    ],
  );

  static final Map<String, LevelProfile> _catalog = {
    marketBasket.gameId: marketBasket,
    facesOfFamily.gameId: facesOfFamily,
    'faces_of_the_family': facesOfFamily,
    sortHarvest.gameId: sortHarvest,
    'sort_harvest': sortHarvest,
    soundsHome.gameId: soundsHome,
    'sounds_home': soundsHome,
    tracePath.gameId: tracePath,
    lampsFestival.gameId: lampsFestival,
  };

  /// Returns the catalog map of all registered profiles keyed by gameId.
  static Map<String, LevelProfile> get catalog => _catalog;

  /// Returns the configured profile for [gameId], or a fallback minimal profile
  /// if not explicitly defined in the catalog.
  static LevelProfile forGame(String gameId) {
    return _catalog[gameId] ??
        LevelProfile(
          gameId: gameId,
          axes: const [
            DifficultyAxis(
              name: 'difficulty',
              start: 1.0,
              perLevel: 1.0,
              limit: 10.0,
            ),
          ],
        );
  }

  /// Returns all unique registered profiles.
  static List<LevelProfile> get allProfiles =>
      {for (final p in _catalog.values) p.gameId: p}.values.toList();
}
