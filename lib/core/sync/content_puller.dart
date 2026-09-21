import 'dart:io';

import 'package:drift/drift.dart' show Value;
// TEMPORARY DIAGNOSTIC import, for the [pull] logging below. Remove with it.
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../db/database.dart';
import '../db/dao/app_configs_dao.dart';
import '../repo/content_repo.dart';
import 'media_downloader.dart';

/// Storage buckets, per APP-BUILD-SPEC.md §7.
const String patientMediaBucket = 'patient-media';

class ContentPullException implements Exception {
  const ContentPullException(this.message);

  final String message;

  @override
  String toString() => 'ContentPullException: $message';
}

/// Outcome of one pull attempt.
class PullResult {
  const PullResult._(this.status, {this.version, this.reason});

  final String status;
  final String? version;
  final String? reason;

  factory PullResult.skipped(String reason) =>
      PullResult._('skipped', reason: reason);

  factory PullResult.upToDate(String version) =>
      PullResult._('up-to-date', version: version);

  factory PullResult.updated(String version) =>
      PullResult._('updated', version: version);

  bool get didUpdate => status == 'updated';

  @override
  String toString() =>
      'PullResult($status${version != null ? ' v$version' : ''}'
      '${reason != null ? ' - $reason' : ''})';
}

/// The remote calls a pull makes. Abstracted for testability; the Supabase
/// implementation lives below, inside `lib/core/sync/` as AGENTS.md
/// non-negotiable #1 requires.
abstract class ContentGateway {
  /// Cheap version probe — step 1, avoids pulling a full payload for nothing.
  Future<String?> fetchRemoteContentVersion(String patientId);

  /// Full payload via the `get_patient_content` RPC.
  Future<Map<String, dynamic>> fetchContent(String patientId);
}

class SupabaseContentGateway implements ContentGateway {
  const SupabaseContentGateway();

  @override
  Future<String?> fetchRemoteContentVersion(String patientId) async {
    final row = await Supabase.instance.client
        .from('patients')
        .select('content_version')
        .eq('id', patientId)
        .maybeSingle();
    final version = row?['content_version'];
    return version?.toString();
  }

  @override
  Future<Map<String, dynamic>> fetchContent(String patientId) async {
    final data = await Supabase.instance.client.rpc(
      'get_patient_content',
      params: {'p_patient_id': patientId},
    );
    if (data is Map) return Map<String, dynamic>.from(data);
    throw const ContentPullException('unexpected get_patient_content response');
  }
}

/// Parsed payload: rows ready for Drift, plus the media they reference.
class ParsedContent {
  const ParsedContent({
    required this.people,
    required this.medications,
    required this.routineItems,
    required this.media,
    this.version,
  });

  final List<PeopleCompanion> people;
  final List<MedicationsCompanion> medications;
  final List<RoutineItemsCompanion> routineItems;
  final List<MediaRef> media;

  /// The payload's own `version`. Authoritative for the rows it carries — the
  /// probe in step 1 could be stale if content changed between the two calls.
  final String? version;
}

/// Pulls patient content and applies it in the strict order §9 mandates:
/// media to tmp -> verify -> move into place -> atomic row swap that bumps
/// `contentVersion` -> reschedule alarms.
///
/// If anything before the swap fails, the previous content set stays intact and
/// `contentVersion` is left alone, so the next run retries cleanly.
class ContentPuller {
  ContentPuller({
    required this.configs,
    required this.contentRepo,
    required this.mediaDownloader,
    this.gateway = const SupabaseContentGateway(),
    this.onContentChanged,
  });

  final AppConfigsDao configs;
  final ContentRepo contentRepo;
  final MediaDownloader mediaDownloader;
  final ContentGateway gateway;

  /// Step 5: reschedule all alarms, because medication times may have changed.
  ///
  /// Called only after a successful swap. The alarm scheduler does not exist
  /// yet (task A11), so this is left injectable and defaults to a no-op stub.
  final Future<void> Function()? onContentChanged;

  static const String patientIdKey = 'patientId';

