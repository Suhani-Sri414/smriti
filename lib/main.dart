import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'app_colors.dart';
import 'core/app_services.dart';
import 'core/auth/supabase_bootstrap.dart';
import 'core/db/database.dart';
import 'core/reminders/reminder_isolate.dart';
import 'core/repo/content_repo.dart';
import 'screens/reminder_screen.dart';
import 'screens/startup_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await dotenv.load(fileName: 'assets/.env');
    debugPrint('[main] dotenv loaded successfully from assets/.env (API Key: ${dotenv.env['VOICEBOT_API_KEY'] != null ? "length ${dotenv.env['VOICEBOT_API_KEY']!.length}" : "null"})');
  } catch (e) {
    debugPrint('[main] Warning: dotenv failed to load assets/.env: $e');
  }

  await initSupabase();

  final services = AppServices();
  services.startPeriodicSync();

  // AndroidAlarmManager must be initialised before any alarm can be scheduled,
  // and the notification channels before any can be shown. Neither is fatal on
  // a platform that has no alarm manager, so failures do not block startup.
  try {
    await services.alarmScheduler.initialize();
    await services.reminderNotifier.initialize();
  } catch (_) {}

  runApp(MyApp(services: services));
}

/// Standalone entrypoint for ReminderActivity.
///
/// Runs in a dedicated engine when the device wakes over the lock screen.
/// Opens its own Drift connection and renders FullScreenReminderScreen.
@pragma('vm:entry-point')
void reminderMain(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  String? medicationId;
  String? reminderEventId;
  if (args.isNotEmpty && args[0].isNotEmpty) {
    medicationId = args[0];
  }
  if (args.length > 1 && args[1].isNotEmpty) {
    reminderEventId = args[1];
  }

  // Open a clean standalone database connection owned by ReminderActivity
  final db = SmritiDatabase.connect(await openConnectionForIsolate());
  final contentRepo = ContentRepo(db);

  Medication? medication;
  if (medicationId != null) {
    medication = await contentRepo.getMedication(medicationId);
  }

  if (medication == null) {
    final allMeds = await contentRepo.getMedications(activeOnly: true);
    if (allMeds.isNotEmpty) {
      medication = allMeds.first;
    }
  }

  if (medication == null) {
    // No medication available to display, exit activity
    SystemNavigator.pop();
    return;
  }

  final services = AppServices(database: db);

  runApp(FullScreenReminderApp(
    services: services,
    medication: medication,
    reminderEventId: reminderEventId,
  ));
}

class FullScreenReminderApp extends StatelessWidget {
  const FullScreenReminderApp({
    super.key,
    required this.services,
    required this.medication,
    this.reminderEventId,
  });

  final AppServices services;
  final Medication medication;
  final String? reminderEventId;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Medication Reminder',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.terracotta),
      ),
      home: FullScreenReminderScreen(
        services: services,
        medication: medication,
        reminderEventId: reminderEventId,
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Smriti',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.terracotta),
      ),
      home: StartupGate(services: services),
    );
  }
}
