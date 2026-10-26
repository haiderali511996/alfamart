/// Contract a future server must implement. The app is offline-first:
/// SQLite is the source of truth and every row carries `updated_at`,
/// `is_deleted` and `sync_status` (1 = changed locally, not yet pushed).
///
/// A REST server only needs two endpoints per table, e.g.
///   POST /sync/{table}/push   body: [rows]         -> 200
///   GET  /sync/{table}/pull?since=EPOCH_MS         -> [rows]
abstract class RemoteApi {
  bool get isConfigured;

  Future<void> push(String table, List<Map<String, Object?>> rows);

  Future<List<Map<String, Object?>>> pull(String table, DateTime since);
}

/// Used until a server exists. Sync is simply skipped.
class OfflineRemoteApi implements RemoteApi {
  @override
  bool get isConfigured => false;

  @override
  Future<void> push(String table, List<Map<String, Object?>> rows) async {}

  @override
  Future<List<Map<String, Object?>>> pull(String table, DateTime since) async => const [];
}
