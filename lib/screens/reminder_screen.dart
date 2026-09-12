import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../app_colors.dart';
import '../core/app_services.dart';
import '../core/db/database.dart';
import '../core/voice/voice_player.dart';

/// Screen 14: Medicine Reminder.
///
/// Designed for a 1280×800 landscape tablet in North-East India.
/// Prototype board 14 specification:
/// "Full screen, blush ground, the real pill drawn at size. 'Not yet' carries no penalty."
///
/// A11 makes this the target of the full-screen intent fired by `fireReminderCallback`.
/// Plays the caregiver's voice message, shows the pill (photo or vector illustration),
/// and provides equal-prominence "Taken" and "Not now" action targets.
class ReminderScreen extends StatefulWidget {
  const ReminderScreen({
    super.key,
    required this.services,
    required this.medication,
    this.reminderEventId,
    this.voicePlayer,
    this.now,
  });

  final AppServices services;
  final Medication medication;

  /// Supplied by the alarm isolate at A11, which has already written the
  /// `ReminderEvents` row. When absent — the test trigger — this screen
  /// creates one so the outcome has somewhere to live.
  final String? reminderEventId;

  final VoicePlayer? voicePlayer;
  final DateTime Function()? now;

  @override
  State<ReminderScreen> createState() => _ReminderScreenState();
}

class _ReminderScreenState extends State<ReminderScreen> {
  late final VoicePlayer _voice = widget.voicePlayer ?? JustAudioVoicePlayer();
  late final DateTime Function() _now = widget.now ?? DateTime.now;

  String? _eventId;
  String? _photoPath;
  String? _voicePath;
  bool _responding = false;
  bool _isPlayingVoice = false;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void dispose() {
    _voice.dispose();
    super.dispose();
  }

  Future<void> _prepare() async {
    final services = widget.services;
    final medication = widget.medication;

    var eventId = widget.reminderEventId;
    if (eventId == null) {
      // Test-fired reminder: create the row this screen will resolve.
      eventId = const Uuid().v4();
      final firedAt = _now().millisecondsSinceEpoch;
      await services.eventRepo.insertReminderEvent(
        ReminderEventsCompanion.insert(
          id: eventId,
          medicationId: medication.id,
          scheduledAt: firedAt,
          firedAt: Value(firedAt),
          channel: 'in_app',
          ladderStep: 0,
        ),
      );
    }

    final photo = medication.pillPhotoPath;
    final photoPath =
        photo == null ? null : await services.resolveMediaPath(photo);

    final voice = medication.voicePath;
    final voicePath =
        voice == null ? null : await services.resolveMediaPath(voice);

    if (!mounted) return;
    setState(() {
      _eventId = eventId;
      _photoPath = photoPath;
      _voicePath = voicePath;
    });

    // The caregiver's own voice is the point; a missing file plays nothing.
    if (voicePath != null) {
      await _playVoice(voicePath);
    }
  }

  Future<void> _playVoice(String resolvedPath) async {
    try {
      setState(() => _isPlayingVoice = true);
      await _voice.play(resolvedPath);
    } finally {
      if (mounted) {
        setState(() => _isPlayingVoice = false);
      }
    }
  }

  Future<void> _replayVoice() async {
    final path = _voicePath;
    if (path != null) {
      await _voice.stop();
      await _playVoice(path);
    }
  }

  /// Writes the outcome and leaves. `outcome` values match the ladder's
  /// vocabulary: the elder either took it or deferred.
  Future<void> _respond(String outcome) async {
    if (_responding) return;
    setState(() => _responding = true);

    await _voice.stop();

    final eventId = _eventId;
    if (eventId != null) {
      // Records the outcome AND tears down the rest of the ladder, so a
      // "taken" dose can never escalate to a phone call.
      await widget.services.respondToReminder(
        reminderEventId: eventId,
        outcome: outcome,
        now: _now(),
      );
    }

    if (mounted) Navigator.of(context).pop(outcome);
  }

