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

    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      body: SafeArea(
        child: Column(
          children: [
            // TOP BAR
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 28, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  InkWell(
                    key: const Key('sounds_back_button'),
                    onTap: () => Navigator.of(context).pop(),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFDF8),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: AppColors.primaryText, width: 2),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.arrow_back_rounded,
                              size: 28, color: AppColors.primaryText),
                          SizedBox(width: 8),
                          Text(
                            'Games',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primaryText,
                              fontFamily: 'Noto Sans',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Expanded(
                    child: Center(
                      child: Text(
                        'Sounds of Home',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primaryText,
                          fontFamily: 'Noto Sans',
                        ),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        key: const Key('sounds_hint_button'),
                        icon: const Icon(Icons.lightbulb_outline_rounded,
                            size: 32, color: AppColors.marigoldDark),
                        tooltip: 'Hint',
                        onPressed: _onAskHint,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _formatTime(),
                        style: const TextStyle(
                          fontSize: 22,
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32, vertical: 12),
                      child: Column(
                        children: [
                          // CENTER SOUND PLAYER CARD
                          Expanded(
                            flex: 5,
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
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
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Animated Sound Pulsing Button
                                  InkWell(
                                    key: const Key('sounds_listen_button'),
                                    onTap: _onReplayAudio,
                                    borderRadius: BorderRadius.circular(50),
                                    child: AnimatedContainer(
                                      duration:
                                          const Duration(milliseconds: 300),
                                      width: 96,
                                      height: 96,
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
                                                  color: AppColors.marigold
                                                      .withAlpha(100),
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
                                        size: 52,
                                        color: _isPlayingSound
                                            ? Colors.white
                                            : AppColors.marigoldDark,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'What made this sound?',
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primaryText,
                                      fontFamily: 'Noto Sans',
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'Tap the speaker to listen again',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                      color: Color(0xFF7A6855),
                                      fontFamily: 'Noto Sans',
                                    ),
                                  ),
                                  if (_feedbackMessage != null) ...[
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 20, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF3EDE2),
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: Text(
                                        _feedbackMessage!,
                                        style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.primaryText,
                                          fontFamily: 'Noto Sans',
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 20),

                          // 3 CHOICE CARDS
                          Expanded(
                            flex: 3,
                            child: Row(
                              children: [
                                for (int i = 0; i < options.length; i++) ...[
                                  if (i > 0) const SizedBox(width: 20),
                                  Expanded(
                                    child: _buildChoiceCard(options[i]),
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

  Widget _buildChoiceCard(HomeSound sound) {
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(sound.icon, size: 38, color: sound.color),
            const SizedBox(height: 4),
            Flexible(
              child: Text(
                sound.label,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryText,
                  fontFamily: 'Noto Sans',
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 2),
            Flexible(
              child: Text(
                sound.description,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.primaryText.withAlpha(180),
                  fontFamily: 'Noto Sans',
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
