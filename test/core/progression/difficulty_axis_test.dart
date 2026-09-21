import 'package:flutter_test/flutter_test.dart';
import 'package:smriti/core/progression/difficulty_axis.dart';
import 'package:smriti/core/progression/game_level_profiles.dart';
import 'package:smriti/core/progression/progression_config.dart';

void main() {
  group('DifficultyAxis & Monotonicity Verification', () {
    test('positive perLevel axis increases monotonically and never exceeds limit', () {
      const axis = DifficultyAxis(
        name: 'test_positive',
        start: 2.0,
        perLevel: 0.5,
        limit: 5.0,
        startLevel: 1.0,
      );

      double previous = -double.infinity;
      for (double l = 1.0; l <= 20.0; l += 0.5) {
        final val = axis.evaluate(l);
        expect(val, greaterThanOrEqualTo(previous),
            reason: 'Axis must not decrease at level $l');
        expect(val, lessThanOrEqualTo(axis.limit),
            reason: 'Axis must not exceed limit at level $l');
        previous = val;
      }

      // Beyond saturation level (1.0 + (5-2)/0.5 = 7.0), value should be pinned at limit
      expect(axis.saturationLevel, 7.0);
      expect(axis.evaluate(7.0), 5.0);
      expect(axis.evaluate(15.0), 5.0);
    });

    test('negative perLevel axis decreases monotonically and never falls below limit', () {
      const axis = DifficultyAxis(
        name: 'test_negative',
        start: 800.0,
        perLevel: -50.0,
        limit: 400.0,
        startLevel: 2.0,
      );

      double previous = double.infinity;
      for (double l = 1.0; l <= 20.0; l += 0.5) {
        final val = axis.evaluate(l);
        expect(val, lessThanOrEqualTo(previous),
            reason: 'Axis must not increase at level $l');
        expect(val, greaterThanOrEqualTo(axis.limit),
            reason: 'Axis must not drop below limit at level $l');
        previous = val;
      }

      // Below startLevel, value is start
      expect(axis.evaluate(1.0), 800.0);
      expect(axis.evaluate(2.0), 800.0);

      // Saturation level: 2.0 + (800 - 400)/50 = 10.0
      expect(axis.saturationLevel, 10.0);
      expect(axis.evaluate(10.0), 400.0);
      expect(axis.evaluate(15.0), 400.0);
    });

    test('respects AxisRounding modes', () {
      const floorAxis = DifficultyAxis(
        name: 'floor_axis',
        start: 2.0,
        perLevel: 0.40,
        limit: 6.0,
        rounding: AxisRounding.floor,
      );

      // L=1.0: 2.0 -> 2.0
      // L=2.0: 2.4 -> floor: 2.0
      // L=3.0: 2.8 -> floor: 2.0
      // L=4.0: 3.2 -> floor: 3.0
      expect(floorAxis.evaluate(1.0), 2.0);
      expect(floorAxis.evaluate(2.0), 2.0);
      expect(floorAxis.evaluate(3.0), 2.0);
      expect(floorAxis.evaluate(4.0), 3.0);

      const roundAxis = DifficultyAxis(
        name: 'round_axis',
        start: 0.0,
        perLevel: 0.75,
        limit: 5.0,
        startLevel: 3.0,
        rounding: AxisRounding.round,
      );

      // Below startLevel
      expect(roundAxis.evaluate(1.0), 0.0);
      expect(roundAxis.evaluate(2.0), 0.0);
      expect(roundAxis.evaluate(3.0), 0.0);
      // L=4.0: 0.75 -> round: 1.0
      expect(roundAxis.evaluate(4.0), 1.0);
      // L=5.0: 1.50 -> round: 2.0
      expect(roundAxis.evaluate(5.0), 2.0);
    });

    test('verifies all catalog game profiles maintain strict monotonicity and bounds', () {
      final profiles = [
        GameLevelProfiles.marketBasket,
        GameLevelProfiles.tracePath,
        GameLevelProfiles.sortHarvest,
        GameLevelProfiles.lampsFestival,
        GameLevelProfiles.soundsHome,
      ];

      for (final profile in profiles) {
        expect(profile.axes, isNotEmpty);
        expect(profile.plateauLevel,
            greaterThanOrEqualTo(ProgressionConfig.minLevel));
        expect(profile.maxAllowedLevel,
            profile.plateauLevel + ProgressionConfig.plateauHeadroom);

        for (final axis in profile.axes) {
          double? lastVal;
          for (double l = 1.0; l <= 20.0; l += 0.5) {
            final val = axis.evaluate(l);

            if (axis.perLevel > 0) {
              if (lastVal != null) {
                expect(val, greaterThanOrEqualTo(lastVal),
                    reason: '${profile.gameId}.${axis.name} decreased at L=$l');
              }
              expect(val, lessThanOrEqualTo(axis.limit),
                  reason: '${profile.gameId}.${axis.name} exceeded limit at L=$l');
            } else if (axis.perLevel < 0) {
              if (lastVal != null) {
                expect(val, lessThanOrEqualTo(lastVal),
                    reason: '${profile.gameId}.${axis.name} increased at L=$l');
              }
              expect(val, greaterThanOrEqualTo(axis.limit),
                  reason: '${profile.gameId}.${axis.name} dropped below limit at L=$l');
            }
            lastVal = val;
          }
        }
      }
    });

    test('LevelProfile paramsAt evaluates all axes into clean parameter map', () {
      final params = GameLevelProfiles.marketBasket.paramsAt(5.0);
      expect(params.containsKey('targetCount'), isTrue);
      expect(params.containsKey('poolSize'), isTrue);
      expect(params.containsKey('delaySeconds'), isTrue);

      expect(params['targetCount'], 3.0); // 2 + 0.4*4 = 3.6 -> floor: 3.0
      expect(params['poolSize'], 6.0); // 4 + 0.6*4 = 6.4 -> floor: 6.0
      expect(params['delaySeconds'], 2.0); // 0 + 0.75*2 = 1.5 -> round: 2.0
    });
  });
}
