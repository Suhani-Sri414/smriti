import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../core/app_services.dart';

/// Item type for unified timeline display on Screen 12 (Today).
enum TodayItemType { medication, routine }

/// Model representing a single event on the Today schedule.
class TodayTimelineItem {
  const TodayTimelineItem({
    required this.id,
    required this.title,
    this.subtitle,
    required this.timeMin,
    required this.type,
    required this.icon,
    this.isDone = false,
  });

  final String id;
  final String title;
  final String? subtitle;
  final int timeMin;
  final TodayItemType type;
  final IconData icon;
  final bool isDone;
}

/// Screen 12: Today (Daily Routine & Medication Timeline View).
///
/// Designed for a 1280×800 landscape tablet in North-East India.
/// Prototype board 12 specification:
/// "Done things fade; a terracotta rule marks now. Nothing is ever marked missed."
///
/// Combines medications and daily routine items into a chronological sequence.
/// Past/completed items fade with a gentle checkmark.
/// A distinct terracotta line with an illuminated pill badge marks the current time ("Now").
/// Strictly zero-shame: nothing is ever marked "missed" or shown in red.
class TodayScreen extends StatefulWidget {
  const TodayScreen({
    super.key,
    required this.services,
    this.now,
  });

  final AppServices services;
  final DateTime Function()? now;

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  late Future<List<TodayTimelineItem>> _itemsFuture;

  @override
  void initState() {
    super.initState();
    _itemsFuture = _loadSchedule();
  }

  DateTime _getNow() => (widget.now != null) ? widget.now!() : DateTime.now();

  Future<List<TodayTimelineItem>> _loadSchedule() async {
    final services = widget.services;
    final now = _getNow();
    final todayStartMs =
        DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
    final todayEndMs = todayStartMs + const Duration(days: 1).inMilliseconds;

    // 1. Fetch medications & routine items from local SQLite
    final medications = await services.contentRepo.getMedications(activeOnly: true);
    final routineItems = await services.contentRepo.getRoutineItems();

    // 2. Fetch today's reminder events to identify taken medications
    final reminderEvents = await (services.db.select(services.db.reminderEvents)
          ..where((t) => t.scheduledAt.isBetweenValues(todayStartMs, todayEndMs)))
        .get();

    final takenMedicationIds = <String>{};
    for (final event in reminderEvents) {
      if (event.outcome == 'taken') {
        takenMedicationIds.add(event.medicationId);
      }
    }

    final items = <TodayTimelineItem>[];

    // Map medications
    for (final med in medications) {
      final isDone = takenMedicationIds.contains(med.id);
      items.add(
        TodayTimelineItem(
          id: 'med_${med.id}',
          title: med.name,
          subtitle: med.dose,
          timeMin: med.chosenTimeMin,
          type: TodayItemType.medication,
          icon: Icons.medication_rounded,
          isDone: isDone,
        ),
      );
    }

    // Map routine items
    for (final r in routineItems) {
      items.add(
        TodayTimelineItem(
          id: 'routine_${r.id}',
          title: _formatRoutineLabel(r.labelKey),
          subtitle: null,
          timeMin: r.timeMin,
          type: TodayItemType.routine,
          icon: _resolveRoutineIcon(r.iconAsset, r.labelKey),
          isDone: false, // Routine items are activities without binary check off
        ),
      );
    }

    // Sort strictly chronologically by timeMin
    items.sort((a, b) => a.timeMin.compareTo(b.timeMin));
    return items;
  }

  static String _formatRoutineLabel(String labelKey) {
    // Gracefully clean up keys like "morning_tea" -> "Morning Tea"
    if (labelKey.contains('_')) {
      return labelKey
          .split('_')
          .map((word) => word.isNotEmpty
              ? '${word[0].toUpperCase()}${word.substring(1)}'
              : '')
          .join(' ');
    }
    return labelKey;
  }

  static IconData _resolveRoutineIcon(String iconAsset, String label) {
    final lower = (iconAsset + label).toLowerCase();
    if (lower.contains('tea') || lower.contains('chai')) {
      return Icons.emoji_food_beverage_rounded;
    }
    if (lower.contains('breakfast') ||
        lower.contains('lunch') ||
        lower.contains('dinner') ||
        lower.contains('meal') ||
        lower.contains('food')) {
      return Icons.restaurant_rounded;
    }
    if (lower.contains('bath') || lower.contains('wash')) {
      return Icons.shower_rounded;
    }
    if (lower.contains('walk') || lower.contains('exercise')) {
      return Icons.directions_walk_rounded;
    }
    if (lower.contains('pray') ||
        lower.contains('puja') ||
        lower.contains('pooja') ||
        lower.contains('temple')) {
      return Icons.self_improvement_rounded;
    }
    if (lower.contains('rest') || lower.contains('sleep') || lower.contains('nap')) {
      return Icons.bedtime_rounded;
    }
    return Icons.wb_sunny_rounded;
  }

