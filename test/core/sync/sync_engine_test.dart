import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:smriti/core/db/database.dart';
import 'package:smriti/core/repo/ability_repo.dart';
import 'package:smriti/core/repo/content_repo.dart';
import 'package:smriti/core/repo/event_repo.dart';
import 'package:smriti/core/repo/memo_repo.dart';
import 'package:smriti/core/sync/content_puller.dart';
import 'package:smriti/core/sync/escalation_writer.dart';
import 'package:smriti/core/sync/event_pusher.dart';
import 'package:smriti/core/sync/heartbeat.dart';
import 'package:smriti/core/sync/media_downloader.dart';
import 'package:smriti/core/sync/memo_uploader.dart';
import 'package:smriti/core/sync/sync_engine.dart';
import 'package:smriti/games/cognitive_game.dart';
import 'package:smriti/games/market_basket/market_basket_game.dart';
import 'package:smriti/games/session_runner.dart';

import '../repo/_test_db.dart';
import '_fake_sync_gateway.dart';
import 'content_puller_test.dart' show FakeMediaFetcher, TempMediaStorage;

void main() {
  late SmritiDatabase db;
  late EventRepo eventRepo;
  late Directory root;

  setUp(() async {
    db = newTestDb();
    eventRepo = EventRepo(db);
    root = await Directory.systemTemp.createTemp('smriti_engine_');
    await db.appConfigsDao.setValue('patientId', 'pat-1');
  });

  tearDown(() async {
    await db.close();
    if (await root.exists()) await root.delete(recursive: true);
  });

  SyncEngine newEngine(
    FakeSyncGateway gateway, {
    bool online = true,
    bool authed = true,
    ContentGateway? contentGateway,
    DateTime Function()? now,
  }) {
    return SyncEngine(
      eventPusher: EventPusher(
        eventRepo: eventRepo,
        configs: db.appConfigsDao,
        gateway: gateway,
      ),
      escalationWriter: EscalationWriter(
        eventRepo: eventRepo,
        configs: db.appConfigsDao,
        gateway: gateway,
      ),
      memoUploader: MemoUploader(
        memoRepo: MemoRepo(db),
        configs: db.appConfigsDao,
        gateway: gateway,
      ),
      contentPuller: ContentPuller(
        configs: db.appConfigsDao,
        contentRepo: ContentRepo(db),
        mediaDownloader: MediaDownloader(
          fetcher: FakeMediaFetcher(),
          storage: TempMediaStorage(root),
        ),
        gateway: contentGateway ?? _NoContentGateway(),
      ),
      heartbeat: Heartbeat(
        eventRepo: eventRepo,
        configs: db.appConfigsDao,
        gateway: gateway,
      ),
      configs: db.appConfigsDao,
      hasConnection: () async => online,
      isAuthenticated: () async => authed,
      now: now,
    );
  }

  test('playing a session then syncing lands rows with matching ids', () async {
    // Play a real session through the harness, exactly as the app would.
    final game = MarketBasketGame(random: Random(7));
    addTearDown(game.dispose);

    final runner = SessionRunner(
      eventRepo: eventRepo,
      abilityRepo: AbilityRepo(db),
      content: const GameContent(
        version: 'mock-1',
        marketItems: [
          MarketItem(
            id: 'rice',
            labelKey: 'item.rice',
            iconAsset: 'a.png',
            category: 'grain',
          ),
          MarketItem(
            id: 'dal',
            labelKey: 'item.dal',
            iconAsset: 'b.png',
            category: 'pulse',
          ),
          MarketItem(
            id: 'milk',
            labelKey: 'item.milk',
            iconAsset: 'c.png',
            category: 'dairy',
          ),
        ],
      ),
    );

    final sessionId = await runner.start([game]);
    final item = (await runner.nextItem(game))!;
    final written = runner.feedback.first;
    game.submit(
      item: item,
      chosenIds:
          (item.context['targetIds']! as List<Object?>).cast<String>(),
      initiationMs: 900,
      movementMs: 1400,
    );
    await written;
    await runner.end(completed: true);

    final localTrials = await eventRepo.getTrialsForSession(sessionId);
    expect(localTrials, hasLength(1));

    // Now sync.
    final gateway = FakeSyncGateway();
    final result = await newEngine(gateway).run(trigger: SyncTrigger.sessionEnd);
    expect(result.isOk, isTrue, reason: result.toString());

    // The remote rows carry the same client-generated ids as the local ones.
    expect(gateway.rowsFor('sessions').single['id'], sessionId);
    expect(gateway.rowsFor('events').single['id'], localTrials.single.id);
    expect(gateway.rowsFor('events').single['session_id'], sessionId);
    expect(gateway.rowsFor('events').single['patient_id'], 'pat-1');

    // And nothing is left queued.
    expect(await eventRepo.unsyncedCount(), 0);
  });

  test('one failing stage does not stop the others', () async {
    await eventRepo.insertSession(
      SessionsCompanion.insert(
        id: 'ses-1',
        startedAt: 1757199000000,
        gameIds: 'market_basket',
      ),
    );

    // Spec 9: a content-pull failure must never prevent event upload.
    final gateway = FakeSyncGateway();
    final result = await newEngine(
      gateway,
      contentGateway: _ThrowingContentGateway(),
    ).run();

    expect(result.status, 'partial');
    expect(result.errors.single, startsWith('content:'));

    // Events still went up, and the heartbeat still fired.
    expect(gateway.rowsFor('sessions'), hasLength(1));
    expect(gateway.rpcCalls.single['name'], 'device_heartbeat');
    expect(await eventRepo.unsyncedSessions(), isEmpty);

    // Recorded for the diagnostics screen only, never shown to the elder.
    expect(await db.appConfigsDao.getValue('lastSyncError'),
        startsWith('content:'));
  });

  test('offline and unauthenticated runs skip without touching the network',
      () async {
    final offline = FakeSyncGateway();
    expect((await newEngine(offline, online: false).run()).reason, 'offline');
    expect(offline.calls, isEmpty);

    final unauthed = FakeSyncGateway();
    expect((await newEngine(unauthed, authed: false).run()).reason,
        'not authed');
    expect(unauthed.calls, isEmpty);
  });

  test('runs are throttled, but a finished session always syncs', () async {
    var clock = DateTime(2025, 9, 7, 9, 30);
    final gateway = FakeSyncGateway();
    final engine = newEngine(gateway, now: () => clock);

    expect((await engine.run()).isOk, isTrue);

    // Too soon for a periodic run.
    clock = clock.add(const Duration(seconds: 30));
    expect((await engine.run()).reason, 'throttled');

    // A session ending overrides the throttle - that data matters most.
    expect(
      (await engine.run(trigger: SyncTrigger.sessionEnd)).isOk,
      isTrue,
    );

    // Connectivity regaining also overrides the throttle - pending data syncs immediately.
    clock = clock.add(const Duration(seconds: 30));
    expect(
      (await engine.run(trigger: SyncTrigger.connectivity)).isOk,
      isTrue,
    );

    clock = clock.add(const Duration(minutes: 3));
    expect((await engine.run()).isOk, isTrue);
  });

  test('the stage order puts the elder data first', () async {
    await eventRepo.insertSession(
      SessionsCompanion.insert(
        id: 'ses-1',
        startedAt: 1757199000000,
        gameIds: 'market_basket',
      ),
    );

    final gateway = FakeSyncGateway();
    await newEngine(gateway).run();

    expect(gateway.calls, ['upsert:sessions', 'rpc:device_heartbeat']);
  });

  test('offline activity is stored locally in SQLite and syncs when connection returns',
      () async {
    // 1. User does activity while offline
    await eventRepo.insertSession(
      SessionsCompanion.insert(
        id: 'ses-offline',
        startedAt: 1757199000000,
        gameIds: 'faces_of_my_family',
      ),
    );
    await eventRepo.insertTrial(
      TrialEventsCompanion.insert(
        id: 'trial-offline',
        sessionId: 'ses-offline',
        gameId: 'faces_of_my_family',
        domain: 'memory',
        itemId: 'item-1',
        itemDifficulty: 0.5,
        thetaBefore: 0.0,
        correct: true,
        initiationMs: 800,
        movementMs: 400,
        responseTimeMs: 1200,
        trialIndex: 0,
        ts: 1757199001000,
        hourOfDay: 14,
        tzOffsetMin: 330,
      ),
    );

    // Verify local SQLite has unsynced records
    expect(await eventRepo.unsyncedSessions(), hasLength(1));
    expect(await eventRepo.unsyncedTrials(), hasLength(1));

    // Offline run skips and doesn't touch network
    final gateway = FakeSyncGateway();
    final offlineEngine = newEngine(gateway, online: false);

    final offlineResult =
        await offlineEngine.run(trigger: SyncTrigger.sessionEnd);
    expect(offlineResult.reason, 'offline');
    expect(gateway.calls, isEmpty);
    expect(await eventRepo.unsyncedSessions(), hasLength(1));
    expect(await eventRepo.unsyncedTrials(), hasLength(1));

    // 2. Internet connection is restored
    final onlineEngine = newEngine(gateway, online: true);
    final restoreResult =
        await onlineEngine.run(trigger: SyncTrigger.connectivity);
    expect(restoreResult.isOk, isTrue);

    // Remote gateway received both the session and the trial
    expect(gateway.rowsFor('sessions').map((r) => r['id']),
        contains('ses-offline'));
    expect(gateway.rowsFor('events').map((r) => r['id']),
        contains('trial-offline'));

    // Local SQLite rows are now marked synced!
    expect(await eventRepo.unsyncedSessions(), isEmpty);
    expect(await eventRepo.unsyncedTrials(), isEmpty);
  });

  test('EventPusher flushes multiple batches of unsynced trials in one sync',
      () async {
    // Insert 25 trials while batchSize is 10
    for (int i = 0; i < 25; i++) {
      await eventRepo.insertTrial(
        TrialEventsCompanion.insert(
          id: 'trial-$i',
          sessionId: 'ses-batch',
          gameId: 'market_basket',
          domain: 'memory',
          itemId: 'item-$i',
          itemDifficulty: 0.5,
          thetaBefore: 0.0,
          correct: true,
          initiationMs: 800,
          movementMs: 400,
          responseTimeMs: 1200,
          trialIndex: i,
          ts: 1757199000000 + i * 1000,
          hourOfDay: 10,
          tzOffsetMin: 330,
        ),
      );
    }

    expect(await eventRepo.unsyncedTrials(limit: 50), hasLength(25));

    final gateway = FakeSyncGateway();
    final pusher = EventPusher(
      eventRepo: eventRepo,
      configs: db.appConfigsDao,
      gateway: gateway,
      batchSize: 10,
    );

    final pushed = await pusher.push();
    expect(pushed, 25);
    expect(gateway.rowsFor('events'), hasLength(25));
    expect(await eventRepo.unsyncedTrials(limit: 50), isEmpty);
  });

  group('Offline-first lifecycle: Test A, Test B, Test C', () {
    test('Test A: Online flow stores locally first, syncs, updates gateway',
        () async {
      final gateway = FakeSyncGateway();
      final engine = newEngine(gateway, online: true);

      // 1. Play game session locally
      final startedAt = DateTime.now().millisecondsSinceEpoch;
      await eventRepo.insertSession(
        SessionsCompanion.insert(
          id: 'ses-online',
          startedAt: startedAt,
          endedAt: Value(startedAt + 180000), // 3 min
          gameIds: 'market_basket',
          completed: const Value(true),
        ),
      );
      await eventRepo.insertTrial(
        TrialEventsCompanion.insert(
          id: 'tri-online',
          sessionId: 'ses-online',
          gameId: 'market_basket',
          domain: 'memory',
          itemId: 'mb_rice',
          itemDifficulty: 0.0,
          thetaBefore: 0.0,
          correct: true,
          initiationMs: 500,
          movementMs: 500,
          responseTimeMs: 1000,
          chosenId: const Value('rice'),
          errorClass: const Value(null),
          trialIndex: 0,
          ts: startedAt + 1000,
          hourOfDay: 10,
          tzOffsetMin: 330,
        ),
      );

      // 2. Confirm reminder event
      await eventRepo.insertReminderEvent(
        ReminderEventsCompanion.insert(
          id: 'rem-online',
          medicationId: 'med-paracetamol',
          scheduledAt: startedAt,
          firedAt: Value(startedAt),
          respondedAt: Value(startedAt + 5000),
          outcome: const Value('confirmed'),
          channel: 'in_app',
          ladderStep: 0,
        ),
      );

      // Verified stored in local SQLite first
      expect(await eventRepo.unsyncedSessions(), hasLength(1));
      expect(await eventRepo.unsyncedTrials(), hasLength(1));
      expect(await eventRepo.unsyncedReminderEvents(), hasLength(1));
      expect(await eventRepo.unsyncedCount(), 3);

      // 3. Sync
      final result = await engine.run(trigger: SyncTrigger.sessionEnd);
      expect(result.isOk, isTrue);

      // Remote backend has received the rows
      expect(gateway.rowsFor('sessions').single['id'], 'ses-online');
      expect(gateway.rowsFor('sessions').single['ended_at'], startedAt + 180000);
      expect(gateway.rowsFor('events').single['id'], 'tri-online');
      expect(gateway.rowsFor('reminder_events').single['outcome'], 'confirmed');

      // Local pending count decreases to zero
      expect(await eventRepo.unsyncedCount(), 0);
    });

    test('Test B & C: Offline activity persists in SQLite, increments pending, and auto-syncs on reconnect with original timestamps',
        () async {
      final gateway = FakeSyncGateway();

      // --- TEST B: OFFLINE ---
      final offlineEngine = newEngine(gateway, online: false);

      // Monday 10:00 AM (e.g. simulated Monday timestamp)
      final mondayTimestamp =
          DateTime(2026, 9, 14, 10, 0, 0).millisecondsSinceEpoch;

      // 1. Elder completes actions while offline
      await eventRepo.insertSession(
        SessionsCompanion.insert(
          id: 'ses-monday-offline',
          startedAt: mondayTimestamp,
          endedAt: Value(mondayTimestamp + 240000), // 4 minutes
          gameIds: 'market_basket',
          completed: const Value(true),
        ),
      );
      await eventRepo.insertTrial(
        TrialEventsCompanion.insert(
          id: 'tri-monday-offline',
          sessionId: 'ses-monday-offline',
          gameId: 'market_basket',
          domain: 'memory',
          itemId: 'mb_dal',
          itemDifficulty: -0.1,
          thetaBefore: 0.2,
          correct: true,
          initiationMs: 600,
          movementMs: 600,
          responseTimeMs: 1200,
          chosenId: const Value('dal'),
          errorClass: const Value(null),
          trialIndex: 0,
          ts: mondayTimestamp + 2000,
          hourOfDay: 10,
          tzOffsetMin: 330,
        ),
      );
      await eventRepo.insertReminderEvent(
        ReminderEventsCompanion.insert(
          id: 'rem-monday-offline',
          medicationId: 'med-bp',
          scheduledAt: mondayTimestamp,
          firedAt: Value(mondayTimestamp),
          respondedAt: Value(mondayTimestamp + 10000),
          outcome: const Value('confirmed'),
          channel: 'in_app',
          ladderStep: 0,
        ),
      );

      // Verify events are stored in SQLite and pending count increased
      expect(await eventRepo.unsyncedSessions(), hasLength(1));
      expect(await eventRepo.unsyncedTrials(), hasLength(1));
      expect(await eventRepo.unsyncedReminderEvents(), hasLength(1));
      expect(await eventRepo.unsyncedCount(), 3);

      // Offline sync attempt skips cleanly without touching network
      final offlineResult =
          await offlineEngine.run(trigger: SyncTrigger.sessionEnd);
      expect(offlineResult.reason, 'offline');
      expect(gateway.calls, isEmpty);
      // All 3 events remain intact in local SQLite
      expect(await eventRepo.unsyncedCount(), 3);

      // --- TEST C: RECONNECT (e.g. Thursday) ---
      final thursdayEngine = newEngine(gateway, online: true);

      // Connection restored triggers sync automatically
      final syncResult =
          await thursdayEngine.run(trigger: SyncTrigger.connectivity);
      expect(syncResult.isOk, isTrue);

      // All pending events uploaded to backend
      expect(gateway.rowsFor('sessions').map((r) => r['id']),
          contains('ses-monday-offline'));
      expect(gateway.rowsFor('events').map((r) => r['id']),
          contains('tri-monday-offline'));
      expect(gateway.rowsFor('reminder_events').map((r) => r['id']),
          contains('rem-monday-offline'));

      // Pending count drops to 0
      expect(await eventRepo.unsyncedCount(), 0);

      // CRITICAL CHECK: Timestamps reflect ORIGINAL event date (Monday), NOT sync date (Thursday)!
      final remoteSession = gateway
          .rowsFor('sessions')
          .firstWhere((r) => r['id'] == 'ses-monday-offline');
      final remoteTrial = gateway
          .rowsFor('events')
          .firstWhere((r) => r['id'] == 'tri-monday-offline');
      final remoteReminder = gateway
          .rowsFor('reminder_events')
          .firstWhere((r) => r['id'] == 'rem-monday-offline');

      expect(remoteSession['started_at'], mondayTimestamp);
      expect(remoteSession['ended_at'], mondayTimestamp + 240000);
      expect(remoteTrial['ts'], mondayTimestamp + 2000);
      expect(remoteReminder['scheduled_at'], mondayTimestamp);
    });
  });
}

/// Content gateway that reports no content, so the pull is a no-op.
class _NoContentGateway implements ContentGateway {
  @override
  Future<String?> fetchRemoteContentVersion(String patientId) async => null;

  @override
  Future<Map<String, dynamic>> fetchContent(String patientId) async => const {};
}

class _ThrowingContentGateway implements ContentGateway {
  @override
  Future<String?> fetchRemoteContentVersion(String patientId) async =>
      throw Exception('content service down');

  @override
  Future<Map<String, dynamic>> fetchContent(String patientId) async => const {};
}