  Future<PullResult> pull() async {
    // TEMPORARY DIAGNOSTIC — whole body wrapped so a thrown pull is logged
    // here. SyncEngine catches content failures into `lastSyncError` and
    // carries on, so today a failed pull is completely silent.
    try {
      return await _pull();
    } catch (error, stack) {
      debugPrint('[pull] ===== pull() THREW =====');
      debugPrint('[pull] runtimeType : ${error.runtimeType}');
      debugPrint('[pull] toString    : $error');
      debugPrint('[pull] stack:\n$stack');
      debugPrint('[pull] ===== end =====');
      rethrow;
    }
  }

  Future<PullResult> _pull() async {
    debugPrint('[pull] --- pull() start ---');

    final patientId = await configs.getValue(patientIdKey);
    debugPrint('[pull] patientId: ${patientId ?? "(null)"}');
    if (patientId == null || patientId.isEmpty) {
      debugPrint('[pull] SKIPPED: not paired');
      return PullResult.skipped('not paired');
    }

    // 1. Cheap version check.
    final remoteVersion =
        await gateway.fetchRemoteContentVersion(patientId);
    final localVersion = await contentRepo.getContentVersion();
    debugPrint('[pull] version probe: remote=${remoteVersion ?? "(null)"} '
        'local=${localVersion ?? "(null)"} '
        'isNewer=${remoteVersion == null ? "n/a" : _isNewer(remoteVersion, localVersion)}');

    if (remoteVersion == null || remoteVersion.isEmpty) {
      debugPrint('[pull] SKIPPED: no remote content version');
      return PullResult.skipped('no remote content version');
    }

    if (!_isNewer(remoteVersion, localVersion)) {
      // If this prints while the home screen is empty, the local version was
      // bumped without the rows landing, and every future pull short-circuits
      // here forever.
      final counts = await _localRowCounts();
      debugPrint('[pull] UP-TO-DATE, nothing written. Local rows now: $counts');
      return PullResult.upToDate(remoteVersion);
    }

    // 2. Full payload.
    debugPrint('[pull] calling get_patient_content RPC for $patientId …');
    final payload = await gateway.fetchContent(patientId);
    debugPrint('[pull] RPC returned. keys=${payload.keys.toList()}');
    debugPrint('[pull] raw payload: $payload');

    final parsed = ContentPayloadParser.parse(payload);
    debugPrint('[pull] parsed: version=${parsed.version} '
        'people=${parsed.people.length} '
        'medications=${parsed.medications.length} '
        'routineItems=${parsed.routineItems.length} '
        'mediaRefs=${parsed.media.length}');
    for (final ref in parsed.media) {
      debugPrint('[pull]   media ref: $ref');
    }

    // 2b. Download people photos directly with graceful error handling
    // and stage them for atomic commit.
    final preparedPeople = await _downloadAndPreparePeople(
      ContentPayloadParser._list(payload, 'people'),
    );

    // 3. Media first: download to tmp, verify, then move into place.
    // Person photos are already downloaded and verified in step 2b, so filter them out of mediaRefs to stage.
    final mediaToStage = parsed.media
        .where((m) => m.kind != MediaKind.personPhoto)
        .toList();
    debugPrint('[pull] staging ${mediaToStage.length} media file(s) …');
    final List<StagedMedia> staged;
    try {
      staged = await mediaDownloader.stage(mediaToStage);
    } catch (e) {
      // Discard staged people photos if staging remaining media fails
      for (final s in preparedPeople.stagedPhotos) {
        final f = File(s.tempPath);
        if (await f.exists()) await f.delete();
      }
      rethrow;
    }

    final allStaged = [...preparedPeople.stagedPhotos, ...staged];
    debugPrint('[pull] staged ${allStaged.length} file(s) OK, committing …');
    await mediaDownloader.commit(allStaged);
    debugPrint('[pull] media committed to disk');

    // 4. Atomic swap; contentVersion is bumped inside the same transaction, so
    //    it can never be ahead of the rows it describes. The payload's own
    //    `version` wins over the probe, which could be stale if content changed
    //    between the two calls.
    final appliedVersion = parsed.version ?? remoteVersion;
    debugPrint('[pull] Drift transaction START '
        '(writing ${preparedPeople.companions.length} people, '
        '${parsed.medications.length} medications, '
        '${parsed.routineItems.length} routine items, '
        'version -> $appliedVersion)');
    await contentRepo.replaceContent(
      people: preparedPeople.companions,
      medications: parsed.medications,
      routineItems: parsed.routineItems,
      contentVersion: appliedVersion,
    );
    debugPrint('[pull] Drift transaction DONE');

    // Read back, so "wrote nothing" and "wrote and lost it" are separable.
    debugPrint('[pull] read-back after swap: ${await _localRowCounts()}');

    // 5. Alarms last.
    await onContentChanged?.call();
    debugPrint('[pull] --- pull() complete: updated to $appliedVersion ---');

    return PullResult.updated(appliedVersion);
  }

