import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Every remote write the sync layer performs.
///
/// Abstracted so the pushers are testable without a backend. The Supabase
/// implementation below is the only place these calls are made, which keeps
/// `supabase_flutter` inside `lib/core/sync/` (AGENTS.md non-negotiable #1).
abstract class SyncGateway {
  /// Insert-only upsert. Implementations must never read the rows back.
  Future<void> upsert(
    String table,
    List<Map<String, dynamic>> rows, {
    bool ignoreDuplicates = true,
  });

  /// Uploads bytes to a storage bucket. Returns the object path.
  Future<String> uploadFile(String bucket, String objectPath, List<int> bytes);

  Future<Map<String, dynamic>?> rpc(String name, Map<String, dynamic> params);
}

class SupabaseSyncGateway implements SyncGateway {
  const SupabaseSyncGateway();

  /// AGENTS.md non-negotiable #4: bare upsert, no `.select()` and no
  /// `RETURNING`. The device identity has insert-only access, so a read-back
  /// fails with a misleading row-level-security error even though the insert
  /// succeeded.
  @override
  Future<void> upsert(
    String table,
    List<Map<String, dynamic>> rows, {
    bool ignoreDuplicates = true,
  }) async {
    if (rows.isEmpty) return;
    await Supabase.instance.client.from(table).upsert(
          rows,
          onConflict: 'id',
          ignoreDuplicates: ignoreDuplicates,
        );
  }

  @override
  Future<String> uploadFile(
    String bucket,
    String objectPath,
    List<int> bytes,
  ) async {
    await Supabase.instance.client.storage.from(bucket).uploadBinary(
          objectPath,
          Uint8List.fromList(bytes),
          fileOptions: const FileOptions(upsert: true),
        );
    return objectPath;
  }

  @override
  Future<Map<String, dynamic>?> rpc(
    String name,
    Map<String, dynamic> params,
  ) async {
    final result =
        await Supabase.instance.client.rpc(name, params: params);
    if (result is Map) return Map<String, dynamic>.from(result);
    if (result is List && result.isNotEmpty && result.first is Map) {
      return Map<String, dynamic>.from(result.first as Map);
    }
    return null;
  }
}

