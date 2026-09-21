import 'package:smriti/core/sync/sync_gateway.dart';

/// Records every remote write in order, and can be told to fail.
class FakeSyncGateway implements SyncGateway {
  FakeSyncGateway({
    this.failUpsertOn,
    this.failUploadOn,
    this.rpcResponse,
    this.rpcThrows = false,
  });

  /// Table name whose upsert throws.
  final String? failUpsertOn;

  /// Object path whose upload throws.
  final String? failUploadOn;

  final Map<String, dynamic>? rpcResponse;
  final bool rpcThrows;

  /// table -> rows written.
  final Map<String, List<Map<String, dynamic>>> upserts = {};
  final Map<String, bool> upsertIgnoreDuplicates = {};
  final List<String> uploads = [];
  final List<Map<String, dynamic>> rpcCalls = [];

  /// Ordered log, so upload-before-row ordering can be asserted.
  final List<String> calls = [];

  List<Map<String, dynamic>> rowsFor(String table) => upserts[table] ?? const [];

  @override
  Future<void> upsert(
    String table,
    List<Map<String, dynamic>> rows, {
    bool ignoreDuplicates = true,
  }) async {
    calls.add('upsert:$table');
    upsertIgnoreDuplicates[table] = ignoreDuplicates;
    if (table == failUpsertOn) throw Exception('upsert failed for $table');
    upserts.putIfAbsent(table, () => []).addAll(rows);
  }

  @override
  Future<String> uploadFile(
    String bucket,
    String objectPath,
    List<int> bytes,
  ) async {
    calls.add('upload:$objectPath');
    if (objectPath == failUploadOn) throw Exception('upload failed');
    uploads.add('$bucket/$objectPath');
    return objectPath;
  }

  @override
  Future<Map<String, dynamic>?> rpc(
    String name,
    Map<String, dynamic> params,
  ) async {
    calls.add('rpc:$name');
    rpcCalls.add({'name': name, ...params});
    if (rpcThrows) throw Exception('rpc failed');
    return rpcResponse;
  }
}
