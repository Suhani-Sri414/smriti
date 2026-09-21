import 'package:flutter_test/flutter_test.dart';
import 'package:smriti/core/ability/estimator.dart';
import 'package:smriti/core/db/database.dart';
import 'package:smriti/core/progression/play_policy.dart';
import 'package:smriti/core/progression/progression_config.dart';
import 'package:smriti/core/progression/progression_state.dart';

void main() {
  group('PlayPolicy (Fatigue & Variety Management)', () {
    final now = DateTime(2026, 9, 20, 14, 0);

    test('8-minute session contribution cap prevents runaway timers', () {
      final sessions = [
        Session(
          id: 's1',
          startedAt: 1000000,
          endedAt: 1000000 + (15 * 60 * 1000), // 15 min session
          gameIds: 'market_basket',
          completed: true,
          synced: true,
          demoReplays: 0,
        ),
        Session(
          id: 's2',
          startedAt: 2000000,
          endedAt: 2000000 + (5 * 60 * 1000), // 5 min session
          gameIds: 'trace_path',
          completed: true,
          synced: true,
          demoReplays: 0,
        ),
      ];

      // s1 capped at 8 min (480s), s2 contributes 5 min (300s) -> 780s total
      final total =
          PlayPolicy.calculateCappedPlaySecondsToday(todaySessions: sessions);
      expect(total, 480 + 300);
    });

    test('prompts rest card at 30 minutes cumulative play', () {
      // 25 minutes play: no prompt
      var state = const RestState(
        dateKey: '2026-09-20',
        playSecondsToday: 25 * 60,
      );
      var eval = PlayPolicy.evaluateRestCard(state: state, now: now);
      expect(eval.status, RestCardStatus.none);

      // 30 minutes play: triggers prompt
      state = state.copyWith(playSecondsToday: 30 * 60);
      eval = PlayPolicy.evaluateRestCard(state: state, now: now);
      expect(eval.status, RestCardStatus.showPrompt);
    });

    test('15-minute snooze interval after "Keep playing"', () {
      // Prompt was shown at 30 min (1800s)
      final state = const RestState(
        dateKey: '2026-09-20',
        playSecondsToday: 35 * 60, // 35 min (+5 min additional)
        lastPromptPlaySeconds: 30 * 60,
        keepPlayingCount: 1,
      );

      final eval1 = PlayPolicy.evaluateRestCard(state: state, now: now);
      expect(eval1.status, RestCardStatus.none); // Not yet +15 min

      // Now at 45 min (+15 min additional) -> triggers next prompt
      final state45 = state.copyWith(playSecondsToday: 45 * 60);
      final eval2 = PlayPolicy.evaluateRestCard(state: state45, now: now);
      expect(eval2.status, RestCardStatus.showPrompt);
    });

    test('3 overrides trigger gentle 3-hour eye-break lock', () {
      final state = const RestState(
        dateKey: '2026-09-20',
        playSecondsToday: 60 * 60,
        lastPromptPlaySeconds: 60 * 60,
        keepPlayingCount: 3, // 3 overrides
      );

      final eval = PlayPolicy.evaluateRestCard(state: state, now: now);
      expect(eval.status, RestCardStatus.locked);
      expect(eval.lockUntil, now.add(ProgressionConfig.gameLockDuration));
    });

    test('Variety Nudge triggers on >= 60% play dominance and recommends least-played domain', () {
      // 10 total sessions: 7 market_basket (70% >= 60%), 3 trace_path
      final sessions = [
        for (int i = 0; i < 7; i++)
          Session(
            id: 's_mb_$i',
            startedAt: 1000 + i * 100,
            endedAt: 1050 + i * 100,
            gameIds: 'market_basket',
            completed: true,
            synced: true,
            demoReplays: 0,
          ),
        for (int i = 0; i < 3; i++)
          Session(
            id: 's_tp_$i',
            startedAt: 2000 + i * 100,
            endedAt: 2050 + i * 100,
            gameIds: 'trace_path',
            completed: true,
            synced: true,
            demoReplays: 0,
          ),
      ];

      final gameDomainMapping = {
        'market_basket': CognitiveDomain.memory,
        'trace_path': CognitiveDomain.visuospatial,
        'sort_harvest': CognitiveDomain.executive,
        'lamps_festival': CognitiveDomain.memory,
        'sounds_home': CognitiveDomain.attention,
      };

      final lastPlayed = {
        CognitiveDomain.memory: now,
        CognitiveDomain.visuospatial: now.subtract(const Duration(hours: 1)),
        CognitiveDomain.executive: now.subtract(const Duration(days: 2)),
        CognitiveDomain.attention: null, // Never played!
        CognitiveDomain.language: now.subtract(const Duration(days: 1)),
      };

      final defaultGamePerDomain = {
        CognitiveDomain.memory: 'market_basket',
        CognitiveDomain.visuospatial: 'trace_path',
        CognitiveDomain.executive: 'sort_harvest',
        CognitiveDomain.attention: 'sounds_home',
        CognitiveDomain.language: 'market_basket',
      };

      final nudge = PlayPolicy.evaluateVarietyNudge(
        recentSessions: sessions,
        nudgeState: const NudgeState(),
        now: now,
        gameDomainMapping: gameDomainMapping,
        lastPlayedPerDomain: lastPlayed,
        defaultGamePerDomain: defaultGamePerDomain,
      );

      expect(nudge.shouldNudge, isTrue);
      expect(nudge.dominantGameId, 'market_basket');
      // Attention was never played, so it must be recommended
      expect(nudge.recommendedDomain, CognitiveDomain.attention);
      expect(nudge.recommendedGameId, 'sounds_home');
    });
  });
}
