import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:smriti/core/db/database.dart';
import 'package:smriti/core/repo/content_repo.dart';
import 'package:smriti/core/sync/content_puller.dart';
import 'package:smriti/core/sync/media_downloader.dart';

import '../repo/_test_db.dart';

/// Serves canned bytes, and records every request in order.
class FakeMediaFetcher implements MediaFetcher {
  FakeMediaFetcher({this.failOn, this.emptyOn});

  /// Object path that throws when requested.
  final String? failOn;

  /// Object path that returns zero bytes — a silently failed download.
  final String? emptyOn;

  final List<String> requested = [];

  @override
  Future<List<int>> download(String bucket, String objectPath) async {
    requested.add('$bucket/$objectPath');
    if (objectPath == failOn) throw Exception('network died');
    if (objectPath == emptyOn) return const [];
    return List<int>.filled(64, 7);
  }
}

/// Points the downloader at a scratch directory instead of app documents.
class TempMediaStorage implements MediaStorage {
  TempMediaStorage(this.root);

  final Directory root;

  @override
  Future<String> tempDirectory() => _ensure(p.join(root.path, 'tmp'));

  @override
  Future<String> directoryFor(MediaKind kind) => switch (kind) {
        MediaKind.personPhoto => _ensure(p.join(root.path, 'people', 'photos')),
        MediaKind.personVoice => _ensure(p.join(root.path, 'people', 'voice')),
        MediaKind.medicationPhoto =>
          _ensure(p.join(root.path, 'medications', 'photos')),
        MediaKind.medicationVoice =>
          _ensure(p.join(root.path, 'medications', 'voice')),
      };

  static Future<String> _ensure(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }
}

class FakeContentGateway implements ContentGateway {
  FakeContentGateway({this.remoteVersion, this.payload});

  final String? remoteVersion;
  final Map<String, dynamic>? payload;

  int versionChecks = 0;
  int payloadFetches = 0;

  @override
  Future<String?> fetchRemoteContentVersion(String patientId) async {
    versionChecks++;
    return remoteVersion;
  }

  @override
  Future<Map<String, dynamic>> fetchContent(String patientId) async {
    payloadFetches++;
    return payload ?? const {};
  }
}

/// A realistic `get_patient_content` payload.
Map<String, dynamic> contentPayload() => {
      'people': [
        {
          'id': 'per1',
          'name': 'Anjali',
          'relationship': 'daughter',
          'photo_path': 'patients/p1/people/per1.jpg',
          'voice_path': 'patients/p1/people/per1.m4a',
          'memory_prompt': 'She visits on Sundays.',
          'is_deceased': false,
          'sort_order': 1,
        },
        {
          'id': 'per2',
          'name': 'Bikash',
          'relationship': 'husband',
          'photo_path': 'patients/p1/people/per2.jpg',
          'is_deceased': true,
          'sort_order': 0,
        },
      ],
      'medications': [
        {
          'id': 'med1',
          'name': 'Donepezil',
          'dose': '5 mg',
          'pill_photo_path': 'patients/p1/meds/med1.jpg',
          'voice_path': 'patients/p1/meds/med1.m4a',
          'window_start_min': 480,
          'window_end_min': 600,
          'chosen_time_min': 540,
          'days_of_week': [1, 2, 3, 4, 5, 6, 7],
          'active': true,
        },
      ],
      'routine': [
        {
          'id': 'rt1',
          'time_min': 420,
          'label_key': 'routine.breakfast',
          'icon_asset': 'assets/icons/breakfast.png',
        },
      ],
    };

