import 'dart:math';

import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../core/app_services.dart';
import '../core/sync/sync_engine.dart';

/// Screen 09: Session End.
///
/// Designed for a 1280×800 landscape tablet.
/// Core UX principle (Rule 11):
/// "No score, no streak. Every session ends warmly, however it went."
///
/// Shows a blooming marigold garland motif, gentle appreciation, elder name,
/// and large accessible touch targets to return Home or play another game.
class SessionEndScreen extends StatefulWidget {
  const SessionEndScreen({
    super.key,
    required this.services,
    this.gameTitle,
  });

  final AppServices services;
  final String? gameTitle;

  @override
  State<SessionEndScreen> createState() => _SessionEndScreenState();
}

class _SessionEndScreenState extends State<SessionEndScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;
  String _elderName = '';

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.96, end: 1.04).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _loadElderName();
    _triggerSessionEndSync();
  }

  Future<void> _loadElderName() async {
    try {
      final name =
          await widget.services.db.appConfigsDao.getValue('elderName');
      if (mounted && name != null && name.trim().isNotEmpty) {
        setState(() => _elderName = name.trim());
      }
    } catch (_) {
      // In tests or missing configs, fallback gracefully.
    }
  }

  void _triggerSessionEndSync() {
    // Fire-and-forget sync trigger immediately after session ends.
    // Spec §4.1: Immediately after a session ends, events are uploaded.
    widget.services.syncEngine.run(trigger: SyncTrigger.sessionEnd).ignore();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _onHomePressed() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _onPlayAnotherPressed() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final displayName = _elderName.isNotEmpty ? _elderName : 'Ibemhal';
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final isCompact = MediaQuery.of(context).size.width < 600 ||
        MediaQuery.of(context).size.height < 600;

    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isCompact ? 16 : 48,
                vertical: isCompact ? 16 : 24,
              ),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 960),
                decoration: BoxDecoration(
                  color: AppColors.raisedSurface,
                  borderRadius: BorderRadius.circular(isCompact ? 24 : 32),
                  border: Border.all(color: AppColors.border, width: 2.5),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryText.withValues(alpha: 0.08),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                padding: EdgeInsets.all(isCompact ? 20 : 36),
                child: isLandscape && isCompact
                    ? _buildLandscapeContent(displayName)
                    : _buildPortraitContent(displayName, isCompact),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLandscapeContent(String displayName) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Left Column: Garland + Optional Game Tag
        Expanded(
          flex: 4,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.gameTitle != null) ...[
                _buildGameTag(),
                const SizedBox(height: 10),
              ],
              ScaleTransition(
                scale: _pulseAnimation,
                child: const SizedBox(
                  width: 120,
                  height: 120,
                  child: CustomPaint(
                    painter: _MarigoldGarlandPainter(),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 20),

        // Right Column: Warm text + Action Buttons
        Expanded(
          flex: 6,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'Thank you, $displayName',
                  key: const Key('session_end_greeting'),
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryText,
                    fontFamily: 'Noto Sans',
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'You spent wonderful time playing today.',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: AppColors.secondaryText,
                  fontFamily: 'Noto Sans',
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Everything is calm and at peace.',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: AppColors.secondaryText.withValues(alpha: 0.85),
                  fontFamily: 'Noto Sans',
                ),
              ),
              const SizedBox(height: 16),
              _buildActionButtons(compact: true),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPortraitContent(String displayName, bool isCompact) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header badge (Optional Game tag)
        if (widget.gameTitle != null) ...[
          _buildGameTag(),
          const SizedBox(height: 14),
        ] else
          const SizedBox(height: 8),

        // Central Warm Floral Motif (Marigold Garland)
        ScaleTransition(
          scale: _pulseAnimation,
          child: SizedBox(
            width: isCompact ? 130 : 170,
            height: isCompact ? 130 : 170,
            child: const CustomPaint(
              painter: _MarigoldGarlandPainter(),
            ),
          ),
        ),
        SizedBox(height: isCompact ? 14 : 24),

        // Warm Appreciation Typography (Zero-Shame)
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            'Thank you, $displayName',
            key: const Key('session_end_greeting'),
            style: TextStyle(
              fontSize: isCompact ? 28 : 38,
              fontWeight: FontWeight.w700,
              color: AppColors.primaryText,
              fontFamily: 'Noto Sans',
              letterSpacing: -0.5,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'You spent wonderful time playing today.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: isCompact ? 18 : 22,
            fontWeight: FontWeight.w500,
            color: AppColors.secondaryText,
            fontFamily: 'Noto Sans',
            height: 1.3,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Everything is calm and at peace.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: isCompact ? 15 : 18,
            fontWeight: FontWeight.w400,
            color: AppColors.secondaryText.withValues(alpha: 0.85),
            fontFamily: 'Noto Sans',
          ),
        ),
        SizedBox(height: isCompact ? 22 : 36),

        // Bottom Action Buttons
        _buildActionButtons(compact: isCompact),
      ],
    );
  }

  Widget _buildGameTag() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.wovenMat.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.border.withValues(alpha: 0.7),
          width: 1.5,
        ),
      ),
      child: Text(
        widget.gameTitle!,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppColors.secondaryText,
          fontFamily: 'Noto Sans',
        ),
      ),
    );
  }

  Widget _buildActionButtons({bool compact = false}) {
    final height = compact ? 58.0 : 76.0;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Home Button
        Expanded(
          child: InkWell(
            key: const Key('session_end_home_button'),
            onTap: _onHomePressed,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              height: height,
              decoration: BoxDecoration(
                color: const Color(0xFFFFFDF8),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppColors.primaryText,
                  width: 2.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryText.withValues(alpha: 0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.home_rounded,
                        size: compact ? 26 : 32,
                        color: AppColors.primaryText,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Home',
                        style: TextStyle(
                          fontSize: compact ? 20 : 24,
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
          ),
        ),
        SizedBox(width: compact ? 14 : 28),

        // Play Another Game Button
        Expanded(
          child: InkWell(
            key: const Key('session_end_games_button'),
            onTap: _onPlayAnotherPressed,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              height: height,
              decoration: BoxDecoration(
                color: AppColors.terracotta,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppColors.terracottaDark,
                  width: 2.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.terracotta.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.grid_view_rounded,
                        size: compact ? 24 : 30,
                        color: AppColors.onColor,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Other Games',
                        style: TextStyle(
                          fontSize: compact ? 20 : 24,
                          fontWeight: FontWeight.w700,
                          color: AppColors.onColor,
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
      ],
    );
  }
}

/// Custom painter rendering a golden marigold flower garland motif.
///
/// Designed with cultural warmth representing celebration, peaceful blessing,
/// and gratitude in North-East Indian households.
class _MarigoldGarlandPainter extends CustomPainter {
  const _MarigoldGarlandPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Outer subtle golden ring
    final ringPaint = Paint()
      ..color = AppColors.marigold.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(center, radius * 0.92, ringPaint);

    // Green leaf accents around flower
    final leafPaint = Paint()
      ..color = AppColors.leafGreen
      ..style = PaintingStyle.fill;

    const numLeaves = 8;
    for (int i = 0; i < numLeaves; i++) {
      final angle = (i * 2 * pi / numLeaves) + (pi / numLeaves);
      final leafCenter = center +
          Offset(cos(angle) * radius * 0.72, sin(angle) * radius * 0.72);

      canvas.save();
      canvas.translate(leafCenter.dx, leafCenter.dy);
      canvas.rotate(angle);
      final leafPath = Path()
        ..moveTo(0, -7)
        ..quadraticBezierTo(14, 0, 0, 7)
        ..quadraticBezierTo(-14, 0, 0, -7)
        ..close();
      canvas.drawPath(leafPath, leafPaint);
      canvas.restore();
    }

    // Outer Petals Layer (Marigold Warm Amber)
    final outerPetalPaint = Paint()
      ..color = AppColors.marigold
      ..style = PaintingStyle.fill;

    const numOuterPetals = 12;
    for (int i = 0; i < numOuterPetals; i++) {
      final angle = i * 2 * pi / numOuterPetals;
      final petalCenter = center +
          Offset(cos(angle) * radius * 0.52, sin(angle) * radius * 0.52);

      canvas.save();
      canvas.translate(petalCenter.dx, petalCenter.dy);
      canvas.rotate(angle);
      final petalPath = Path()
        ..moveTo(0, -14)
        ..quadraticBezierTo(20, 0, 0, 14)
        ..quadraticBezierTo(-8, 0, 0, -14)
        ..close();
      canvas.drawPath(petalPath, outerPetalPaint);
      canvas.restore();
    }

    // Inner Petals Layer (Deep Marigold/Amber)
    final innerPetalPaint = Paint()
      ..color = const Color(0xFFE8AB30)
      ..style = PaintingStyle.fill;

    const numInnerPetals = 10;
    for (int i = 0; i < numInnerPetals; i++) {
      final angle = (i * 2 * pi / numInnerPetals) + (pi / numInnerPetals);
      final petalCenter = center +
          Offset(cos(angle) * radius * 0.32, sin(angle) * radius * 0.32);

      canvas.save();
      canvas.translate(petalCenter.dx, petalCenter.dy);
      canvas.rotate(angle);
      final innerPath = Path()
        ..moveTo(0, -10)
        ..quadraticBezierTo(14, 0, 0, 10)
        ..quadraticBezierTo(-6, 0, 0, -10)
        ..close();
      canvas.drawPath(innerPath, innerPetalPaint);
      canvas.restore();
    }

    // Central Terracotta Core
    final corePaint = Paint()
      ..color = AppColors.terracotta
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius * 0.22, corePaint);

    final coreHighlightPaint = Paint()
      ..color = AppColors.marigoldPressed
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius * 0.12, coreHighlightPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
