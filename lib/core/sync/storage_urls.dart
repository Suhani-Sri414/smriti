import 'package:supabase_flutter/supabase_flutter.dart';

import 'content_puller.dart' show patientMediaBucket;

/// Utility for resolving remote Supabase Storage paths into full URLs.
///
/// Keeps the `supabase_flutter` dependency scoped strictly inside `lib/core/sync/`
/// per AGENTS.md Rule 1.
class StorageUrls {
  static const String supabaseProjectUrl =
      'https://yzhtgpaekoqaszxgbeyn.supabase.co';

  /// Resolves a family member or caregiver photo path into an authenticated URL.
  ///
  /// Example URL structure:
  /// `https://[project_ref].supabase.co/storage/v1/object/authenticated/patient-media/$path`
  static String resolvePhotoUrl(String? path) =>
      resolveAuthenticatedUrl(path, bucket: patientMediaBucket);

  /// Resolves a storage path or full URL into a valid authenticated URL for media retrieval.
  ///
  /// - Returns `''` if [path] is null or empty.
  /// - If [path] is already an HTTP or HTTPS URL containing `/object/public/`,
  ///   rewrites it to `/object/authenticated/` so private buckets load cleanly.
  /// - Strips redundant bucket prefixes (e.g. `'patient-media/'`) and leading slashes.
  /// - Returns `$supabaseProjectUrl/storage/v1/object/authenticated/$bucket/$cleanPath`.
  static String resolveAuthenticatedUrl(
    String? path, {
    String bucket = patientMediaBucket,
  }) {
    if (path == null) return '';
    final trimmed = path.trim();
    if (trimmed.isEmpty) return '';

    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      if (trimmed.contains('/storage/v1/object/public/$bucket/')) {
        return trimmed.replaceFirst(
          '/storage/v1/object/public/$bucket/',
          '/storage/v1/object/authenticated/$bucket/',
        );
      }
      return trimmed;
    }

    var cleanPath = trimmed;
    if (cleanPath.startsWith('$bucket/')) {
      cleanPath = cleanPath.substring(bucket.length + 1);
    }
    while (cleanPath.startsWith('/')) {
      cleanPath = cleanPath.substring(1);
    }

    return '$supabaseProjectUrl/storage/v1/object/authenticated/$bucket/$cleanPath';
  }

  /// Resolves a storage path or full URL into a valid public URL for public media retrieval.
  static String resolvePublicUrl(
    String? path, {
    String bucket = patientMediaBucket,
  }) {
    if (path == null) return '';
    final trimmed = path.trim();
    if (trimmed.isEmpty) return '';

    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }

    var cleanPath = trimmed;
    if (cleanPath.startsWith('$bucket/')) {
      cleanPath = cleanPath.substring(bucket.length + 1);
    }
    while (cleanPath.startsWith('/')) {
      cleanPath = cleanPath.substring(1);
    }

    try {
      return Supabase.instance.client.storage
          .from(bucket)
          .getPublicUrl(cleanPath);
    } catch (_) {
      return '$supabaseProjectUrl/storage/v1/object/public/$bucket/$cleanPath';
    }
  }
}
