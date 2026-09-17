import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_colors.dart';
import '../../core/app_services.dart';
import '../../screens/session_end_screen.dart';
import '../cognitive_game.dart';
import '../session_runner.dart';
import 'sounds_of_home_game.dart';

/// Screen for Sounds of Home (Screen 02 game 4).
///
/// Auditory attention & environmental sound recognition game for the 1280×800 tablet.
/// The elder listens to a familiar domestic sound and taps the matching card
/// from 3 accessible choices.
/// Adheres strictly to AGENTS.md rule 11: no red, no "wrong", neutral return
/// on incorrect answer.
class SoundsOfHomeScreen extends StatefulWidget {
  const SoundsOfHomeScreen({
    super.key,
    required this.services,
    required this.content,
  });

  final AppServices services;
  final GameContent content;

  @override
  State<SoundsOfHomeScreen> createState() => _SoundsOfHomeScreenState();
}

class _SoundsOfHomeScreenState extends State<SoundsOfHomeScreen> {
  late final SoundsOfHomeGame _game = SoundsOfHomeGame();
  late final SessionRunner _runner = SessionRunner(
    eventRepo: widget.services.eventRepo,
    abilityRepo: widget.services.abilityRepo,
    content: widget.content,
  );

  GameItem? _item;
  DateTime? _shownAt;
  DateTime? _firstTouchAt;
  bool _isProcessing = false;
  String? _feedbackMessage;
  String? _eliminatedId;
  bool _isPlayingSound = false;
  Timer? _advanceTimer;
  Timer? _soundPlayTimer;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _advanceTimer?.cancel();
    _soundPlayTimer?.cancel();
    _runner.end(completed: false);
    _game.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    await _runner.start([_game]);
    await _nextItem();
  }

  Future<void> _nextItem() async {
    final item = await _runner.nextItem(_game);
    if (!mounted) return;

    if (item == null) {
      await _runner.end(completed: true);
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => SessionEndScreen(
              services: widget.services,
              gameTitle: 'Sounds of Home',
            ),
          ),
        );
      }
      return;
    }

    setState(() {
      _item = item;
      _shownAt = DateTime.now();
      _firstTouchAt = null;
      _isProcessing = false;
      _feedbackMessage = null;
      _eliminatedId = null;
      _isPlayingSound = true;
    });

    // Simulate sound playback pulse for 1.5 seconds
    _soundPlayTimer?.cancel();
    _soundPlayTimer = Timer(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      setState(() => _isPlayingSound = false);
    });
  }

  void _onReplayAudio() {
    if (_isProcessing) return;
    setState(() => _isPlayingSound = true);
    _soundPlayTimer?.cancel();
    _soundPlayTimer = Timer(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      setState(() => _isPlayingSound = false);
    });
  }

  void _onChooseSound(HomeSound chosen) {
    if (_isProcessing || _item == null) return;
    final now = DateTime.now();
    _firstTouchAt ??= now;

    final target = _item!.payload['target'] as HomeSound;
    final isCorrect = chosen.id == target.id;

    setState(() {
      _isProcessing = true;
      if (isCorrect) {
        _feedbackMessage = 'Yes! That is ${target.label}!';
      } else {
        // Rule 11: Gentle neutral cue, no red, no "wrong"
        _feedbackMessage = 'Let us listen again together';
      }
    });

    final initiationMs =
        _firstTouchAt!.difference(_shownAt ?? _firstTouchAt!).inMilliseconds;
    final movementMs = now.difference(_firstTouchAt!).inMilliseconds;

    _game.submitChoice(
      item: _item!,
      chosenId: chosen.id,
      initiationMs: initiationMs.clamp(50, 30000),
      movementMs: movementMs.clamp(10, 30000),
    );

    _advanceTimer?.cancel();
    _advanceTimer = Timer(Duration(milliseconds: isCorrect ? 1200 : 1500), () {
      if (!mounted) return;
      _nextItem();
    });
  }

  void _onAskHint() {
    if (_isProcessing || _item == null) return;
    final hintLevel = _runner.escalateHint();
    final target = _item!.payload['target'] as HomeSound;
    final options =
        (_item!.payload['options'] as List<Object?>).cast<HomeSound>();

    setState(() {
      if (hintLevel == 1) {
        _feedbackMessage = 'Clue: ${target.description}';
      } else if (hintLevel >= 2) {
        // Eliminate one distractor
        final distractor =
            options.firstWhere((s) => s.id != target.id && s.id != _eliminatedId);
        _eliminatedId = distractor.id;
        _feedbackMessage = 'Look at the choices left';
      }
    });
  }

  String _formatTime() {
    final now = DateTime.now();
    return '${now.hour}:${now.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final target = _item?.payload['target'] as HomeSound?;
    final options =
        (_item?.payload['options'] as List<Object?>?)?.cast<HomeSound>() ??
            const [];

    final media = MediaQuery.of(context);
    final isLandscape = media.orientation == Orientation.landscape;
    final isCompact = media.size.shortestSide < 600;

    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      body: SafeArea(
        child: Column(
          children: [
            // TOP BAR
            Padding(
              padding: EdgeInsets.fromLTRB(
                isCompact ? 16 : 24,
                isCompact ? 8 : 12,
                isCompact ? 16 : 28,
                isCompact ? 6 : 8,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  InkWell(
                    key: const Key('sounds_back_button'),
                    onTap: () => Navigator.of(context).pop(),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isCompact ? 12 : 16,
                        vertical: isCompact ? 6 : 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFDF8),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: AppColors.primaryText, width: 2),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.arrow_back_rounded,
                              size: isCompact ? 24 : 28,
                              color: AppColors.primaryText),
                          const SizedBox(width: 8),
                          Text(
                            'Games',
                            style: TextStyle(
                              fontSize: isCompact ? 17 : 20,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primaryText,
                              fontFamily: 'Noto Sans',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            'Sounds of Home',
                            style: TextStyle(
                              fontSize: isCompact ? 20 : 26,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primaryText,
                              fontFamily: 'Noto Sans',
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        key: const Key('sounds_hint_button'),
                        icon: Icon(Icons.lightbulb_outline_rounded,
                            size: isCompact ? 28 : 32,
                            color: AppColors.marigoldDark),
                        tooltip: 'Hint',
                        onPressed: _onAskHint,
                      ),
                      SizedBox(width: isCompact ? 6 : 12),
                      Text(
                        _formatTime(),
                        style: TextStyle(
                          fontSize: isCompact ? 18 : 22,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primaryText,
                          fontFamily: 'Noto Sans',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // MAIN PLAY AREA
            Expanded(
              child: target == null
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.marigold,
                      ),
                    )
                  : Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: isCompact ? 16 : 32,
                        vertical: isCompact ? 8 : 12,
                      ),
                      child: isLandscape
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Left: Sound Player Card
                                Expanded(
                                  flex: 5,
                                  child: _buildPlayerCard(isCompact: isCompact),
                                ),
                                SizedBox(width: isCompact ? 12 : 20),
                                // Right: 3 Choice Cards vertically
                                Expanded(
                                  flex: 5,
                                  child: Column(
                                    children: [
                                      for (int i = 0;
                                          i < options.length;
                                          i++) ...[
                                        if (i > 0)
                                          SizedBox(height: isCompact ? 8 : 12),
                                        Expanded(
                                          child: _buildChoiceCard(
                                            options[i],
                                            isCompact: isCompact,
                                            isRowLayout: true,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            )
                          : Column(
                              children: [
                                // Top: Sound Player Card
                                Expanded(
                                  flex: 5,
                                  child: _buildPlayerCard(isCompact: isCompact),
                                ),
                                SizedBox(height: isCompact ? 12 : 16),
                                // Bottom: Choice Cards
                                Expanded(
                                  flex: isCompact ? 5 : 3,
                                  child: isCompact
                                      ? Column(
                                          children: [
                                            for (int i = 0;
                                                i < options.length;
                                                i++) ...[
                                              if (i > 0)
                                                const SizedBox(height: 8),
                                              Expanded(
                                                child: _buildChoiceCard(
                                                  options[i],
                                                  isCompact: isCompact,
                                                  isRowLayout: true,
                                                ),
                                              ),
                                            ],
                                          ],
                                        )
                                      : Row(
                                          children: [
                                            for (int i = 0;
                                                i < options.length;
                                                i++) ...[
                                              if (i > 0)
                                                const SizedBox(width: 20),
                                              Expanded(
                                                child: _buildChoiceCard(
                                                  options[i],
                                                  isCompact: isCompact,
                                                  isRowLayout: false,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                ),
                              ],
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerCard({required bool isCompact}) {
    final buttonSize = isCompact ? 76.0 : 96.0;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isCompact ? 12 : 16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDF8),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: AppColors.marigold.withAlpha(120),
          width: 2.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(12),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Animated Sound Pulsing Button
          InkWell(
            key: const Key('sounds_listen_button'),
            onTap: _onReplayAudio,
            borderRadius: BorderRadius.circular(50),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: buttonSize,
              height: buttonSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isPlayingSound
                    ? AppColors.marigold
                    : const Color(0xFFFAF2E1),
                border: Border.all(
                  color: AppColors.marigold,
                  width: 3,
                ),
                boxShadow: _isPlayingSound
                    ? [
                        BoxShadow(
                          color: AppColors.marigold.withAlpha(100),
                          blurRadius: 20,
                          spreadRadius: 6,
                        ),
                      ]
                    : [],
              ),
              child: Icon(
                _isPlayingSound
                    ? Icons.volume_up_rounded
                    : Icons.play_arrow_rounded,
                size: isCompact ? 42 : 52,
                color: _isPlayingSound ? Colors.white : AppColors.marigoldDark,
              ),
            ),
          ),
          SizedBox(height: isCompact ? 6 : 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              'What made this sound?',
              style: TextStyle(
                fontSize: isCompact ? 20 : 24,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryText,
                fontFamily: 'Noto Sans',
              ),
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              'Tap the speaker to listen again',
              style: TextStyle(
                fontSize: isCompact ? 13 : 16,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF7A6855),
                fontFamily: 'Noto Sans',
              ),
            ),
          ),
          if (_feedbackMessage != null) ...[
            SizedBox(height: isCompact ? 6 : 8),
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: isCompact ? 14 : 20,
                vertical: isCompact ? 4 : 6,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFF3EDE2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  _feedbackMessage!,
                  style: TextStyle(
                    fontSize: isCompact ? 16 : 20,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryText,
                    fontFamily: 'Noto Sans',
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildChoiceCard(
    HomeSound sound, {
    required bool isCompact,
    required bool isRowLayout,
  }) {
    final isEliminated = sound.id == _eliminatedId;

    if (isEliminated) {
      return Container(
        decoration: BoxDecoration(
          color: const Color(0xFFEFECE4),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFD6CFC4), width: 2),
        ),
        child: const Center(
          child: Icon(Icons.remove_circle_outline,
              size: 36, color: Color(0xFFA69E92)),
        ),
      );
    }

    return InkWell(
      key: Key('sound_option_${sound.id}'),
      onTap: _isProcessing ? null : () => _onChooseSound(sound),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isCompact ? 12 : 16,
          vertical: isCompact ? 6 : 10,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFDF8),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.marigold, width: 2.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(10),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: isRowLayout
            ? Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(isCompact ? 6 : 8),
                    decoration: BoxDecoration(
                      color: sound.color.withAlpha(25),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      sound.icon,
                      size: isCompact ? 24 : 32,
                      color: sound.color,
                    ),
                  ),
                  SizedBox(width: isCompact ? 10 : 14),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            sound.label,
                            style: TextStyle(
                              fontSize: isCompact ? 17 : 20,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primaryText,
                              fontFamily: 'Noto Sans',
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            sound.description,
                            style: TextStyle(
                              fontSize: isCompact ? 12 : 14,
                              fontWeight: FontWeight.w500,
                              color: AppColors.primaryText.withAlpha(180),
                              fontFamily: 'Noto Sans',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    sound.icon,
                    size: isCompact ? 30 : 38,
                    color: sound.color,
                  ),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      sound.label,
                      style: TextStyle(
                        fontSize: isCompact ? 17 : 20,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primaryText,
                        fontFamily: 'Noto Sans',
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      sound.description,
                      style: TextStyle(
                        fontSize: isCompact ? 12 : 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.primaryText.withAlpha(180),
                        fontFamily: 'Noto Sans',
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
