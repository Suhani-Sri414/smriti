import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../app_colors.dart';
import '../core/voice/voice_commander.dart';

/// The visual state of the microphone overlay over Home screen.
enum MicOverlayState {
  /// Hidden; Home screen is fully interactive.
  idle,

  /// Screen 15: Concentric ripple rings radiating over Home.
  listening,

  /// Screen 16: Zero-shame "I didn't catch that" with one-touch options.
  noMatch,
}

/// Overlay for Screen 15 (Microphone — Listening) and Screen 16 (Microphone — No Match).
///
/// Designed per prototype boards 15 & 16: sits directly over Home without replacing it,
/// showing animated expanding ripple rings during speech intake, and offering calm,
/// zero-shame one-touch navigation shortcuts when speech is not recognized.
class VoiceInteractionOverlay extends StatefulWidget {
  const VoiceInteractionOverlay({
    super.key,
    required this.state,
    required this.onDismiss,
    required this.onCommand,
    required this.onRetry,
    this.contactName = 'Family',
  });

  /// Current visual state.
  final MicOverlayState state;

  /// Callback when user closes or taps outside.
  final VoidCallback onDismiss;

  /// Callback when a navigation command or shortcut tile is selected.
  final ValueChanged<VoiceCommand> onCommand;

  /// Callback when user taps "Try again" to re-initiate listening.
  final VoidCallback onRetry;

  /// Primary caregiver or contact name for the Call shortcut.
  final String contactName;

  @override
  State<VoiceInteractionOverlay> createState() =>
      _VoiceInteractionOverlayState();
}

