import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../db/database.dart';
import 'ladder.dart';

/// Shows the dose reminder.
///
/// Abstracted so the ladder can be tested without a notification plugin; the
/// real implementation is [LocalReminderNotifier].
abstract class ReminderNotifier {
  Future<void> initialize();

  /// Full-screen, over the lock screen, with the pill photo and two actions.
  Future<void> showReminder({
    required String reminderEventId,
    required Medication medication,
    required int step,
    String? pillPhotoPath,
  });

  /// Clears the reminder once the elder has answered.
  Future<void> cancelReminder(String reminderEventId);
}

/// Notification payload actions.
const String takenActionId = 'reminder_taken';
const String notNowActionId = 'reminder_not_now';

/// Encodes/decodes what the notification carries back to the app.
class ReminderPayload {
  const ReminderPayload({
    required this.reminderEventId,
    required this.medicationId,
  });

  factory ReminderPayload.parse(String raw) {
    final parts = raw.split('|');
    return ReminderPayload(
      reminderEventId: parts.isNotEmpty ? parts[0] : '',
      medicationId: parts.length > 1 ? parts[1] : '',
    );
  }

  final String reminderEventId;
  final String medicationId;

  String encode() => '$reminderEventId|$medicationId';
}

class LocalReminderNotifier implements ReminderNotifier {
  LocalReminderNotifier({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  /// Separate channels so step 1 can be louder without re-creating a channel —
  /// Android ignores importance changes to an existing channel.
  static const String channelId = 'medication_reminder_v2';
  static const String loudChannelId = 'medication_reminder_v2_loud';

  @override
  Future<void> initialize() async {
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _plugin.initialize(settings);
  }

  @override
  Future<void> showReminder({
    required String reminderEventId,
    required Medication medication,
    required int step,
    String? pillPhotoPath,
  }) async {
    final louder = ReminderLadder.isLouder(step);

    // The pill photo goes in the notification itself, so the elder sees what to
    // take without unlocking anything. A missing file is skipped silently.
    StyleInformation? style;
    if (pillPhotoPath != null && File(pillPhotoPath).existsSync()) {
      style = BigPictureStyleInformation(
        FilePathAndroidBitmap(pillPhotoPath),
        hideExpandedLargeIcon: true,
      );
    }

    final details = AndroidNotificationDetails(
      louder ? loudChannelId : channelId,
      louder ? 'Medicine reminders (repeat)' : 'Medicine reminders',
      channelDescription: 'Reminds the elder to take a dose',
      importance: Importance.max,
      priority: Priority.high,
      // The whole point: wake the screen and take it over, per §10.
      fullScreenIntent: true,
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public,
      ongoing: true,
      autoCancel: false,
      playSound: true,
      enableVibration: true,
      audioAttributesUsage: AudioAttributesUsage.alarm,
      styleInformation: style,
      actions: const [
        AndroidNotificationAction(takenActionId, 'Taken',
            showsUserInterface: true),
        AndroidNotificationAction(notNowActionId, 'Not now',
            showsUserInterface: true),
      ],
    );

    await _plugin.show(
      _notificationId(reminderEventId),
      medication.name,
      medication.dose,
      NotificationDetails(android: details),
      payload: ReminderPayload(
        reminderEventId: reminderEventId,
        medicationId: medication.id,
      ).encode(),
    );
  }

  @override
  Future<void> cancelReminder(String reminderEventId) =>
      _plugin.cancel(_notificationId(reminderEventId));

  /// Stable per dose, so step 1 replaces step 0's notification rather than
  /// stacking a second one in front of the elder.
  static int _notificationId(String reminderEventId) =>
      ReminderLadder.stableHash(reminderEventId) & 0x7FFFFFFF;
}

/// Records calls instead of showing anything. Used by tests and by any surface
/// that must not post notifications.
class NoopReminderNotifier implements ReminderNotifier {
  final List<String> shown = [];
  final List<String> cancelled = [];

  @override
  Future<void> initialize() async {}

  @override
  Future<void> showReminder({
    required String reminderEventId,
    required Medication medication,
    required int step,
    String? pillPhotoPath,
  }) async {
    shown.add('$reminderEventId:step$step');
  }

  @override
  Future<void> cancelReminder(String reminderEventId) async {
    cancelled.add(reminderEventId);
  }
}
