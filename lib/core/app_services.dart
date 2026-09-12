import 'dart:async';

import 'auth/pairing_service.dart';
import 'auth/supabase_bootstrap.dart';
import 'db/app_database.dart';
import 'db/database.dart';
import 'files/file_paths.dart';
import 'reminders/alarm_scheduler.dart';
import 'repo/ability_repo.dart';
import 'repo/content_repo.dart';
import 'repo/event_repo.dart';
import 'repo/memo_repo.dart';
import 'sync/content_puller.dart';
import 'sync/escalation_writer.dart';
import 'sync/event_pusher.dart';
import 'sync/heartbeat.dart';
import 'sync/media_downloader.dart';
import 'sync/memo_uploader.dart';
import 'sync/sync_engine.dart';
import 'kiosk/kiosk_service.dart';
import 'reminders/notifications.dart';
import 'voice/phrase_player.dart';
import 'voice/voice_commander.dart';

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
  }) : db = database ?? appDatabase {
    contentRepo = ContentRepo(db);
    eventRepo = EventRepo(db);
    abilityRepo = AbilityRepo(db);
    memoRepo = MemoRepo(db);

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
      // TODO(A11/A17): use connectivity_plus so a sync can also be triggered
      // when the connection comes back. Attempting and failing is harmless in
      // the meantime — every stage is independently wrapped.
      hasConnection: () async => true,
      isAuthenticated: () async => hasSupabaseSession(),
    );
  }

  /// Posts and clears dose notifications.
  late final ReminderNotifier reminderNotifier;

  final SmritiDatabase db;

  late final ContentRepo contentRepo;
  late final EventRepo eventRepo;
  late final AbilityRepo abilityRepo;
  late final MemoRepo memoRepo;
  late final AlarmScheduler alarmScheduler;
  late final PairingService pairingService;
  late final ContentPuller contentPuller;
  late final SyncEngine syncEngine;
  late final KioskService kioskService;
  late final PhrasePlayer phrasePlayer;
  late final VoiceCommander voiceCommander;

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
}