  /// Downloads people photos directly from Supabase Storage and records the
  /// absolute local file path into Drift SQLite.
  ///
  /// Staged to tmp/ first so that if overall media sync fails, partial files
  /// are discarded cleanly and not left in final directories.
  ///
  /// If a photo download fails, logs the error and gracefully sets the photoPath to
  /// empty string (so SQLite has no invalid path, and UI renders the fallback icon).
  Future<({List<PeopleCompanion> companions, List<StagedMedia> stagedPhotos})>
      _downloadAndPreparePeople(
    List<Map<String, dynamic>> peopleRows,
  ) async {
    final companions = <PeopleCompanion>[];
    final stagedPhotos = <StagedMedia>[];

    String photosDir;
    try {
      photosDir =
          await mediaDownloader.storage.directoryFor(MediaKind.personPhoto);
    } catch (_) {
      final docDir = await getApplicationDocumentsDirectory();
      photosDir = p.join(docDir.path, 'people', 'photos');
    }
    final tempRoot = await mediaDownloader.storage.tempDirectory();

    var sortOrder = 0;
    for (final raw in peopleRows) {
      // ignore: avoid_print
      print("DEBUG SYNC - Received Person Payload: $raw");

      final id = ContentPayloadParser._string(raw, 'id');
      if (id == null) continue;

      final rawPhotoPath = ContentPayloadParser._string(raw, 'photo_path') ??
          ContentPayloadParser._string(raw, 'image_path') ??
          ContentPayloadParser._string(raw, 'image_url') ??
          ContentPayloadParser._string(raw, 'photo_url');

      String? absoluteLocalPath;
      if (rawPhotoPath != null && rawPhotoPath.trim().isNotEmpty) {
        final cleanPath = _cleanStoragePath(rawPhotoPath, patientMediaBucket);
        try {
          final bytes = await _downloadPhotoBytes(cleanPath);
          if (bytes.isNotEmpty) {
            final tempPath = p.join(tempRoot, 'personPhoto_$id.jpg');
            final tempFile = File(tempPath);
            await tempFile.writeAsBytes(bytes, flush: true);
            if (await tempFile.exists() &&
                await tempFile.length() == bytes.length) {
              absoluteLocalPath = p.join(photosDir, '$id.jpg');
              stagedPhotos.add(
                StagedMedia(
                  ref: MediaRef(
                    bucket: patientMediaBucket,
                    objectPath: cleanPath,
                    kind: MediaKind.personPhoto,
                    ownerId: id,
                  ),
                  tempPath: tempPath,
                ),
              );
              debugPrint('[pull] Downloaded photo for person $id to $tempPath');
            }
          }
        } catch (e) {
          debugPrint(
              '[pull] Failed to download photo for person $id ($rawPhotoPath): $e');
          final existing = File(p.join(photosDir, '$id.jpg'));
          if (existing.existsSync()) {
            absoluteLocalPath = existing.path;
          } else {
            absoluteLocalPath = null;
          }
        }
      }

      final voiceObject = ContentPayloadParser._string(raw, 'voice_path');

      companions.add(
        PeopleCompanion.insert(
          id: id,
          name: ContentPayloadParser._string(raw, 'name') ?? '',
          relationship:
              ContentPayloadParser._string(raw, 'relationship') ?? '',
          photoPath: absoluteLocalPath ?? '',
          voicePath: Value(
            voiceObject == null
                ? null
                : ContentPayloadParser._localPath(MediaKind.personVoice, id),
          ),
          memoryPrompt:
              Value(ContentPayloadParser._string(raw, 'memory_prompt')),
          isDeceased:
              Value(ContentPayloadParser._bool(raw, 'is_deceased') ?? false),
          sortOrder: ContentPayloadParser._int(raw, 'sort_order') ?? sortOrder,
        ),
      );
      sortOrder++;
    }

    return (companions: companions, stagedPhotos: stagedPhotos);
  }

