import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../files/file_paths.dart';

/// Where a downloaded file belongs on disk, per APP-BUILD-SPEC.md §6.
enum MediaKind {
  personPhoto,
  personVoice,
  medicationPhoto,
  medicationVoice,
}

extension MediaKindExtension on MediaKind {
  /// Filenames inside each directory are `{id}.{ext}`.
  String get extension => switch (this) {
        MediaKind.personPhoto || MediaKind.medicationPhoto => 'jpg',
        MediaKind.personVoice || MediaKind.medicationVoice => 'm4a',
      };
}

/// One file to fetch: a storage object, and the local slot it lands in.
class MediaRef {
  const MediaRef({
    required this.bucket,
    required this.objectPath,
    required this.kind,
    required this.ownerId,
  });

  final String bucket;
  final String objectPath;
  final MediaKind kind;

  /// Person or medication id — the local filename stem.
  final String ownerId;

  String get fileName => '$ownerId.${kind.extension}';

  @override
  String toString() => '$bucket/$objectPath -> ${kind.name}/$fileName';
}

/// A file downloaded and verified in tmp/, not yet moved into place.
class StagedMedia {
  const StagedMedia({required this.ref, required this.tempPath});

  final MediaRef ref;
  final String tempPath;
}

class MediaDownloadException implements Exception {
  const MediaDownloadException(this.message);

  final String message;

  @override
  String toString() => 'MediaDownloadException: $message';
}

/// Fetches bytes from Supabase Storage. Abstracted so the downloader is
/// testable without a network (AGENTS.md non-negotiable #1 keeps the Supabase
/// import inside `lib/core/sync/`).
abstract class MediaFetcher {
  Future<List<int>> download(String bucket, String objectPath);
}

class SupabaseMediaFetcher implements MediaFetcher {
  const SupabaseMediaFetcher();

  @override
  Future<List<int>> download(String bucket, String objectPath) {
    return Supabase.instance.client.storage.from(bucket).download(objectPath);
  }
}

/// Resolves the on-disk directories. Wraps [FilePaths] so tests can point at a
/// scratch directory without touching the real app documents directory.
abstract class MediaStorage {
  Future<String> tempDirectory();

  Future<String> directoryFor(MediaKind kind);
}

class AppMediaStorage implements MediaStorage {
  const AppMediaStorage();

  @override
  Future<String> tempDirectory() => FilePaths.temporary();

  @override
  Future<String> directoryFor(MediaKind kind) => switch (kind) {
        MediaKind.personPhoto => FilePaths.peoplePhotos(),
        MediaKind.personVoice => FilePaths.peopleVoice(),
        MediaKind.medicationPhoto => FilePaths.medicationPhotos(),
        MediaKind.medicationVoice => FilePaths.medicationVoice(),
      };
}

/// Downloads content media to tmp/, verifies it, and only then moves it into
/// place — steps 3 of the pull order in APP-BUILD-SPEC.md §9.
///
/// Nothing is moved until every file has been fetched and verified, so a
/// download that dies halfway leaves the previous, fully-working media set
/// untouched.
class MediaDownloader {
  MediaDownloader({
    MediaFetcher fetcher = const SupabaseMediaFetcher(),
    MediaStorage storage = const AppMediaStorage(),
  })  : _fetcher = fetcher,
        _storage = storage;

  final MediaFetcher _fetcher;
  final MediaStorage _storage;

  MediaFetcher get fetcher => _fetcher;
  MediaStorage get storage => _storage;

  /// Fetches everything into tmp/ and verifies it is complete.
  ///
  /// Throws [MediaDownloadException] if any file fails, after cleaning up the
  /// partial downloads it made.
  Future<List<StagedMedia>> stage(List<MediaRef> refs) async {
    final tempRoot = await _storage.tempDirectory();
    final staged = <StagedMedia>[];

    try {
      for (final ref in refs) {
        final bytes = await _fetcher.download(ref.bucket, ref.objectPath);

        // An empty file is a failed download, not a valid asset.
        if (bytes.isEmpty) {
          throw MediaDownloadException('empty download for $ref');
        }

        final tempPath = p.join(tempRoot, '${ref.kind.name}_${ref.fileName}');
        final file = File(tempPath);
        await file.writeAsBytes(bytes, flush: true);

        // Verify what actually landed on disk, not what we think we wrote.
        if (!await file.exists() || await file.length() != bytes.length) {
          throw MediaDownloadException('incomplete write for $ref');
        }

        staged.add(StagedMedia(ref: ref, tempPath: tempPath));
      }
    } catch (e) {
      await _discard(staged);
      if (e is MediaDownloadException) rethrow;
      throw MediaDownloadException('$e');
    }

    return staged;
  }

  /// Moves verified files from tmp/ into their final directories.
  Future<void> commit(List<StagedMedia> staged) async {
    for (final item in staged) {
      final directory = await _storage.directoryFor(item.ref.kind);
      final destination = p.join(directory, item.ref.fileName);
      final source = File(item.tempPath);

      try {
        await source.rename(destination);
      } on FileSystemException {
        // rename fails across filesystems; fall back to copy-then-delete.
        await source.copy(destination);
        await source.delete();
      }
    }
  }

  /// Removes staged files. Safe to call on a partial list.
  Future<void> _discard(List<StagedMedia> staged) async {
    for (final item in staged) {
      final file = File(item.tempPath);
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  /// Clears anything left in tmp/ from an interrupted run.
  Future<void> clearTemp() async {
    final directory = Directory(await _storage.tempDirectory());
    if (!await directory.exists()) return;
    await for (final entity in directory.list()) {
      if (entity is File) await entity.delete();
    }
  }
}
