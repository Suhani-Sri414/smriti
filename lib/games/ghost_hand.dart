import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../app_colors.dart';

/// Controller for the ghost-hand demo: a translucent hand that traces the
/// correct gesture so the elder learns by watching rather than by reading
/// instructions.
///
/// Holds demo playback state, step durations, path waypoints, and waypoint
/// progress. Backwards-compatible with session runner and existing games.
class GhostHandController extends ChangeNotifier {
  GhostHandController({this.stepDuration = const Duration(milliseconds: 600)});

  final Duration stepDuration;

  bool _isPlaying = false;
  bool get isPlaying => _isPlaying;

  /// Normalised (0–1) points the hand moves between, in order.
  List<Offset> _path = const [];
  List<Offset> get path => _path;

  int _completedRuns = 0;
  int get completedRuns => _completedRuns;

  int _activeWaypointIndex = 0;
  int get activeWaypointIndex => _activeWaypointIndex;

  Offset? _currentPosition;
  Offset? get currentPosition => _currentPosition;

  /// Plays the demo gesture across [path].
  Future<void> play(List<Offset> path) async {
    if (path.isEmpty) return;

    _path = path;
    _isPlaying = true;
    _activeWaypointIndex = 0;
    _currentPosition = path.first;
    notifyListeners();

    final segments = (path.length - 1).clamp(1, 10);
    final perSegment = Duration(
      microseconds: (stepDuration.inMicroseconds / segments).round(),
    );

    for (int i = 1; i < path.length; i++) {
      await Future<void>.delayed(perSegment);
      _activeWaypointIndex = i;
      _currentPosition = path[i];
      notifyListeners();
    }

    // Hold briefly at final waypoint to register the action if duration allows
    if (stepDuration.inMilliseconds > 50) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }

    _isPlaying = false;
    _completedRuns++;
    notifyListeners();
  }

  /// Manually reset position and state if needed.
  void reset() {
    _isPlaying = false;
    _activeWaypointIndex = 0;
    _currentPosition = _path.isNotEmpty ? _path.first : null;
    notifyListeners();
  }
}

/// High-fidelity vector overlay of the ghost hand.
///
/// Renders an organic translucent pointing hand with drop shadow, subtle
/// waypoint pulse ripples, and a connecting motion trail so the elder
/// immediately understands the movement without verbal explanation.
class GhostHandOverlay extends StatefulWidget {
  const GhostHandOverlay({
    super.key,
    required this.controller,
    this.showTrail = true,
  });

  final GhostHandController controller;
  final bool showTrail;

  @override
  State<GhostHandOverlay> createState() => _GhostHandOverlayState();
}

