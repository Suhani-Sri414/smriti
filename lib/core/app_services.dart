import 'dart:async';

import 'auth/pairing_service.dart';
import 'auth/supabase_bootstrap.dart' as auth_boot;
import 'db/app_database.dart';
import 'db/database.dart';
import 'files/file_paths.dart';
import 'reminders/alarm_scheduler.dart';
import 'repo/ability_repo.dart';
import 'repo/content_repo.dart';
import 'repo/event_repo.dart';
import 'repo/memo_repo.dart';
import 'sync/connectivity_service.dart';
import 'sync/content_puller.dart';
import 'sync/escalation_writer.dart';
import 'sync/event_pusher.dart';
import 'sync/heartbeat.dart';
import 'sync/media_downloader.dart';
import 'sync/memo_uploader.dart';
import 'sync/storage_urls.dart';
import 'sync/sync_engine.dart';
import 'kiosk/kiosk_service.dart';
import 'progression/progression_repo.dart';
import 'progression/progression_service.dart';
import 'reminders/notifications.dart';
import 'voice/phrase_player.dart';
import 'voice/screen_reader_service.dart';
import 'voice/voice_commander.dart';
import 'voicebot/voicebot_controller.dart';

/// Builds the object graph the app runs on.
///
/// APP-BUILD-SPEC.md §4 has the UI reaching repositories through Riverpod
/// providers; this is the same shape by hand, and is the thing Riverpod would
/// replace. Until A10.5 nothing in `lib/` constructed the sync engine at all —
/// it existed only in tests — so a paired device never pulled content.
class AppServices {
  AppServices({
    SmritiDatabase? database,
    AlarmScheduler? alarmScheduler,
    ReminderNotifier? notifier,
    PairingService? pairingService,
    KioskHandler? kioskHandler,
    PhrasePlayer? phrasePlayer,
    VoiceCommander? voiceCommander,
    VoiceBotController? voiceBotController,
    ScreenReaderService? screenReaderService,
    ConnectivityService? connectivityService,
    bool enablePeriodicSync = false,
  }) : db = database ?? appDatabase {
    contentRepo = ContentRepo(db);
    eventRepo = EventRepo(db);
    abilityRepo = AbilityRepo(db);
    memoRepo = MemoRepo(db);
    progressionRepo = ProgressionRepo(db);
    progressionService = ProgressionService(repo: progressionRepo);

    this.connectivityService = connectivityService ?? ConnectivityService();

    this.alarmScheduler =
        alarmScheduler ?? AlarmScheduler(contentRepo: contentRepo);
    reminderNotifier = notifier ?? LocalReminderNotifier();

    this.pairingService = pairingService ??
        PairingService(configs: db.appConfigsDao, abilityRepo: abilityRepo);

    kioskService = KioskService(
      configs: db.appConfigsDao,
      handler: kioskHandler,
    );

    this.phrasePlayer = phrasePlayer ?? DiskAndAssetPhrasePlayer();
    this.voiceCommander = voiceCommander ?? SpeechToTextVoiceCommander();
    this.voiceBotController = voiceBotController ?? VoiceBotController();
    this.screenReaderService = screenReaderService ?? ScreenReaderService();

    contentPuller = ContentPuller(
      configs: db.appConfigsDao,
      contentRepo: contentRepo,
      mediaDownloader: MediaDownloader(),
      // Step 5 of the pull order: medication times may have changed, so the
      // alarms are rebuilt last.
      onContentChanged: () => this.alarmScheduler.rescheduleAll(),
    );

    syncEngine = SyncEngine(
      eventPusher: EventPusher(eventRepo: eventRepo, configs: db.appConfigsDao),
      escalationWriter:
          EscalationWriter(eventRepo: eventRepo, configs: db.appConfigsDao),
      memoUploader: MemoUploader(memoRepo: memoRepo, configs: db.appConfigsDao),
      contentPuller: contentPuller,
      heartbeat: Heartbeat(eventRepo: eventRepo, configs: db.appConfigsDao),
      configs: db.appConfigsDao,
      hasConnection: () => this.connectivityService.checkConnection(),
      isAuthenticated: () async => auth_boot.hasSupabaseSession(),
    );

    // Auto-sync whenever network connection is restored
    _connectivitySubscription =
        this.connectivityService.onConnectionRestored.listen((_) {
      unawaited(syncEngine.run(trigger: SyncTrigger.connectivity));
    });

    if (enablePeriodicSync) {
      startPeriodicSync();
    }
  }

  /// Starts periodic sync while the app is active (per spec §9).
  void startPeriodicSync({Duration interval = const Duration(minutes: 15)}) {
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = Timer.periodic(interval, (_) {
      unawaited(syncEngine.run(trigger: SyncTrigger.periodic));
    });
  }

  /// Posts and clears dose notifications.
  late final ReminderNotifier reminderNotifier;

  final SmritiDatabase db;

  late final ContentRepo contentRepo;
  late final EventRepo eventRepo;
  late final AbilityRepo abilityRepo;
  late final MemoRepo memoRepo;
  late final ProgressionRepo progressionRepo;
  late final ProgressionService progressionService;
  late final AlarmScheduler alarmScheduler;
  late final PairingService pairingService;
  late final ContentPuller contentPuller;
  late final SyncEngine syncEngine;
  late final KioskService kioskService;
  late final PhrasePlayer phrasePlayer;
  late final VoiceCommander voiceCommander;
  late final VoiceBotController voiceBotController;
  late final ScreenReaderService screenReaderService;
  late final ConnectivityService connectivityService;

  StreamSubscription<void>? _connectivitySubscription;
  Timer? _periodicSyncTimer;

  static const String patientIdKey = 'patientId';

  /// Records the elder's answer to a dose and tears down the rest of its
  /// ladder.
  ///
  /// Cancelling is the important half: a step 2 alarm left armed after the
  /// elder has taken their medicine places a real phone call to a family
  /// member for nothing.
  Future<void> respondToReminder({
    required String reminderEventId,
    required String outcome,
    DateTime? now,
  }) async {
    await eventRepo.recordReminderOutcome(
      id: reminderEventId,
      outcome: outcome,
      respondedAt: (now ?? DateTime.now()).millisecondsSinceEpoch,
    );

    await alarmScheduler.cancelLadder(reminderEventId);
    await reminderNotifier.cancelReminder(reminderEventId);

    // Get the answer upstream promptly; the server watchdog is watching for a
    // dose never reported.
    unawaited(syncEngine.run(trigger: SyncTrigger.manual));
  }

  /// Whether this tablet has been paired to a patient.
  Future<bool> isPaired() async {
    final patientId = await db.appConfigsDao.getValue(patientIdKey);
    return patientId != null && patientId.isNotEmpty;
  }

  /// Absolute path for a media path stored relative to the documents
  /// directory, e.g. `medications/photos/{id}.jpg`.
  Future<String> resolveMediaPath(String relativePath) =>
      FilePaths.absolute(relativePath);

  /// Resolves a family member or caregiver photo path to a fully qualified authenticated URL.
  static String resolvePhotoUrl(String? path) => StorageUrls.resolvePhotoUrl(path);

  /// Retrieves the active Supabase access token (JWT), or falls back to anon key.
  static String? getSupabaseAccessToken() => auth_boot.getSupabaseAccessToken();

  /// Releases active listeners and background timers.
  void dispose() {
    _connectivitySubscription?.cancel();
    _periodicSyncTimer?.cancel();
    connectivityService.dispose();
    voiceBotController.dispose();
    screenReaderService.dispose();
  }
}