  Future<Uint8List> _downloadPhotoBytes(String cleanPath) async {
    // If a custom MediaFetcher is supplied (e.g. in test suites):
    if (mediaDownloader.fetcher is! SupabaseMediaFetcher) {
      final list = await mediaDownloader.fetcher.download(
        patientMediaBucket,
        cleanPath,
      );
      return Uint8List.fromList(list);
    }

    // In production with Supabase client:
    final Uint8List bytes = await Supabase.instance.client.storage
        .from(patientMediaBucket)
        .download(cleanPath);
    return bytes;
  }

  static String _cleanStoragePath(String raw, String bucket) {
    var clean = raw.trim();
    if (clean.contains('/$bucket/')) {
      clean = clean.substring(clean.indexOf('/$bucket/') + bucket.length + 2);
    } else if (clean.startsWith('$bucket/')) {
      clean = clean.substring(bucket.length + 1);
    }
    while (clean.startsWith('/')) {
      clean = clean.substring(1);
    }
    return clean;
  }

  /// TEMPORARY DIAGNOSTIC — what is actually in Drift right now.
  Future<String> _localRowCounts() async {
    try {
      final people = await contentRepo.getPeople();
      final medications = await contentRepo.getMedications(activeOnly: false);
      final routine = await contentRepo.getRoutineItems();
      return 'people=${people.length} medications=${medications.length} '
          'routine=${routine.length} '
          'contentVersion=${await contentRepo.getContentVersion() ?? "(null)"}';
    } catch (e) {
      return 'count failed: $e';
    }
  }

  /// Versions are opaque strings; compare numerically when both parse as ints,
  /// otherwise treat any difference as newer.
  static bool _isNewer(String remote, String? local) {
    if (local == null || local.isEmpty) return true;
    final remoteInt = int.tryParse(remote);
    final localInt = int.tryParse(local);
    if (remoteInt != null && localInt != null) return remoteInt > localInt;
    return remote != local;
  }
}

