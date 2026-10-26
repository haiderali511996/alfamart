import 'package:sqflite/sqflite.dart';

import '../data/app_database.dart';
import 'remote_api.dart';

class SyncResult {
  SyncResult(this.pushed, this.pulled);
  final int pushed;
  final int pulled;
}

/// Two-way, last-write-wins sync between the local database and a server.
/// Plug a real [RemoteApi] in `main.dart` when the server is ready – no
/// other code needs to change.
class SyncService {
  SyncService(this.database, this.api);

  final AppDatabase database;
  final RemoteApi api;
  static const _lastSyncKey = 'last_sync_at';

  Database get _db => database.db;

  Future<int> pendingCount() async {
    var total = 0;
    for (final t in AppDatabase.syncTables) {
      total += Sqflite.firstIntValue(await _db.rawQuery('SELECT COUNT(*) FROM $t WHERE sync_status = 1')) ?? 0;
    }
    return total;
  }

  Future<DateTime?> lastSync() async {
    final rows = await _db.query('settings', where: 'key = ?', whereArgs: [_lastSyncKey]);
    if (rows.isEmpty) return null;
    return DateTime.fromMillisecondsSinceEpoch(int.parse(rows.first['value'] as String));
  }

  Future<SyncResult> syncNow() async {
    if (!api.isConfigured) throw StateError('No server configured yet');
    final since = await lastSync() ?? DateTime.fromMillisecondsSinceEpoch(0);
    final startedAt = DateTime.now();
    var pushed = 0, pulled = 0;
    for (final table in AppDatabase.syncTables) {
      final pending = await _db.query(table, where: 'sync_status = 1');
      if (pending.isNotEmpty) {
        await api.push(table, pending);
        final ids = pending.map((r) => r['id']).toList();
        await _db.update(table, {'sync_status': 0},
            where: 'id IN (${List.filled(ids.length, '?').join(',')})', whereArgs: ids);
        pushed += pending.length;
      }
      final remote = await api.pull(table, since);
      for (final row in remote) {
        final local = await _db.query(table, where: 'id = ?', whereArgs: [row['id']], limit: 1);
        final remoteUpdated = (row['updated_at'] as int?) ?? 0;
        if (local.isEmpty || ((local.first['updated_at'] as int?) ?? 0) < remoteUpdated) {
          await _db.insert(table, {...row, 'sync_status': 0}, conflictAlgorithm: ConflictAlgorithm.replace);
          pulled++;
        }
      }
    }
    await _db.insert('settings', {'key': _lastSyncKey, 'value': '${startedAt.millisecondsSinceEpoch}'},
        conflictAlgorithm: ConflictAlgorithm.replace);
    return SyncResult(pushed, pulled);
  }
}