void main() {
  late SmritiDatabase db;
  late ContentRepo contentRepo;
  late Directory root;

  setUp(() async {
    db = newTestDb();
    contentRepo = ContentRepo(db);
    root = await Directory.systemTemp.createTemp('smriti_pull_');
    await db.appConfigsDao.setValue('patientId', 'p1');
  });

  tearDown(() async {
    await db.close();
    if (await root.exists()) await root.delete(recursive: true);
  });

  /// Records the pull's side effects in the order they happen.
  late List<String> order;

  ContentPuller newPuller({
    required FakeContentGateway gateway,
    required FakeMediaFetcher fetcher,
  }) {
    order = [];
    return ContentPuller(
      configs: db.appConfigsDao,
      contentRepo: contentRepo,
      mediaDownloader: MediaDownloader(
        fetcher: fetcher,
        storage: TempMediaStorage(root),
      ),
      gateway: gateway,
      onContentChanged: () async => order.add('rescheduleAlarms'),
    );
  }

  File localFile(String relative) =>
      File(p.normalize(p.join(root.path, relative)));

  test('pulls media, swaps rows, bumps version, then reschedules alarms',
      () async {
    final fetcher = FakeMediaFetcher();
    final puller = newPuller(
      gateway: FakeContentGateway(remoteVersion: '7', payload: contentPayload()),
      fetcher: fetcher,
    );

    final result = await puller.pull();
    expect(result.didUpdate, isTrue);
    expect(result.version, '7');

    // Every referenced object was fetched.
    expect(fetcher.requested, [
      'patient-media/patients/p1/people/per1.jpg',
      'patient-media/patients/p1/people/per2.jpg',
      'patient-media/patients/p1/people/per1.m4a',
      'patient-media/patients/p1/meds/med1.jpg',
      'patient-media/patients/p1/meds/med1.m4a',
    ]);

    // Files landed in the §6 layout, and tmp/ was drained.
    expect(await localFile('people/photos/per1.jpg').exists(), isTrue);
    expect(await localFile('people/voice/per1.m4a').exists(), isTrue);
    expect(await localFile('people/photos/per2.jpg').exists(), isTrue);
    expect(await localFile('medications/photos/med1.jpg').exists(), isTrue);
    expect(await localFile('medications/voice/med1.m4a').exists(), isTrue);
    expect(
      Directory(p.join(root.path, 'tmp')).listSync().whereType<File>(),
      isEmpty,
      reason: 'staged files are moved, not copied',
    );

    // Rows swapped in.
    final people = await contentRepo.getPeople();
    expect(people.map((x) => x.id), ['per2', 'per1']);
    final anjali = await contentRepo.getPerson('per1');
    expect(anjali!.name, 'Anjali');
    expect(anjali.photoPath, localFile('people/photos/per1.jpg').path);
    expect(anjali.voicePath, 'people/voice/per1.m4a');
    expect(anjali.memoryPrompt, 'She visits on Sundays.');
    expect((await contentRepo.getPerson('per2'))!.voicePath, isNull);

    final med = (await contentRepo.getMedications()).single;
    expect(med.name, 'Donepezil');
    expect(med.dose, '5 mg');
    expect(med.windowStartMin, 480);
    expect(med.chosenTimeMin, 540);
    expect(med.daysOfWeek, '1,2,3,4,5,6,7');
    expect(med.pillPhotoPath, 'medications/photos/med1.jpg');

    expect((await contentRepo.getRoutineItems()).single.labelKey,
        'routine.breakfast');

    // Version bumped, alarms rescheduled once and last.
    expect(await contentRepo.getContentVersion(), '7');
    expect(order, ['rescheduleAlarms']);
  });

  test('pulls the real live payload end to end', () async {
    final live = jsonDecode(
      File('test/fixtures/get_patient_content.json').readAsStringSync(),
    ) as Map<String, dynamic>;

    final fetcher = FakeMediaFetcher();
    final puller = newPuller(
      gateway: FakeContentGateway(remoteVersion: '7', payload: live),
      fetcher: fetcher,
    );

    final result = await puller.pull();
    expect(result.didUpdate, isTrue);
    expect(result.version, '7');

    // Only the two person photos exist as objects; both point at the same
    // remote file but land in separate local files.
    expect(fetcher.requested, [
      'patient-media/test/placeholder.jpg',
      'patient-media/test/placeholder.jpg',
    ]);
    expect(
      await localFile(
        'people/photos/1cda8709-d82e-4725-9e4f-97198052d57f.jpg',
      ).exists(),
      isTrue,
    );
    expect(
      await localFile(
        'people/photos/5b9e6f77-f579-4004-bef5-55d486ee5e55.jpg',
      ).exists(),
      isTrue,
    );

    final people = await contentRepo.getPeople();
    expect(people, hasLength(2));
    expect(people.first.name, 'Bina');
    expect(people.first.voicePath, isNull);

    final meds = await contentRepo.getMedications();
    expect(meds, hasLength(2));
    expect(meds.first.name, 'Metformin');
    expect(meds.first.chosenTimeMin, 500);
    expect(meds.first.daysOfWeek, '1,2,3,4,5,6,7');

    expect(await contentRepo.getRoutineItems(), hasLength(2));
    expect(await contentRepo.getContentVersion(), '7');
    expect(order, ['rescheduleAlarms']);
  });

  test('the payload version wins over a stale probe', () async {
    // Probe says 8, payload says 7: the rows we actually applied are v7.
    final live = jsonDecode(
      File('test/fixtures/get_patient_content.json').readAsStringSync(),
    ) as Map<String, dynamic>;

    final result = await newPuller(
      gateway: FakeContentGateway(remoteVersion: '8', payload: live),
      fetcher: FakeMediaFetcher(),
    ).pull();

    expect(result.version, '7');
    expect(await contentRepo.getContentVersion(), '7',
        reason: 'never record a version the local rows do not match');
  });

  test('a cheap version check skips the payload when already current',
      () async {
    await db.appConfigsDao.setValue('contentVersion', '7');
    final gateway =
        FakeContentGateway(remoteVersion: '7', payload: contentPayload());
    final fetcher = FakeMediaFetcher();

    final result = await newPuller(gateway: gateway, fetcher: fetcher).pull();

    expect(result.status, 'up-to-date');
    expect(gateway.versionChecks, 1);
    expect(gateway.payloadFetches, 0, reason: 'no payload for nothing');
    expect(fetcher.requested, isEmpty);
    expect(order, isEmpty, reason: 'alarms are not rescheduled for no change');
  });

  test('an older remote version does not downgrade local content', () async {
    await db.appConfigsDao.setValue('contentVersion', '9');
    final gateway =
        FakeContentGateway(remoteVersion: '7', payload: contentPayload());

    final result =
        await newPuller(gateway: gateway, fetcher: FakeMediaFetcher()).pull();

    expect(result.status, 'up-to-date');
    expect(gateway.payloadFetches, 0);
  });

  test('a failed download keeps the old content and does not bump the version',
      () async {
    // Seed a working previous content set.
    await contentRepo.replaceContent(
      people: [
        PeopleCompanion.insert(
          id: 'old',
          name: 'Old Person',
          relationship: 'friend',
          photoPath: 'people/photos/old.jpg',
          sortOrder: 0,
        ),
      ],
      medications: const [],
      routineItems: const [],
      contentVersion: '6',
    );

    final fetcher =
        FakeMediaFetcher(failOn: 'patients/p1/meds/med1.jpg');
    final puller = newPuller(
      gateway: FakeContentGateway(remoteVersion: '7', payload: contentPayload()),
      fetcher: fetcher,
    );

    await expectLater(puller.pull(), throwsA(isA<MediaDownloadException>()));

    // Old content survives, untouched.
    expect((await contentRepo.getPeople()).map((x) => x.id), ['old']);
    expect(await contentRepo.getContentVersion(), '6',
        reason: 'never bump the version ahead of verified media');
    expect(order, isEmpty, reason: 'alarms are not rescheduled on failure');

    // Nothing was moved into place, and tmp/ was cleaned up.
    expect(await localFile('people/photos/per1.jpg').exists(), isFalse);
    expect(
      Directory(p.join(root.path, 'tmp')).listSync().whereType<File>(),
      isEmpty,
    );
  });

  test('an empty download counts as a failure, not a valid file', () async {
    final fetcher =
        FakeMediaFetcher(emptyOn: 'patients/p1/people/per1.m4a');
    final puller = newPuller(
      gateway: FakeContentGateway(remoteVersion: '7', payload: contentPayload()),
      fetcher: fetcher,
    );

    await expectLater(puller.pull(), throwsA(isA<MediaDownloadException>()));

    expect(await contentRepo.getContentVersion(), isNull);
    expect(await contentRepo.getPeople(), isEmpty);
    expect(await localFile('people/photos/per1.jpg').exists(), isFalse);
  });

  test(
      'a failed person photo download saves person with empty photoPath and does not crash sync',
      () async {
    final fetcher =
        FakeMediaFetcher(failOn: 'patients/p1/people/per1.jpg');
    final puller = newPuller(
      gateway: FakeContentGateway(remoteVersion: '7', payload: contentPayload()),
      fetcher: fetcher,
    );

    final result = await puller.pull();
    expect(result.didUpdate, isTrue);

    final anjali = await contentRepo.getPerson('per1');
    expect(anjali, isNotNull);
    expect(anjali!.name, 'Anjali');
    expect(anjali.photoPath, isEmpty);
  });

  test('an unpaired device pulls nothing', () async {
    await db.appConfigsDao.deleteValue('patientId');
    final gateway = FakeContentGateway(remoteVersion: '7');

    final result =
        await newPuller(gateway: gateway, fetcher: FakeMediaFetcher()).pull();

    expect(result.status, 'skipped');
    expect(result.reason, 'not paired');
    expect(gateway.versionChecks, 0);
  });

  test('a patient with no remote content version is skipped', () async {
    final result = await newPuller(
      gateway: FakeContentGateway(remoteVersion: null),
      fetcher: FakeMediaFetcher(),
    ).pull();

    expect(result.status, 'skipped');
  });

  test('a second pull of the same version is a no-op', () async {
    final gateway =
        FakeContentGateway(remoteVersion: '7', payload: contentPayload());
    final fetcher = FakeMediaFetcher();

    final puller = newPuller(gateway: gateway, fetcher: fetcher);
    expect((await puller.pull()).didUpdate, isTrue);

    final again = newPuller(gateway: gateway, fetcher: fetcher);
    expect((await again.pull()).status, 'up-to-date');
    expect(fetcher.requested, hasLength(5), reason: 'no re-download');
  });

  group('payload parsing', () {
    /// The exact payload captured from the live `get_patient_content` RPC.
    Map<String, dynamic> livePayload() => jsonDecode(
          File('test/fixtures/get_patient_content.json').readAsStringSync(),
        ) as Map<String, dynamic>;

    test('parses the real live payload', () {
      final parsed = ContentPayloadParser.parse(livePayload());

      // Version is a top-level int in the live payload.
      expect(parsed.version, '7');

      expect(parsed.people, hasLength(2));
      final person = parsed.people.first;
      expect(person.id.value, '1cda8709-d82e-4725-9e4f-97198052d57f');
      expect(person.name.value, 'Bina');
      expect(person.relationship.value, 'daughter');
      expect(person.isDeceased.value, isFalse);
      expect(person.sortOrder.value, 0);
      expect(person.photoPath.value, 'test/placeholder.jpg');
      // JSON nulls stay null rather than becoming empty strings.
      expect(person.voicePath.value, isNull);
      expect(person.memoryPrompt.value, isNull);

      expect(parsed.medications, hasLength(2));
      final med = parsed.medications.first;
      expect(med.id.value, '12660487-f1b1-4641-8131-d72be0bb13c6');
      expect(med.name.value, 'Metformin');
      expect(med.dose.value, '500mg');
      expect(med.active.value, isTrue);
      expect(med.daysOfWeek.value, '1,2,3,4,5,6,7');
      expect(med.windowStartMin.value, 480);
      expect(med.windowEndMin.value, 540);
      expect(med.chosenTimeMin.value, 500);
      expect(med.pillPhotoPath.value, isNull);
      expect(med.voicePath.value, isNull);

      expect(parsed.routineItems, hasLength(2));
      final routine = parsed.routineItems.first;
      expect(routine.id.value, 'a2207b97-ab90-44c0-b1fb-a71e1e0fb9b4');
      expect(routine.timeMin.value, 480);
      expect(routine.labelKey.value, 'breakfast');
      expect(routine.iconAsset.value, 'icon_breakfast');

      // Only the two photos are downloadable; every other media field is null.
      expect(parsed.media, hasLength(2));
      expect(parsed.media.map((m) => m.objectPath),
          ['test/placeholder.jpg', 'test/placeholder.jpg']);
      expect(parsed.media.map((m) => m.kind),
          [MediaKind.personPhoto, MediaKind.personPhoto]);
      expect(
        parsed.media.map((m) => m.fileName),
        [
          '1cda8709-d82e-4725-9e4f-97198052d57f.jpg',
          '5b9e6f77-f579-4004-bef5-55d486ee5e55.jpg',
        ],
        reason: 'two people share one remote object but get separate local '
            'files',
      );
    });

    test('the escalation config is ignored, not mis-parsed', () {
      // No Drift table covers it yet; see the TODO in ContentPayloadParser.
      final parsed = ContentPayloadParser.parse({
        ...livePayload(),
        'escalation': {
          'ladder': [0, 15, 30],
          'primary_contact_phone': '+910000000000',
        },
      });

      expect(parsed.people, hasLength(2));
      expect(parsed.medications, hasLength(2));
      expect(parsed.version, '7');
    });

    test('days_of_week also accepts a JSON array', () {
      final parsed = ContentPayloadParser.parse({
        'medications': [
          {
            'id': 'med1',
            'name': 'Donepezil',
            'dose': '5 mg',
            'days_of_week': [1, 3, 5],
            'window_start_min': 480,
            'window_end_min': 600,
            'chosen_time_min': 540,
          },
        ],
      });

      expect(parsed.medications.single.daysOfWeek.value, '1,3,5');
    });

    test('rows without an id are dropped rather than crashing', () {
      final parsed = ContentPayloadParser.parse({
        'people': [
          {'name': 'No id here'},
          {'id': 'per1', 'name': 'Fine', 'relationship': 'son'},
        ],
        'medications': const [],
        'routine': const [],
      });

      expect(parsed.people, hasLength(1));
      expect(parsed.people.single.id.value, 'per1');
    });

    test('an empty payload parses to nothing', () {
      final parsed = ContentPayloadParser.parse(const {});
      expect(parsed.people, isEmpty);
      expect(parsed.medications, isEmpty);
      expect(parsed.routineItems, isEmpty);
      expect(parsed.media, isEmpty);
    });

    test('media refs all target the patient-media bucket', () {
      final parsed = ContentPayloadParser.parse(contentPayload());
      expect(parsed.media, hasLength(5));
      expect(
        parsed.media.every((m) => m.bucket == 'patient-media'),
        isTrue,
      );
      expect(
        parsed.media.map((m) => m.fileName),
        ['per1.jpg', 'per1.m4a', 'per2.jpg', 'med1.jpg', 'med1.m4a'],
      );
    });
  });
}