  static String _formatMinutes(int minutes) {
    final h = (minutes ~/ 60).toString().padLeft(2, '0');
    final m = (minutes % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _formatDayTitle(DateTime now) {
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday'
    ];
    final dayName = days[now.weekday - 1];
    return 'Today · $dayName';
  }

  @override
  Widget build(BuildContext context) {
    final now = _getNow();
    final currentMinutes = now.hour * 60 + now.minute;

    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      body: SafeArea(
        child: Column(
          children: [
            // TOP BAR: Accessible Back Button, Title with Day, Live Clock
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 28, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Back Button (large touch target >= 56dp)
                  InkWell(
                    key: const Key('today_back_button'),
                    onTap: () => Navigator.of(context).pop(),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFDF8),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: AppColors.primaryText, width: 2.2),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.arrow_back_rounded,
                              size: 28, color: AppColors.primaryText),
                          SizedBox(width: 8),
                          Text(
                            'Home',
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

                  // Title: "Today · [Day]"
                  Text(
                    _formatDayTitle(now),
                    key: const Key('today_title'),
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryText,
                      fontFamily: 'Noto Sans',
                    ),
                  ),

                  // Clock
                  Text(
                    _formatMinutes(currentMinutes),
                    key: const Key('today_clock'),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryText,
                      fontFamily: 'Noto Sans',
                    ),
                  ),
                ],
              ),
            ),

            // MAIN SCHEDULE CONTENT
            Expanded(
              child: FutureBuilder<List<TodayTimelineItem>>(
                future: _itemsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.marigold,
                      ),
                    );
                  }

                  final items = snapshot.data ?? [];
                  if (items.isEmpty) {
                    return _buildEmptyState();
                  }

                  return _buildTimelineList(items, currentMinutes);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Empty state reassuring the elder when no items are scheduled.
  Widget _buildEmptyState() {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 48),
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 36),
        decoration: BoxDecoration(
          color: AppColors.raisedSurface,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: AppColors.border, width: 2),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.wb_sunny_rounded,
              size: 64,
              color: AppColors.marigold,
            ),
            const SizedBox(height: 18),
            const Text(
              'No tasks scheduled for today',
              key: Key('today_empty_message'),
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryText,
                fontFamily: 'Noto Sans',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Have a peaceful and restful day.',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w500,
                color: AppColors.secondaryText.withValues(alpha: 0.85),
                fontFamily: 'Noto Sans',
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Renders chronological timeline list with the terracotta "Now" rule.
  Widget _buildTimelineList(List<TodayTimelineItem> items, int currentMinutes) {
    // Find split index where items transition from past (< currentMinutes) to future (>= currentMinutes)
    int nowIndex = items.length;
    for (int i = 0; i < items.length; i++) {
      if (items[i].timeMin >= currentMinutes) {
        nowIndex = i;
        break;
      }
    }

    final listWidgets = <Widget>[];

    for (int i = 0; i < items.length; i++) {
      // Insert terracotta "Now" rule exactly at the current time transition
      if (i == nowIndex) {
        listWidgets.add(_buildTerracottaNowRule(currentMinutes));
      }

      final item = items[i];
      final isPast = item.timeMin < currentMinutes;
      listWidgets.add(_buildTimelineCard(item, isPast));
    }

    // If all items were in the past, place the "Now" rule at the bottom
    if (nowIndex == items.length) {
      listWidgets.add(_buildTerracottaNowRule(currentMinutes));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(40, 10, 40, 24),
      children: listWidgets,
    );
  }

  /// Prototype Board 12: "A terracotta rule marks now."
  Widget _buildTerracottaNowRule(int currentMinutes) {
    return Padding(
      key: const Key('today_now_marker'),
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 3,
              color: AppColors.terracotta,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.terracotta,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppColors.terracotta.withValues(alpha: 0.35),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.access_time_filled_rounded,
                  size: 20,
                  color: AppColors.onColor,
                ),
                const SizedBox(width: 8),
                Text(
                  'Now · ${_formatMinutes(currentMinutes)}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onColor,
                    fontFamily: 'Noto Sans',
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              height: 3,
              color: AppColors.terracotta,
            ),
          ),
        ],
      ),
    );
  }

  /// Single item card.
  /// "Done things fade; a terracotta rule marks now. Nothing is ever marked missed."
  Widget _buildTimelineCard(TodayTimelineItem item, bool isPast) {
    final isFaded = item.isDone || (isPast && item.type == TodayItemType.routine);

    final cardColor = isFaded
        ? AppColors.raisedSurface.withValues(alpha: 0.6)
        : const Color(0xFFFFFDF8);

    final borderColor = isFaded
        ? AppColors.border.withValues(alpha: 0.5)
        : (item.type == TodayItemType.medication
            ? AppColors.marigold.withValues(alpha: 0.8)
            : AppColors.border);

    return Opacity(
      opacity: isFaded ? 0.55 : 1.0,
      child: Container(
        key: Key('today_item_${item.id}'),
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor, width: 2),
          boxShadow: isFaded
              ? []
              : [
                  BoxShadow(
                    color: AppColors.primaryText.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Row(
          children: [
            // Time Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isFaded
                    ? AppColors.wovenMat.withValues(alpha: 0.4)
                    : AppColors.wovenMat.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _formatMinutes(item.timeMin),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: isFaded
                      ? AppColors.secondaryText
                      : AppColors.primaryText,
                  fontFamily: 'Noto Sans',
                ),
              ),
            ),
            const SizedBox(width: 20),

            // Icon Badge
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: item.type == TodayItemType.medication
                    ? (isFaded
                        ? AppColors.medicineBlush.withValues(alpha: 0.5)
                        : AppColors.medicineBlush)
                    : (isFaded
                        ? AppColors.raisedSurface
                        : const Color(0xFFF7ECDA)),
                shape: BoxShape.circle,
              ),
              child: Icon(
                item.icon,
                size: 28,
                color: item.type == TodayItemType.medication
                    ? AppColors.terracotta
                    : AppColors.primaryText,
              ),
            ),
            const SizedBox(width: 20),

            // Title & Subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.title,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: isFaded
                          ? AppColors.secondaryText
                          : AppColors.primaryText,
                      fontFamily: 'Noto Sans',
                    ),
                  ),
                  if (item.subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.subtitle!,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: AppColors.secondaryText,
                        fontFamily: 'Noto Sans',
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Status Indicator (Checkmark if done, never a "missed" indicator)
            if (item.isDone)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.leafGreen.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_rounded,
                  size: 24,
                  color: AppColors.leafGreen,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