/// Maps the `get_patient_content` payload onto Drift rows.
///
/// Field names below are taken from a real payload captured from the live
/// backend, not inferred. The payload also carries `age`, `education_years`,
/// `lang_code`, `elder_name`, `script`, `timezone` and `lang_pack_version`,
/// which pairing already writes into `AppConfigs`; refreshing them from a pull
/// is not in this task's scope.
///
/// TODO(A10+): the payload's `escalation` object has nowhere to live yet — no
/// Drift table covers it, and APP-BUILD-SPEC.md §9 did not scope storage for
/// it. §7's `AppConfigs` key list already reserves `ladderConfigJson`,
/// `primaryContactPhone` and `secondaryContactPhone`, so it can be persisted
/// there once the reminder ladder needs it. Ignored for now (it is `null` in
/// the captured payload).
class ContentPayloadParser {
  static ParsedContent parse(Map<String, dynamic> payload) {
    final people = <PeopleCompanion>[];
    final medications = <MedicationsCompanion>[];
    final routineItems = <RoutineItemsCompanion>[];
    final media = <MediaRef>[];

    var sortOrder = 0;
    for (final jsonRow in _list(payload, 'people')) {
      // ignore: avoid_print
      print("DEBUG SYNC - Received Person Payload: $jsonRow");
      final id = _string(jsonRow, 'id');
      if (id == null) continue;

      final photoObject = _string(jsonRow, 'photo_path') ??
          _string(jsonRow, 'image_path') ??
          _string(jsonRow, 'image_url') ??
          _string(jsonRow, 'photo_url');
      final voiceObject = _string(jsonRow, 'voice_path');

      // Preserve the remote storage path / URL if provided, otherwise derive
      // the standard local slot per APP-BUILD-SPEC.md §6.
      people.add(
        PeopleCompanion.insert(
          id: id,
          name: _string(jsonRow, 'name') ?? '',
          relationship: _string(jsonRow, 'relationship') ?? '',
          photoPath: photoObject ?? _localPath(MediaKind.personPhoto, id),
          voicePath: Value(
            voiceObject == null ? null : _localPath(MediaKind.personVoice, id),
          ),
          memoryPrompt: Value(_string(jsonRow, 'memory_prompt')),
          isDeceased: Value(_bool(jsonRow, 'is_deceased') ?? false),
          sortOrder: _int(jsonRow, 'sort_order') ?? sortOrder,
        ),
      );
      sortOrder++;

      if (photoObject != null) {
        media.add(
          MediaRef(
            bucket: patientMediaBucket,
            objectPath: photoObject,
            kind: MediaKind.personPhoto,
            ownerId: id,
          ),
        );
      }
      if (voiceObject != null) {
        media.add(
          MediaRef(
            bucket: patientMediaBucket,
            objectPath: voiceObject,
            kind: MediaKind.personVoice,
            ownerId: id,
          ),
        );
      }
    }

    for (final row in _list(payload, 'medications')) {
      final id = _string(row, 'id');
      if (id == null) continue;

      final pillObject = _string(row, 'pill_photo_path');
      final voiceObject = _string(row, 'voice_path');

      medications.add(
        MedicationsCompanion.insert(
          id: id,
          name: _string(row, 'name') ?? '',
          dose: _string(row, 'dose') ?? '',
          pillPhotoPath: Value(
            pillObject == null
                ? null
                : _localPath(MediaKind.medicationPhoto, id),
          ),
          voicePath: Value(
            voiceObject == null
                ? null
                : _localPath(MediaKind.medicationVoice, id),
          ),
          windowStartMin: _int(row, 'window_start_min') ?? 0,
          windowEndMin: _int(row, 'window_end_min') ?? 0,
          chosenTimeMin: _int(row, 'chosen_time_min') ?? 0,
          daysOfWeek: _daysOfWeek(row) ?? '1,2,3,4,5,6,7',
          active: Value(_bool(row, 'active') ?? true),
        ),
      );

      if (pillObject != null) {
        media.add(
          MediaRef(
            bucket: patientMediaBucket,
            objectPath: pillObject,
            kind: MediaKind.medicationPhoto,
            ownerId: id,
          ),
        );
      }
      if (voiceObject != null) {
        media.add(
          MediaRef(
            bucket: patientMediaBucket,
            objectPath: voiceObject,
            kind: MediaKind.medicationVoice,
            ownerId: id,
          ),
        );
      }
    }

    for (final row in _list(payload, 'routine')) {
      final id = _string(row, 'id');
      if (id == null) continue;

      routineItems.add(
        RoutineItemsCompanion.insert(
          id: id,
          timeMin: _int(row, 'time_min') ?? 0,
          labelKey: _string(row, 'label_key') ?? '',
          iconAsset: _string(row, 'icon_asset') ?? '',
        ),
      );
    }

    return ParsedContent(
      people: people,
      medications: medications,
      routineItems: routineItems,
      media: media,
      // Arrives as an int in the live payload.
      version: payload['version']?.toString(),
    );
  }

  /// Local media paths are relative to the directories §6 fixes; the absolute
  /// prefix is resolved at read time by `FilePaths`.
  static String _localPath(MediaKind kind, String id) => switch (kind) {
        MediaKind.personPhoto => 'people/photos/$id.jpg',
        MediaKind.personVoice => 'people/voice/$id.m4a',
        MediaKind.medicationPhoto => 'medications/photos/$id.jpg',
        MediaKind.medicationVoice => 'medications/voice/$id.m4a',
      };

  /// The live payload sends `"1,2,3,4,5,6,7"`; a JSON array is also accepted
  /// because `Medications.daysOfWeek` stores the comma form either way.
  static String? _daysOfWeek(Map<String, dynamic> row) {
    final value = row['days_of_week'];
    if (value is List) return value.join(',');
    if (value is String && value.isNotEmpty) return value;
    return null;
  }

  static List<Map<String, dynamic>> _list(
    Map<String, dynamic> payload,
    String key,
  ) {
    final value = payload[key];
    if (value is! List) return const [];
    return value.whereType<Map>().map(Map<String, dynamic>.from).toList();
  }

  /// Nullable fields (`voice_path`, `pill_photo_path`, `memory_prompt`) arrive
  /// as JSON null in the live payload, so null and empty are both "absent".
  static String? _string(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value is String && value.isNotEmpty) return value;
    return null;
  }

  static int? _int(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}');
  }

  static bool? _bool(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value is bool) return value;
    if (value is String) return value.toLowerCase() == 'true';
    return null;
  }
}
