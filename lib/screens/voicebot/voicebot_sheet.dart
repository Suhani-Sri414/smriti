import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../app_colors.dart';
import '../../core/voicebot/voicebot_controller.dart';

/// Modal bottom sheet or dialog providing the interactive ML VoiceBot companion.
class VoiceBotSheet extends StatefulWidget {
  const VoiceBotSheet({
    super.key,
    required this.controller,
    this.onClose,
  });

  final VoiceBotController controller;
  final VoidCallback? onClose;

  /// Convenience method to show the VoiceBot modal sheet.
  static Future<void> show(
    BuildContext context, {
    required VoiceBotController controller,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => VoiceBotSheet(
        controller: controller,
        onClose: () => Navigator.of(ctx).pop(),
      ),
    );
  }

  @override
  State<VoiceBotSheet> createState() => _VoiceBotSheetState();
}

class _VoiceBotSheetState extends State<VoiceBotSheet>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    widget.controller.addListener(_onControllerChange);
  }

  void _onControllerChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _animController.dispose();
    widget.controller.removeListener(_onControllerChange);
    super.dispose();
  }

  Future<void> _handleMicTap() async {
    final state = widget.controller.state;
    if (state == VoiceBotState.idle || state == VoiceBotState.error) {
      await widget.controller.startListening();
    } else if (state == VoiceBotState.listening) {
      await widget.controller.stopAndProcess();
    } else if (state == VoiceBotState.speaking) {
      await widget.controller.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final controller = widget.controller;

    return Container(
      height: screenHeight * 0.85,
      decoration: const BoxDecoration(
        color: AppColors.pageBackground,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            _buildDragHandle(),
            _buildHeader(context),
            const Divider(color: AppColors.border, height: 1),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Column(
                  children: [
                    Expanded(child: _buildConversationArea(controller)),
                    const SizedBox(height: 16),
                    _buildMicCenter(controller),
                    const SizedBox(height: 20),
                    _buildStatusLabel(controller),
                    _buildErrorDetailsBox(controller),
                    const SizedBox(height: 12),
                    _buildActionControls(controller),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDragHandle() {
    return Container(
      margin: const EdgeInsets.only(top: 12, bottom: 6),
      width: 48,
      height: 5,
      decoration: BoxDecoration(
        color: AppColors.border,
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.terracotta.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.volunteer_activism_rounded,
                  color: AppColors.terracotta,
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Smriti Companion',
                    style: TextStyle(
                      fontFamily: 'serif',
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryText,
                    ),
                  ),
                  Text(
                    'Always here to listen & talk',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.secondaryText.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ],
          ),
          IconButton(
            onPressed: widget.onClose ?? () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, size: 28),
            color: AppColors.primaryText,
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }

  Widget _buildConversationArea(VoiceBotController controller) {
    if (controller.turns.isEmpty &&
        controller.currentResponseText.isEmpty &&
        controller.currentTranscript.isEmpty) {
      return const SingleChildScrollView(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.chat_bubble_outline_rounded,
                size: 44,
                color: Color(0x666B7280),
              ),
              SizedBox(height: 12),
              Text(
                'How are you feeling today?\nTap the microphone below to talk.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: AppColors.secondaryText,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      reverse: true,
      itemCount: controller.turns.length,
      itemBuilder: (context, index) {
        final turn = controller.turns[controller.turns.length - 1 - index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (turn.userTranscript.isNotEmpty)
                Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    margin: const EdgeInsets.only(left: 48, bottom: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.wovenMat,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(
                      turn.userTranscript,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w500,
                        color: AppColors.primaryText,
                      ),
                    ),
                  ),
                ),
              if (turn.botResponse.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(right: 48),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.raisedSurface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppColors.border),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x0C000000),
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      turn.botResponse,
                      style: const TextStyle(
                        fontSize: 18,
                        height: 1.35,
                        color: AppColors.primaryText,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMicCenter(VoiceBotController controller) {
    final state = controller.state;
    Color buttonColor = AppColors.terracotta;
    IconData buttonIcon = Icons.mic_rounded;

    switch (state) {
      case VoiceBotState.idle:
        buttonColor = AppColors.terracotta;
        buttonIcon = Icons.mic_rounded;
        break;
      case VoiceBotState.listening:
        buttonColor = AppColors.marigold;
        buttonIcon = Icons.stop_rounded;
        break;
      case VoiceBotState.processing:
        buttonColor = AppColors.indigo;
        buttonIcon = Icons.hourglass_top_rounded;
        break;
      case VoiceBotState.speaking:
        buttonColor = AppColors.leafGreen;
        buttonIcon = Icons.volume_up_rounded;
        break;
      case VoiceBotState.error:
        buttonColor = AppColors.terracottaDark;
        buttonIcon = Icons.refresh_rounded;
        break;
    }

    return GestureDetector(
      key: const Key('voicebot_mic_button'),
      behavior: HitTestBehavior.opaque,
      onTap: _handleMicTap,
      child: AnimatedBuilder(
        animation: _animController,
        builder: (context, child) {
          double pulse = 1.0;
          if (state == VoiceBotState.listening) {
            pulse = 1.0 +
                (controller.amplitude * 0.35) +
                (math.sin(_animController.value * 2 * math.pi) * 0.08);
          } else if (state == VoiceBotState.speaking) {
            pulse = 1.0 +
                (math.sin(_animController.value * 2 * math.pi).abs() * 0.15);
          }

          return Stack(
            alignment: Alignment.center,
            children: [
              if (state == VoiceBotState.listening ||
                  state == VoiceBotState.speaking)
                Container(
                  width: 140 * pulse,
                  height: 140 * pulse,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: buttonColor.withValues(alpha: 0.18),
                  ),
                ),
              if (state == VoiceBotState.listening)
                Container(
                  width: 120 * pulse,
                  height: 120 * pulse,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: buttonColor.withValues(alpha: 0.28),
                  ),
                ),
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: buttonColor,
                  boxShadow: [
                    BoxShadow(
                      color: buttonColor.withValues(alpha: 0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: state == VoiceBotState.processing
                    ? const Center(
                        child: SizedBox(
                          width: 42,
                          height: 42,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 3.5,
                          ),
                        ),
                      )
                    : Icon(
                        buttonIcon,
                        size: 48,
                        color: Colors.white,
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatusLabel(VoiceBotController controller) {
    String label = 'Tap to speak';
    Color labelColor = AppColors.primaryText;

    switch (controller.state) {
      case VoiceBotState.idle:
        label = 'Tap the microphone to speak';
        labelColor = AppColors.secondaryText;
        break;
      case VoiceBotState.listening:
        label = 'Listening closely... Tap when finished';
        labelColor = AppColors.marigoldDark;
        break;
      case VoiceBotState.processing:
        label = 'Thinking...';
        labelColor = AppColors.indigoDark;
        break;
      case VoiceBotState.speaking:
        label = 'Companion speaking';
        labelColor = AppColors.leafGreenDark;
        break;
      case VoiceBotState.error:
        label = controller.errorMessage ?? "I'm right here. Let's try again.";
        labelColor = AppColors.terracottaDark;
        break;
    }

    return Text(
      label,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: labelColor,
      ),
    );
  }

  Widget _buildErrorDetailsBox(VoiceBotController controller) {
    if (controller.state != VoiceBotState.error) {
      return const SizedBox.shrink();
    }
    final rawDetails = controller.rawErrorDetails ?? controller.errorMessage;
    if (rawDetails == null || rawDetails.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      constraints: const BoxConstraints(maxHeight: 120),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFA39E)),
      ),
      child: SingleChildScrollView(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.bug_report_rounded,
              size: 20,
              color: AppColors.terracottaDark,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SelectableText(
                rawDetails,
                key: const Key('voicebot_raw_error_text'),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF820014),
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionControls(VoiceBotController controller) {
    if (controller.state == VoiceBotState.listening) {
      return ElevatedButton.icon(
        onPressed: () => controller.stopAndProcess(),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.marigold,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        icon: const Icon(Icons.check_rounded, size: 22),
        label: const Text(
          'Done Speaking',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      );
    }

    if (controller.state == VoiceBotState.error) {
      return ElevatedButton.icon(
        onPressed: () => controller.startListening(),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.terracotta,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        icon: const Icon(Icons.mic_rounded, size: 22),
        label: const Text(
          'Try Again',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      );
    }

    return const SizedBox(height: 12);
  }
}
