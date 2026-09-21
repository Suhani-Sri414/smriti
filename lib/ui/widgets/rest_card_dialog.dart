import 'package:flutter/material.dart';

import '../../app_colors.dart';
import '../../core/progression/play_policy.dart';
import '../../core/progression/progression_service.dart';

/// Shows the elder-friendly Daily Rest Card / Tea Break dialog if fatigue thresholds
/// or eye-break locks are active.
///
/// Returns `true` if the elder chose to "Keep playing" (or if no rest was needed),
/// and `false` if the elder chose "Take a break" or if games are locked.
Future<bool> maybeShowRestCardDialog(
  BuildContext context, {
  required ProgressionService progressionService,
  RestCardEvaluation? evaluation,
  DateTime? currentTime,
}) async {
  final now = currentTime ?? DateTime.now();
  final eval = evaluation ?? await progressionService.checkRestStatus(currentTime: now);

  if (eval.status == RestCardStatus.none) {
    return true;
  }

  if (!context.mounted) return false;

  final isLocked = eval.status == RestCardStatus.locked;
  final title = isLocked ? 'Games are Resting 🌙' : 'Time for a Tea Break 🍵';
  final message = isLocked
      ? 'You have played wonderfully today! Time to rest your eyes and have some tea. Games will return in a little while.'
      : 'You have played wonderfully today! Would you like to rest your eyes and have some tea?';

  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: Colors.white,
      titlePadding: const EdgeInsets.fromLTRB(28, 28, 28, 12),
      contentPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
      actionsPadding: const EdgeInsets.fromLTRB(28, 16, 28, 24),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 24,
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
            style: const TextStyle(
              fontSize: 18,
              height: 1.45,
              color: AppColors.primaryText,
            ),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.raisedSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.spa_rounded,
                  size: 20,
                  color: AppColors.leafGreen,
                ),
                const SizedBox(width: 8),
                Text(
                  'Play today: ${(eval.playSecondsToday / 60).toStringAsFixed(1)} mins',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.secondaryText,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        if (!isLocked)
          TextButton(
            key: const Key('rest_card_keep_playing_button'),
            onPressed: () async {
              Navigator.of(ctx).pop(true);
              await progressionService.recordRestAction(
                RestAction.keepPlaying,
                currentTime: now,
              );
            },
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text(
              'Keep playing',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AppColors.secondaryText,
              ),
            ),
          ),
        ElevatedButton(
          key: const Key('rest_card_take_break_button'),
          onPressed: () async {
            Navigator.of(ctx).pop(false);
            await progressionService.recordRestAction(
              RestAction.takeBreak,
              currentTime: now,
            );
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.terracotta,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: const Text(
            'Take a break',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );

  return result ?? false;
}