  static String _formatMinutes(int minutes) {
    final h = (minutes ~/ 60).toString().padLeft(2, '0');
    final m = (minutes % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final photo = _photoPath;
    final file = photo == null ? null : File(photo);
    final hasRealPhoto = file != null && file.existsSync();

    final hasVoice = _voicePath != null;

    final windowStr =
        '${_formatMinutes(widget.medication.windowStartMin)} – ${_formatMinutes(widget.medication.windowEndMin)}';

    return Scaffold(
      backgroundColor: AppColors.medicineBlush,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 1040, maxHeight: 680),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFDF8),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(
                  color: AppColors.border,
                  width: 2.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryText.withValues(alpha: 0.08),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(48, 36, 48, 36),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Main Body (Two Columns: Visual Left, Information Right)
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Left Visual: Pill Photo or Vector Pill + Voice Replay
                        Expanded(
                          flex: 5,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 260,
                                height: 220,
                                decoration: BoxDecoration(
                                  color: AppColors.raisedSurface,
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(
                                    color: AppColors.border.withValues(alpha: 0.7),
                                    width: 2,
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: hasRealPhoto
                                    ? ClipRRect(
                                        borderRadius: BorderRadius.circular(22),
                                        child: Image.file(
                                          file,
                                          height: 200,
                                          fit: BoxFit.contain,
                                        ),
                                      )
                                    : const CustomPaint(
                                        size: Size(220, 150),
                                        painter: _PillVectorPainter(),
                                      ),
                              ),

                              // Caregiver Voice Playback & Replay Button
                              if (hasVoice) ...[
                                const SizedBox(height: 16),
                                InkWell(
                                  key: const Key('reminder_replay_voice'),
                                  onTap: _responding ? null : _replayVoice,
                                  borderRadius: BorderRadius.circular(20),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.medicineBlush,
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: AppColors.terracotta,
                                        width: 1.8,
                                      ),
                                    ),
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            _isPlayingVoice
                                                ? Icons.volume_up_rounded
                                                : Icons.replay_rounded,
                                            size: 24,
                                            color: AppColors.terracotta,
                                          ),
                                          const SizedBox(width: 8),
                                          const Text(
                                            'Hear message again',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w700,
                                              color: AppColors.terracotta,
                                              fontFamily: 'Noto Sans',
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 40),

                        // Right Column: Information & Prompts
                        Expanded(
                          flex: 6,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Gentle Prompt Tag
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.medicineBlush,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: AppColors.terracotta.withValues(alpha: 0.5),
                                    width: 1.5,
                                  ),
                                ),
                                child: const FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.medication_rounded,
                                        size: 20,
                                        color: AppColors.terracotta,
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        'Medicine time',
                                        style: TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.terracotta,
                                          fontFamily: 'Noto Sans',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),

                              // Medication Name
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  widget.medication.name,
                                  key: const Key('reminder_medication_name'),
                                  style: const TextStyle(
                                    fontSize: 40,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primaryText,
                                    fontFamily: 'Noto Sans',
                                    letterSpacing: -0.5,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),

                              // Medication Dose
                              Text(
                                widget.medication.dose,
                                key: const Key('reminder_medication_dose'),
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.secondaryText,
                                  fontFamily: 'Noto Sans',
                                ),
                              ),
                              const SizedBox(height: 18),

