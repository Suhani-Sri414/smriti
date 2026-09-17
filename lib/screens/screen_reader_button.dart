import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../core/voice/screen_reader_service.dart';

/// Reusable accessibility button that triggers Text-to-Speech (TTS) reading
/// of on-screen content for dementia patients and elderly users.
///
/// Toggles between starting and stopping speech, with an active visual
/// indicator (color accent + gentle pulsing halo animation) while speaking.
class ScreenReaderButton extends StatefulWidget {
  const ScreenReaderButton({
    super.key,
    required this.text,
    this.service,
    this.iconSize = 22,
    this.compact = false,
    this.showLabel = false,
    this.customLabel,
  });

  /// The text string read aloud when activated.
  final String text;

  /// Injected or shared [ScreenReaderService]. If not provided, a fallback
  /// instance is lazily instantiated.
  final ScreenReaderService? service;

  /// Icon size.
  final double iconSize;

  /// Whether to render a compact layout (e.g. For landscape top bars).
  final bool compact;

  /// Whether to display a textual label next to the speaker icon.
  final bool showLabel;

  /// Custom label override.
  final String? customLabel;

  @override
  State<ScreenReaderButton> createState() => _ScreenReaderButtonState();
}

class _ScreenReaderButtonState extends State<ScreenReaderButton>
    with SingleTickerProviderStateMixin {
  late final ScreenReaderService _service;
  late final AnimationController _pulseController;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? ScreenReaderService();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOut,
      ),
    );

    _service.isSpeakingNotifier.addListener(_onSpeakingChanged);
    if (_service.isSpeaking) {
      _pulseController.repeat(reverse: true);
    }
  }

  void _onSpeakingChanged() {
    if (!mounted) return;
    if (_service.isSpeaking) {
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
    } else {
      if (_pulseController.isAnimating) {
        _pulseController.stop();
        _pulseController.reset();
      }
    }
    setState(() {});
  }

  @override
  void dispose() {
    _service.isSpeakingNotifier.removeListener(_onSpeakingChanged);
    _pulseController.dispose();
    super.dispose();
  }

  void _toggleSpeech() {
    if (_service.isSpeaking) {
      _service.stop();
    } else {
      _service.speak(widget.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSpeaking = _service.isSpeaking;
    final labelText = widget.customLabel ?? (isSpeaking ? 'Stop reading' : 'Read aloud');

    return Semantics(
      button: true,
      label: labelText,
      hint: isSpeaking
          ? 'Tap to stop reading screen instructions'
          : 'Tap to read screen instructions aloud',
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          final scale = isSpeaking ? _scaleAnimation.value : 1.0;
          final pulseValue = isSpeaking ? _pulseController.value : 0.0;

          return Transform.scale(
            scale: scale,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _toggleSpeech,
                borderRadius: BorderRadius.circular(24),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  padding: widget.showLabel
                      ? EdgeInsets.symmetric(
                          horizontal: widget.compact ? 12 : 16,
                          vertical: widget.compact ? 8 : 10,
                        )
                      : EdgeInsets.all(widget.compact ? 10 : 12),
                  decoration: BoxDecoration(
                    color: isSpeaking
                        ? AppColors.medicineBlush
                        : AppColors.raisedSurface,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: isSpeaking
                          ? AppColors.terracotta
                          : AppColors.terracotta.withValues(alpha: 0.45),
                      width: isSpeaking ? 2.0 : 1.5,
                    ),
                    boxShadow: [
                      if (isSpeaking)
                        BoxShadow(
                          color: AppColors.terracotta.withValues(
                            alpha: 0.2 + (0.2 * pulseValue),
                          ),
                          blurRadius: 10 + (6 * pulseValue),
                          spreadRadius: 1 + (2 * pulseValue),
                        )
                      else
                        const BoxShadow(
                          color: Color(0x0C000000),
                          blurRadius: 6,
                          offset: Offset(0, 2),
                        ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isSpeaking
                            ? Icons.volume_up_rounded
                            : Icons.volume_up_outlined,
                        color: AppColors.terracotta,
                        size: widget.iconSize,
                      ),
                      if (widget.showLabel) ...[
                        const SizedBox(width: 8),
                        Text(
                          labelText,
                          style: TextStyle(
                            fontSize: widget.compact ? 14 : 16,
                            fontWeight:
                                isSpeaking ? FontWeight.w800 : FontWeight.w700,
                            color: AppColors.terracotta,
                            fontFamily: 'Noto Sans',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
