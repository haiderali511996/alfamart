import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../app_database.dart';
import '../models/entity.dart';

/// Bumped after every write so screens can refresh.
class DataChangeNotifier extends ChangeNotifier {
  int _revision = 0;
  int get revision => _revision;
  void changed() {
    _revision++;
    notifyListeners();
  }
}

/// Who is performing a write (used for created_by/updated_by and the audit
/// trail).
class Actor {
  const Actor(this.id, this.name);
  final String id;
  final String name;
  static const system = Actor('system', 'System');
}

/// Generic repository over a synchronisable table. All deletes are soft
/// deletes so nothing financial is ever silently lost, and every change is
/// written to the audit log in the same transaction.
class Repository<T extends Entity> {
  Repository(this.database, this.table, this.fromMap, this.notifier, {required this.entityName});

  final AppDatabase database;
  final String table;
  final String entityName;
  final T Function(Map<String, Object?>) fromMap;
  final DataChangeNotifier notifier;

  Database get _db => database.db;

  Future<List<T>> query({
    String? where,
    List<Object?>? args,
    String? orderBy,
    bool includeDeleted = false,
    int? limit,
  }) async {
    final clauses = <String>[if (!includeDeleted) 'is_deleted = 0', if (where != null) '($where)'];
    final rows = await _db.query(
      table,
      where: clauses.isEmpty ? null : clauses.join(' AND '),
      whereArgs: args,
      orderBy: orderBy,
      limit: limit,
    );
    return rows.map(fromMap).toList();
  }

  Future<T?> getById(String id) async {
    final rows = await _db.query(table, where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : fromMap(rows.first);
  }

  Future<List<T>> inRange(String startDb, String endDb, {String? extraWhere, List<Object?>? extraArgs}) =>
      query(
        where: 'date BETWEEN ? AND ?${extraWhere == null ? '' : ' AND $extraWhere'}',
        args: [startDb, endDb, ...?extraArgs],
        orderBy: 'date DESC, created_at DESC',
      );

  Future<void> save(T item, Actor actor, {bool audit = true}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.transaction((txn) async {
      final existing = await txn.query(table, where: 'id = ?', whereArgs: [item.id], limit: 1);
      final values = {
        ...item.toMap(),
        'updated_at': now,
        'updated_by': actor.id,
        'sync_status': 1,
      };
      if (existing.isEmpty) {
        await txn.insert(table, {
          ...values,
          'created_at': now,
          'created_by': actor.id,
          'is_deleted': 0,
        });
      } else {
        await txn.update(table, values, where: 'id = ?', whereArgs: [item.id]);
      }
      if (audit) {
        await _audit(txn, actor, existing.isEmpty ? 'create' : 'update', item.id, item.describe(),
            before: existing.isEmpty ? null : existing.first, after: item.toMap());
      }
    });
    notifier.changed();
  }

  Future<void> softDelete(T item, Actor actor) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.transaction((txn) async {
      await txn.update(
        table,
        {'is_deleted': 1, 'updated_at': now, 'updated_by': actor.id, 'sync_status': 1},
        where: 'id = ?',
        whereArgs: [item.id],
      );
      await _audit(txn, actor, 'delete', item.id, item.describe(), before: item.toMap());
    });
    notifier.changed();
  }

  Future<void> _audit(
    DatabaseExecutor txn,
    Actor actor,
    String action,
    String entityId,
    String summary, {
    Map<String, Object?>? before,
    Map<String, Object?>? after,
  }) =>
      writeAudit(txn, actor, action, entityName, entityId, summary, before: before, after: after);

  static Future<void> writeAudit(
    DatabaseExecutor txn,
    Actor actor,
    String action,
    String entity,
    String entityId,
    String summary, {
    Map<String, Object?>? before,
    Map<String, Object?>? after,
  }) {
    // Never store password material in the audit log.
    Map<String, Object?>? clean(Map<String, Object?>? m) => m == null
        ? null
        : (Map.of(m)
          ..remove('password_hash')
          ..remove('salt'));
    return txn.insert('audit_log', {
      'ts': DateTime.now().millisecondsSinceEpoch,
      'user_id': actor.id,
      'user_name': actor.name,
      'action': action,
      'entity': entity,
      'entity_id': entityId,
      'summary': summary,
      'before_json': before == null ? null : jsonEncode(clean(before)),
      'after_json': after == null ? null : jsonEncode(clean(after)),
    });
  }
}