                              // Time window
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.wovenMat.withValues(alpha: 0.4),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.access_time_rounded,
                                        size: 18,
                                        color: AppColors.secondaryText,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Time: $windowStr',
                                        style: const TextStyle(
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
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Bottom Action Buttons (Large Touch Targets >= 76dp)
                  Row(
                    children: [
                      // "Taken" Button (Leaf green filled)
                      Expanded(
                        child: InkWell(
                          key: const Key('reminder_taken'),
                          onTap: _responding ? null : () => _respond('taken'),
                          borderRadius: BorderRadius.circular(24),
                          child: Container(
                            height: 76,
                            decoration: BoxDecoration(
                              color: AppColors.leafGreen,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: AppColors.leafGreenDark,
                                width: 2.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.leafGreen.withValues(alpha: 0.3),
                                  blurRadius: 12,
                                  offset: const Offset(0, 5),
                                ),
                              ],
                            ),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.check_circle_rounded,
                                      size: 30,
                                      color: AppColors.onColor,
                                    ),
                                    SizedBox(width: 12),
                                    Text(
                                      'Taken',
                                      style: TextStyle(
                                        fontSize: 24,
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
                      const SizedBox(width: 28),

                      // "Not now" Button (Zero-shame snooze)
                      Expanded(
                        child: InkWell(
                          key: const Key('reminder_not_now'),
                          onTap: _responding ? null : () => _respond('snoozed'),
                          borderRadius: BorderRadius.circular(24),
                          child: Container(
                            height: 76,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFFDF8),
                              borderRadius: BorderRadius.circular(24),
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
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.schedule_rounded,
                                      size: 30,
                                      color: AppColors.primaryText,
                                    ),
                                    SizedBox(width: 12),
                                    Text(
                                      'Not now',
                                      style: TextStyle(
                                        fontSize: 24,
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
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Custom painter rendering a realistic capsule pill illustration at visual size.
///
/// Shows a two-toned capsule (terracotta & warm ivory) with scored separation line,
/// gentle drop shadow, and smooth specular surface highlight.
class _PillVectorPainter extends CustomPainter {
  const _PillVectorPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const pillWidth = 170.0;
    const pillHeight = 76.0;
    const pillRadius = pillHeight / 2;

    // 1. Drop shadow underneath pill
    final shadowPaint = Paint()
      ..color = AppColors.primaryText.withValues(alpha: 0.12)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    final shadowRect = Rect.fromCenter(
      center: center + const Offset(0, 12),
      width: pillWidth * 0.95,
      height: pillHeight * 0.8,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(shadowRect, const Radius.circular(pillRadius)),
      shadowPaint,
    );

    // 2. Full pill boundary path
    final pillRect = Rect.fromCenter(
      center: center,
      width: pillWidth,
      height: pillHeight,
    );
    final pillRRect =
        RRect.fromRectAndRadius(pillRect, const Radius.circular(pillRadius));

    canvas.save();
    canvas.clipRRect(pillRRect);

    // Left Half (Terracotta)
    final leftRect = Rect.fromLTRB(
      pillRect.left,
      pillRect.top,
      center.dx,
      pillRect.bottom,
    );
    final terracottaPaint = Paint()
      ..color = AppColors.terracotta
      ..style = PaintingStyle.fill;
    canvas.drawRect(leftRect, terracottaPaint);

    // Right Half (Warm Ivory)
    final rightRect = Rect.fromLTRB(
      center.dx,
      pillRect.top,
      pillRect.right,
      pillRect.bottom,
    );
    final ivoryPaint = Paint()
      ..color = const Color(0xFFF9F3EA)
      ..style = PaintingStyle.fill;
    canvas.drawRect(rightRect, ivoryPaint);

    // Central scored joint shadow
    final jointShadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.18)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(center.dx - 1, pillRect.top),
      Offset(center.dx - 1, pillRect.bottom),
      jointShadowPaint,
    );

    final jointHighlightPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(center.dx + 1, pillRect.top),
      Offset(center.dx + 1, pillRect.bottom),
      jointHighlightPaint,
    );

    // Top Gloss Highlight
    final glossPath = Path();
    glossPath.moveTo(pillRect.left + 24, pillRect.top + 10);
    glossPath.quadraticBezierTo(
      center.dx,
      pillRect.top + 6,
      pillRect.right - 24,
      pillRect.top + 10,
    );
    final glossPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(glossPath, glossPaint);

    canvas.restore();

    // Subtle outer border
    final borderPaint = Paint()
      ..color = AppColors.border.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRRect(pillRRect, borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