class _GhostHandOverlayState extends State<GhostHandOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    widget.controller.addListener(_onControllerChanged);
    if (widget.controller.isPlaying) {
      _animController.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant GhostHandOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
      _onControllerChanged();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _animController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (widget.controller.isPlaying) {
      if (!_animController.isAnimating) {
        _animController.repeat();
      }
    } else {
      if (_animController.isAnimating) {
        _animController.stop();
      }
    }
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final isVisible =
        widget.controller.isPlaying || widget.controller.currentPosition != null;

    return IgnorePointer(
      child: SizedBox.expand(
        child: AnimatedOpacity(
          opacity: isVisible ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 200),
          child: AnimatedBuilder(
            animation: _animController,
            builder: (context, _) {
              return CustomPaint(
                key: const Key('ghost_hand_visual'),
                painter: _GhostHandPainter(
                  path: widget.controller.path,
                  currentPosition: widget.controller.currentPosition,
                  activeWaypointIndex: widget.controller.activeWaypointIndex,
                  isPlaying: widget.controller.isPlaying,
                  pulseProgress: _animController.value,
                  showTrail: widget.showTrail,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _GhostHandPainter extends CustomPainter {
  const _GhostHandPainter({
    required this.path,
    required this.currentPosition,
    required this.activeWaypointIndex,
    required this.isPlaying,
    required this.pulseProgress,
    required this.showTrail,
  });

  final List<Offset> path;
  final Offset? currentPosition;
  final int activeWaypointIndex;
  final bool isPlaying;
  final double pulseProgress;
  final bool showTrail;

  @override
  void paint(Canvas canvas, Size size) {
    if (path.isEmpty && currentPosition == null) return;

    // 1. Draw motion trajectory trail
    if (showTrail && path.length > 1) {
      _drawTrajectoryTrail(canvas, size);
    }

    // 2. Resolve pixel target for current hand position
    final normPos = currentPosition ?? path.first;
    final targetPixel = Offset(
      normPos.dx * size.width,
      normPos.dy * size.height,
    );

    // 3. Draw touch / waypoint pulse ripple
    if (isPlaying) {
      _drawWaypointRipple(canvas, targetPixel);
    }

    // 4. Draw the realistic translucent ghost hand pointing at targetPixel
    _drawHand(canvas, targetPixel);
  }

  void _drawTrajectoryTrail(Canvas canvas, Size size) {
    final trailPaint = Paint()
      ..color = const Color(0xFFD99A2B).withValues(alpha: 0.45)
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final pixelPoints = path
        .map((p) => Offset(p.dx * size.width, p.dy * size.height))
        .toList();

    for (int i = 0; i < pixelPoints.length - 1; i++) {
      final p1 = pixelPoints[i];
      final p2 = pixelPoints[i + 1];

      // Draw subtle dotted trail
      const dashWidth = 8.0;
      const dashSpace = 6.0;
      final distance = (p2 - p1).distance;
      if (distance <= 0) continue;

      final dx = (p2.dx - p1.dx) / distance;
      final dy = (p2.dy - p1.dy) / distance;

      double currentDist = 0.0;
      while (currentDist < distance) {
        final start = Offset(p1.dx + dx * currentDist, p1.dy + dy * currentDist);
        currentDist += dashWidth;
        final end = Offset(
          p1.dx + dx * math.min(currentDist, distance),
          p1.dy + dy * math.min(currentDist, distance),
        );
        canvas.drawLine(start, end, trailPaint);
        currentDist += dashSpace;
      }
    }
  }

  void _drawWaypointRipple(Canvas canvas, Offset target) {
    final rippleRadius = 14.0 + (pulseProgress * 24.0);
    final rippleOpacity = (1.0 - pulseProgress).clamp(0.0, 1.0) * 0.7;

    final ripplePaint = Paint()
      ..color = const Color(0xFFE5A93C).withValues(alpha: rippleOpacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    canvas.drawCircle(target, rippleRadius, ripplePaint);

    final innerGlow = Paint()
      ..color = const Color(0xFFC85A32).withValues(alpha: 0.25 * (1.0 - pulseProgress))
      ..style = PaintingStyle.fill;

    canvas.drawCircle(target, 12.0, innerGlow);
  }

  void _drawHand(Canvas canvas, Offset fingertip) {
    canvas.save();
    // Position hand so fingertip touches fingertip coordinate
    canvas.translate(fingertip.dx, fingertip.dy);

    // Hand angle: finger pointing up-left or down-right.
    // Standard natural touch pointer points up-left at -35 deg
    canvas.rotate(math.pi * -0.18);

    // Drop shadow
    final shadowPaint = Paint()
      ..color = const Color(0x35000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);

    final handPath = _createHandPath();
    canvas.drawPath(handPath.shift(const Offset(4, 6)), shadowPaint);

    // Main translucent body
    final fillPaint = Paint()
      ..color = AppColors.ghostHand.withValues(alpha: 0.82)
      ..style = PaintingStyle.fill;
    canvas.drawPath(handPath, fillPaint);

    // Organic inner gradient / soft warm sheen
    final sheenPaint = Paint()
      ..color = const Color(0xFFD4C8BE).withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawPath(handPath, sheenPaint);

    // Hand outline
    final strokePaint = Paint()
      ..color = const Color(0xFF4A3E38).withValues(alpha: 0.90)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(handPath, strokePaint);

    // Fingernail / index tip accent
    final tipAccent = Paint()
      ..color = const Color(0xFFFFFBF6).withValues(alpha: 0.6)
      ..style = PaintingStyle.fill;
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(0, 8), width: 7, height: 10),
      tipAccent,
    );

    canvas.restore();
  }

  /// Creates a stylized vector path of an index finger pointing at (0, 0).
  Path _createHandPath() {
    final path = Path();
    // Tip of index finger
    path.moveTo(-5, 5);
    path.quadraticBezierTo(0, 0, 5, 5);

    // Right side of index finger
    path.lineTo(7, 32);

    // Knuckle & middle finger curl
    path.quadraticBezierTo(14, 34, 18, 40);
    path.quadraticBezierTo(20, 48, 17, 56);

    // Ring finger curl
    path.quadraticBezierTo(19, 62, 16, 68);

    // Pinky finger curl
    path.quadraticBezierTo(17, 74, 13, 80);

    // Outer palm & wrist
    path.quadraticBezierTo(8, 90, 2, 102);
    path.lineTo(-18, 98);

    // Inner palm to thumb
    path.quadraticBezierTo(-16, 78, -14, 66);

    // Thumb knuckle and body
    path.quadraticBezierTo(-22, 54, -20, 42);
    path.quadraticBezierTo(-15, 34, -8, 38);

    // Left side of index finger
    path.lineTo(-6, 12);
    path.close();

    return path;
  }

  @override
  bool shouldRepaint(covariant _GhostHandPainter old) {
    return old.currentPosition != currentPosition ||
        old.isPlaying != isPlaying ||
        old.pulseProgress != pulseProgress ||
        old.activeWaypointIndex != activeWaypointIndex ||
        old.path != path;
  }
}