class _VoiceInteractionOverlayState extends State<VoiceInteractionOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _rippleController;

  @override
  void initState() {
    super.initState();
    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );

    if (widget.state == MicOverlayState.listening) {
      _rippleController.repeat();
    }
  }

  @override
  void didUpdateWidget(VoiceInteractionOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.state == MicOverlayState.listening) {
      if (!_rippleController.isAnimating) {
        _rippleController.repeat();
      }
    } else {
      _rippleController.stop();
    }
  }

  @override
  void dispose() {
    _rippleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.state == MicOverlayState.idle) {
      return const SizedBox.shrink();
    }

    return SizedBox.expand(
      child: Material(
        color: Colors.transparent,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Dark warm translucent scrim over Home (Color(0xAA251C15))
            Positioned.fill(
              child: GestureDetector(
                key: const Key('voice_scrim_dismiss'),
                behavior: HitTestBehavior.opaque,
                onTap: widget.onDismiss,
                child: Container(
                  color: const Color(0xAA251C15),
                ),
              ),
            ),

            // CONTENT: Screen 15 (Listening) vs Screen 16 (No Match)
            if (widget.state == MicOverlayState.listening)
              _buildListeningView()
            else if (widget.state == MicOverlayState.noMatch)
              _buildNoMatchView(),

            // Top Close Target (placed after content in z-order so it is always on top)
            Positioned(
              top: 24,
              right: 28,
              child: GestureDetector(
                key: const Key('voice_overlay_close'),
                behavior: HitTestBehavior.opaque,
                onTap: widget.onDismiss,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.raisedSurface,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: AppColors.border,
                      width: 2.0,
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.close_rounded,
                        size: 22,
                        color: AppColors.primaryText,
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Close',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primaryText,
                          fontFamily: 'Noto Sans',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SCREEN 15: MICROPHONE — LISTENING
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildListeningView() {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Concentric Expanding Ripple Rings Painter centered at bottom mic
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: 380,
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _rippleController,
              builder: (context, _) {
                return CustomPaint(
                  painter: _ConcentricRipplePainter(
                    progress: _rippleController.value,
                  ),
                );
              },
            ),
          ),
        ),

        // Floating Prompt Pill in upper half
        Positioned(
          top: 130,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
            decoration: BoxDecoration(
              color: AppColors.raisedSurface,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: AppColors.terracotta,
                width: 2.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      decoration: const BoxDecoration(
                        color: AppColors.terracotta,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Listening...',
                      key: Key('voice_listening_title'),
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primaryText,
                        fontFamily: 'Noto Sans',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Say: Play, Today, My People, or Call',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.secondaryText,
                    fontFamily: 'Noto Sans',
                  ),
                ),
              ],
            ),
          ),
        ),

        // Centered Highlighted Bottom Mic Button
        Positioned(
          bottom: 8,
          child: GestureDetector(
            key: const Key('voice_listening_mic_button'),
            behavior: HitTestBehavior.opaque,
            onTap: widget.onDismiss,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.terracotta,
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFFFFFDF8),
                  width: 3.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.terracotta.withValues(alpha: 0.5),
                    blurRadius: 18,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.mic_rounded,
                size: 42,
                color: Color(0xFFFFFDF8),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SCREEN 16: MICROPHONE — NO MATCH
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildNoMatchView() {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 740),
        margin: const EdgeInsets.symmetric(horizontal: 28),
        padding: const EdgeInsets.fromLTRB(32, 28, 32, 24),
        decoration: BoxDecoration(
          color: AppColors.raisedSurface,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(
            color: AppColors.border,
            width: 2.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Friendly zero-shame prompt
            const Text(
              "I didn't catch that",
              key: Key('voice_no_match_title'),
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: AppColors.primaryText,
                fontFamily: 'Noto Sans',
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Tap where you would like to go, or try speaking again:',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.secondaryText,
                fontFamily: 'Noto Sans',
              ),
            ),
            const SizedBox(height: 22),

            // 4 Shortcut Tiles (2x2 Grid)
            Row(
              children: [
                Expanded(
                  child: _buildActionTile(
                    key: const Key('voice_action_play'),
                    title: 'Play Games',
                    subtitle: 'Cognitive activities',
                    icon: Icons.extension_rounded,
                    accentColor: AppColors.terracotta,
                    onTap: () => widget.onCommand(VoiceCommand.play),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _buildActionTile(
                    key: const Key('voice_action_today'),
                    title: 'See Today',
                    subtitle: 'Schedule & medicines',
                    icon: Icons.calendar_today_rounded,
                    accentColor: AppColors.marigold,
                    onTap: () => widget.onCommand(VoiceCommand.today),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildActionTile(
                    key: const Key('voice_action_people'),
                    title: 'My People',
                    subtitle: 'Family & voice notes',
                    icon: Icons.people_alt_rounded,
                    accentColor: AppColors.indigo,
                    onTap: () => widget.onCommand(VoiceCommand.people),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _buildActionTile(
                    key: const Key('voice_action_call'),
                    title: 'Call ${widget.contactName}',
                    subtitle: 'Speak to family',
                    icon: Icons.phone_in_talk_rounded,
                    accentColor: AppColors.leafGreen,
                    onTap: () => widget.onCommand(VoiceCommand.call),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),

            // Bottom Buttons: "Try again" and "Back to Home"
            Row(
              children: [
                // "Try again" button
                Expanded(
                  flex: 5,
                  child: GestureDetector(
                    key: const Key('voice_try_again'),
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.onRetry,
                    child: Container(
                      height: 56,
                      decoration: BoxDecoration(
                        color: AppColors.terracotta,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: AppColors.terracottaDark,
                          width: 2.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.terracotta.withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.mic_rounded,
                                  color: Color(0xFFFFFDF8),
                                  size: 22,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Try speaking again',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFFFFFDF8),
                                    fontFamily: 'Noto Sans',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),

                // "Back to Home" button
                Expanded(
                  flex: 4,
                  child: GestureDetector(
                    key: const Key('voice_no_match_close'),
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.onDismiss,
                    child: Container(
                      height: 56,
                      decoration: BoxDecoration(
                        color: AppColors.raisedSurface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: AppColors.border,
                          width: 2.0,
                        ),
                      ),
                      child: const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              'Back to Home',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primaryText,
                                fontFamily: 'Noto Sans',
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionTile({
    required Key key,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      key: key,
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 68,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFDF8),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: accentColor.withValues(alpha: 0.6),
            width: 2.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: accentColor,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primaryText,
                        fontFamily: 'Noto Sans',
                      ),
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.secondaryText,
                      fontFamily: 'Noto Sans',
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.secondaryText,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

/// Custom painter rendering animated concentric expanding ripple rings
/// from the bottom microphone location.
class _ConcentricRipplePainter extends CustomPainter {
  _ConcentricRipplePainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    // Origin is bottom center of the canvas
    final center = Offset(size.width / 2, size.height - 48);

    // 3 expanding waves spaced apart
    const waveCount = 3;
    const maxRadius = 240.0;

    for (int i = 0; i < waveCount; i++) {
      final waveProgress = (progress + (i / waveCount)) % 1.0;
      final radius = 50.0 + (waveProgress * (maxRadius - 50.0));
      final opacity = math.sin(waveProgress * math.pi) * 0.45;

      final paint = Paint()
        ..color = AppColors.terracotta.withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5 - (waveProgress * 1.5);

      canvas.drawCircle(center, radius, paint);

      // Subtle warm fill for the innermost expanding ring
      if (i == 0) {
        final fillPaint = Paint()
          ..color = AppColors.marigold.withValues(alpha: opacity * 0.18)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(center, radius, fillPaint);
      }
    }
  }

  @override
  bool shouldRepaint(_ConcentricRipplePainter oldDelegate) =>
      oldDelegate.progress != progress;
}
