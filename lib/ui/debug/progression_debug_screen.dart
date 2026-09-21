import 'dart:convert';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../app_colors.dart';
import '../../core/ability/estimator.dart';
import '../../core/app_services.dart';
import '../../core/db/database.dart';
import '../../core/progression/game_level_profiles.dart';
import '../../core/progression/level_scale.dart';
import '../../core/progression/play_policy.dart';
import '../../core/progression/progression_service.dart';
import '../../core/progression/progression_state.dart';

/// Developer Debug UI for testing progression, forced reviews, and fatigue states.
class ProgressionDebugScreen extends StatefulWidget {
  const ProgressionDebugScreen({super.key, required this.services});

  final AppServices services;

  @override
  State<ProgressionDebugScreen> createState() => _ProgressionDebugScreenState();
}

class _ProgressionDebugScreenState extends State<ProgressionDebugScreen> {
  static const _uuid = Uuid();

  bool _loading = false;
  String? _lastReviewSummary;

  // Live state
  final Map<String, GameProgress> _gameProgresses = {};
  RestState? _restState;
  VarietyNudgeEvaluation? _nudgeEval;

  @override
  void initState() {
    super.initState();
    _refreshState();
  }

  Future<void> _refreshState() async {
    setState(() => _loading = true);
    try {
      final repo = widget.services.progressionRepo;
      final service = widget.services.progressionService;
      final now = DateTime.now();

      final uniqueGameIds = GameLevelProfiles.allProfiles.map((p) => p.gameId).toList();
      for (final gameId in uniqueGameIds) {
        final progress = await repo.getGameProgress(gameId);
        _gameProgresses[gameId] = progress;
      }

      final rest = await repo.getRestState(now: now);
      final nudge = await service.checkVarietyNudge(currentTime: now);

      if (mounted) {
        setState(() {
          _restState = rest;
          _nudgeEval = nudge;
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // --- Section A: Simulate Trials ---

  Future<void> _simulatePlay({
    required String gameId,
    required bool isPerfect,
  }) async {
    setState(() => _loading = true);
    try {
      final db = widget.services.db;
      final now = DateTime.now();
      final sessionId = 'debug_${isPerfect ? 'perf' : 'poor'}_${now.millisecondsSinceEpoch}';

      // Insert dummy session
      await db.into(db.sessions).insert(
            SessionsCompanion.insert(
              id: sessionId,
              startedAt: now.subtract(const Duration(days: 1)).millisecondsSinceEpoch,
              endedAt: Value(now.subtract(const Duration(days: 1, minutes: -6)).millisecondsSinceEpoch),
              gameIds: gameId,
              completed: const Value(true),
            ),
          );

      // Determine cognitive domain
      final domain = _domainForGame(gameId);

      // Insert 10 trials spaced over the last 3 days
      for (int i = 0; i < 10; i++) {
        final timestamp = now.subtract(Duration(days: i % 3, hours: i + 1));
        final bool correct = isPerfect ? true : (i < 3); // 100% vs 30%
        final String metricsJson = isPerfect
            ? jsonEncode({'targets': 10, 'missed': 0, 'intrusions': 0})
            : jsonEncode({'targets': 10, 'missed': 7, 'intrusions': 0});

        await db.into(db.trialEvents).insert(
              TrialEventsCompanion.insert(
                id: _uuid.v4(),
                sessionId: sessionId,
                gameId: gameId,
                domain: domain.name,
                itemId: 'debug_item_$i',
                itemDifficulty: 0.0,
                thetaBefore: 1.0,
                correct: correct,
                initiationMs: 900,
                movementMs: 1100,
                responseTimeMs: 2000,
                trialIndex: i,
                hintLevel: const Value(0),
                metrics: Value(metricsJson),
                ts: timestamp.millisecondsSinceEpoch,
                hourOfDay: timestamp.hour,
                tzOffsetMin: timestamp.timeZoneOffset.inMinutes,
              ),
            );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isPerfect
                  ? 'Added 10 PERFECT trials (score 1.0) for $gameId across 3 days'
                  : 'Added 10 POOR trials (score 0.3) for $gameId across 3 days',
            ),
            backgroundColor: isPerfect ? AppColors.leafGreen : AppColors.terracotta,
          ),
        );
      }
      await _refreshState();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // --- Section B: The Time Machine ---

  Future<void> _forceReviewNow() async {
    setState(() => _loading = true);
    try {
      final reviews = await widget.services.progressionService.runDueReviews(
        forceOverride: true,
      );

      final summary = StringBuffer();
      if (reviews.isEmpty) {
        summary.writeln('No trials found in database to evaluate. Simulate some plays first!');
      } else {
        summary.writeln('Evaluated ${reviews.length} games:');
        for (final r in reviews) {
          final outcome = r.decision.name.toUpperCase();
          final change = '${r.levelBefore.toStringAsFixed(1)} → ${r.levelAfter.toStringAsFixed(1)}';
          final concernStr = r.isConcern ? ' [⚠️ CLINICAL CONCERN]' : '';
          final throttledStr = r.throttled ? ' [THROTTLED +0.5]' : '';
          summary.writeln('• $outcome: $change (Score: ${(r.meanScore * 100).toStringAsFixed(0)}%)$concernStr$throttledStr');
        }
      }

      _lastReviewSummary = summary.toString();

      if (mounted) {
        showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Time Machine Review Results'),
            content: Text(_lastReviewSummary ?? ''),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }

      await _refreshState();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // --- Section C: Fatigue & Rest Card ---

  Future<void> _addThirtyMinutes() async {
    final now = DateTime.now();
    final repo = widget.services.progressionRepo;
    final current = await repo.getRestState(now: now);
    final updated = current.copyWith(
      playSecondsToday: current.playSecondsToday + 1800,
    );
    await repo.saveRestState(updated);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Added 30m playtime. Total today: ${(updated.playSecondsToday / 60).toStringAsFixed(1)} mins',
          ),
          backgroundColor: AppColors.indigo,
        ),
      );
    }
    await _refreshState();
  }

  Future<void> _resetFatigue() async {
    final now = DateTime.now();
    final repo = widget.services.progressionRepo;
    final state = await repo.getRestState(now: now);
    final reset = state.copyWith(
      playSecondsToday: 0,
      keepPlayingCount: 0,
      lockUntilTs: null,
      lastPromptPlaySeconds: null,
    );
    await repo.saveRestState(reset);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reset fatigue counters and eye-break locks to zero'),
          backgroundColor: AppColors.leafGreen,
        ),
      );
    }
    await _refreshState();
  }

  Future<void> _triggerRestCard() async {
    final now = DateTime.now();
    final eval = await widget.services.progressionService.checkRestStatus(currentTime: now);

    if (!mounted) return;

    if (eval.status == RestCardStatus.showPrompt) {
      _showRestCardModal(
        title: 'Time for a Tea Break 🍵',
        message:
            'You have played wonderfully today! Would you like to rest your eyes and have some tea?',
        showKeepPlaying: true,
      );
    } else if (eval.status == RestCardStatus.locked) {
      _showRestCardModal(
        title: 'Games are Resting 🌙',
        message:
            'You have played wonderfully today! Time to rest your eyes and have some tea. Games will return in a little while.',
        showKeepPlaying: false,
      );
    } else {
      // Under threshold: show preview with option
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Rest Check: Free Play'),
          content: Text(
            'Current play today is ${(eval.playSecondsToday / 60).toStringAsFixed(1)} mins (threshold is 30 mins).\n\nTap "Add 30 Minutes" first to trigger naturally, or tap "Preview Modal" to test the UI directly.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _showRestCardModal(
                  title: 'Tea Break Preview 🍵',
                  message:
                      'You have played wonderfully today! Would you like to rest your eyes and have some tea?',
                  showKeepPlaying: true,
                );
              },
              child: const Text('Preview Modal'),
            ),
          ],
        ),
      );
    }
  }

  void _showRestCardModal({
    required String title,
    required String message,
    required bool showKeepPlaying,
  }) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppColors.primaryText,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message,
              style: const TextStyle(fontSize: 16, height: 1.4),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.raisedSurface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Play today: ${((_restState?.playSecondsToday ?? 0) / 60).toStringAsFixed(1)} min · Overrides: ${_restState?.keepPlayingCount ?? 0} / 3',
                style: const TextStyle(fontSize: 13, color: AppColors.secondaryText),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await widget.services.progressionService.recordRestAction(RestAction.takeBreak);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Elder chose: "Take a break" (cleared overrides)'),
                    backgroundColor: AppColors.leafGreen,
                  ),
                );
              }
              await _refreshState();
            },
            child: const Text('Take a break', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          if (showKeepPlaying)
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.terracotta,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                Navigator.of(ctx).pop();
                await widget.services.progressionService.recordRestAction(RestAction.keepPlaying);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Elder chose: "Keep playing" (+1 override)'),
                      backgroundColor: AppColors.indigo,
                    ),
                  );
                }
                await _refreshState();
              },
              child: const Text('Keep playing', style: TextStyle(fontSize: 16)),
            ),
        ],
      ),
    );
  }

  // --- Helpers ---

  CognitiveDomain _domainForGame(String gameId) {
    switch (gameId) {
      case 'market_basket':
        return CognitiveDomain.memory;
      case 'trace_path':
        return CognitiveDomain.visuospatial;
      case 'sort_the_harvest':
      case 'sort_harvest':
        return CognitiveDomain.executive;
      case 'lamps_festival':
        return CognitiveDomain.memory;
      case 'sounds_of_home':
      case 'sounds_home':
        return CognitiveDomain.attention;
      case 'faces_of_my_family':
      case 'faces_of_the_family':
      case 'faces_of_family':
        return CognitiveDomain.memory;
      default:
        return CognitiveDomain.memory;
    }
  }

  String _gameDisplayName(String gameId) {
    switch (gameId) {
      case 'market_basket':
        return 'Market Basket';
      case 'trace_path':
        return 'Trace the Path';
      case 'sort_the_harvest':
      case 'sort_harvest':
        return 'Sort the Harvest';
      case 'lamps_festival':
        return 'Lamps Festival';
      case 'sounds_of_home':
      case 'sounds_home':
        return 'Sounds of Home';
      case 'faces_of_my_family':
      case 'faces_of_the_family':
      case 'faces_of_family':
        return 'Faces of My Family';
      default:
        return gameId;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(
        title: const Text('Progression & Fatigue Engine Debugger'),
        backgroundColor: AppColors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh State',
            onPressed: _loading ? null : _refreshState,
          ),
        ],
      ),
      body: _loading && _gameProgresses.isEmpty
          ? const Center(child: CircularProgressIndicator(color: AppColors.terracotta))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                // SECTION B: The Time Machine (Large prominent banner)
                _buildSectionCard(
                  title: '⚡ Section B: The Time Machine (Force Review)',
                  subtitle: 'Bypass 4-day time windows and 2-day active minimums to evaluate current telemetry immediately.',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ElevatedButton.icon(
                        key: const Key('debug_force_review_button'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.terracotta,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.fast_forward, size: 26),
                        label: const Text(
                          'Force 4-Day Review Now',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        onPressed: _loading ? null : _forceReviewNow,
                      ),
                      if (_lastReviewSummary != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.raisedSurface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Text(
                            _lastReviewSummary!,
                            style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // SECTION A: Live Game Baselines
                _buildSectionCard(
                  title: '🎮 Section A: Live Game Baselines',
                  subtitle: 'Real-time SQLite levels stored in AppConfigs table (progression.v1.game.*).',
                  child: Column(
                    children: GameLevelProfiles.allProfiles.map((levelProfile) {
                      final gameId = levelProfile.gameId;
                      final progress = _gameProgresses[gameId] ?? GameProgress(gameId: gameId);
                      final profile = GameLevelProfiles.forGame(gameId);
                      final level = progress.level;
                      final difficulty = LevelScale.levelToDifficulty(level);
                      final domain = _domainForGame(gameId);

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.raisedSurface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _gameDisplayName(gameId),
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.primaryText,
                                      ),
                                    ),
                                    Text(
                                      'Domain: ${domain.name.toUpperCase()} · Max L: ${profile.maxAllowedLevel}',
                                      style: const TextStyle(fontSize: 12, color: AppColors.secondaryText),
                                    ),
                                  ],
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: AppColors.indigo,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        'L = ${level.toStringAsFixed(1)}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'd = ${difficulty.toStringAsFixed(2)}',
                                      style: const TextStyle(fontSize: 12, color: AppColors.secondaryText),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Reviews: ${progress.reviewHistory.length} · Last score: ${progress.lastReviewScore != null ? (progress.lastReviewScore! * 100).toStringAsFixed(0) : 'None'}% · Consecutive qualify: ${progress.consecutiveRaiseQualifyingCount}',
                              style: const TextStyle(fontSize: 12, color: AppColors.secondaryText),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.leafGreen,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 10),
                                    ),
                                    icon: const Icon(Icons.sentiment_very_satisfied, size: 18),
                                    label: const Text('Simulate Perfect', style: TextStyle(fontSize: 13)),
                                    onPressed: _loading ? null : () => _simulatePlay(gameId: gameId, isPerfect: true),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.amber.shade800,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 10),
                                    ),
                                    icon: const Icon(Icons.sentiment_dissatisfied, size: 18),
                                    label: const Text('Simulate Poor', style: TextStyle(fontSize: 13)),
                                    onPressed: _loading ? null : () => _simulatePlay(gameId: gameId, isPerfect: false),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 20),

                // SECTION C: Fatigue & Rest Card Testing
                _buildSectionCard(
                  title: '☕ Section C: Fatigue & Daily Rest Card',
                  subtitle: 'Tracks cumulative play time (8m session cap), 30m tea break, 15m snoozes, and 3h gentle lock.',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.raisedSurface,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Playtime Today: ${((_restState?.playSecondsToday ?? 0) / 60).toStringAsFixed(1)} minutes (${_restState?.playSecondsToday ?? 0}s)',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Overrides: ${_restState?.keepPlayingCount ?? 0} / 3 · Lock status: ${_restState?.isLocked(DateTime.now()) == true ? '🔒 ACTIVE (3h lock)' : 'Unlocked'}',
                              style: TextStyle(
                                fontSize: 13,
                                color: _restState?.isLocked(DateTime.now()) == true ? AppColors.terracotta : AppColors.secondaryText,
                                fontWeight: _restState?.isLocked(DateTime.now()) == true ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                              icon: const Icon(Icons.add_alarm),
                              label: const Text('+30m Playtime'),
                              onPressed: _loading ? null : _addThirtyMinutes,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                              icon: const Icon(Icons.restart_alt),
                              label: const Text('Reset Fatigue'),
                              onPressed: _loading ? null : _resetFatigue,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.leafGreen,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        icon: const Icon(Icons.free_breakfast),
                        label: const Text('Trigger Rest Card Check', style: TextStyle(fontSize: 16)),
                        onPressed: _loading ? null : _triggerRestCard,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // SECTION D: Variety Nudge Status
                _buildSectionCard(
                  title: '🧭 Section D: Variety Nudge (Anti-Perseveration)',
                  subtitle: 'Detects >= 60% repetitive play over >= 6 sessions and guides elder to under-exercised domains.',
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.raisedSurface,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Should Nudge: ${_nudgeEval?.shouldNudge == true ? 'YES' : 'NO'}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: _nudgeEval?.shouldNudge == true ? AppColors.terracotta : AppColors.primaryText,
                          ),
                        ),
                        if (_nudgeEval?.shouldNudge == true) ...[
                          const SizedBox(height: 4),
                          Text('Dominant Game: ${_nudgeEval?.dominantGameId}'),
                          Text('Recommended Domain: ${_nudgeEval?.recommendedDomain?.name}'),
                          Text('Recommended Game: ${_nudgeEval?.recommendedGameId}'),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.primaryText,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 13, color: AppColors.secondaryText),
          ),
          const Divider(height: 24),
          child,
        ],
      ),
    );
  }
}
