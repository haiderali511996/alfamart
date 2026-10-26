import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

/// Local SQLite database. Everything works fully offline; every business
/// table carries sync columns so a future server can be added without a
/// schema rewrite.
class AppDatabase {
  AppDatabase._(this._db, this.path);

  static const fileName = 'alfamart_cashflow.db';
  static const schemaVersion = 1;

  /// Tables that are mirrored to the server once sync is enabled.
  static const syncTables = [
    'users',
    'counters',
    'cashiers',
    'shift_sales',
    'purchases',
    'cash_handovers',
    'expenses',
  ];

  Database _db;
  final String path;

  Database get db => _db;

  static Future<String> defaultPath() async => p.join(await getDatabasesPath(), fileName);

  static Future<AppDatabase> open() async {
    final path = await defaultPath();
    return AppDatabase._(await _openAt(path), path);
  }

  static Future<Database> _openAt(String path) => openDatabase(
        path,
        version: schemaVersion,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: _create,
        onUpgrade: _upgrade,
      );

  Future<void> reopen() async {
    if (_db.isOpen) await _db.close();
    _db = await _openAt(path);
  }

  Future<void> close() => _db.close();

  /// Replaces the database file with a backup and reopens it.
  Future<void> replaceWith(File backup) async {
    await _db.close();
    await backup.copy(path);
    _db = await _openAt(path);
  }

  static const _meta = '''
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    created_by TEXT,
    updated_by TEXT,
    is_deleted INTEGER NOT NULL DEFAULT 0,
    sync_status INTEGER NOT NULL DEFAULT 1
  ''';

  static Future<void> _create(Database db, int version) async {
    final batch = db.batch();
    batch.execute('''
      CREATE TABLE users (
        id TEXT PRIMARY KEY,
        username TEXT NOT NULL UNIQUE COLLATE NOCASE,
        full_name TEXT NOT NULL,
        role TEXT NOT NULL,
        password_hash TEXT NOT NULL,
        salt TEXT NOT NULL,
        iterations INTEGER NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        failed_attempts INTEGER NOT NULL DEFAULT 0,
        locked_until INTEGER,
        last_login INTEGER,
        $_meta
      )''');
    batch.execute('''
      CREATE TABLE counters (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        sort_order INTEGER NOT NULL DEFAULT 0,
        is_active INTEGER NOT NULL DEFAULT 1,
        $_meta
      )''');
    batch.execute('''
      CREATE TABLE cashiers (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        phone TEXT,
        counter_id TEXT REFERENCES counters(id),
        is_active INTEGER NOT NULL DEFAULT 1,
        $_meta
      )''');
    batch.execute('''
      CREATE TABLE shift_sales (
        id TEXT PRIMARY KEY,
        date TEXT NOT NULL,
        counter_id TEXT NOT NULL REFERENCES counters(id),
        cashier_id TEXT NOT NULL REFERENCES cashiers(id),
        start_time TEXT,
        end_time TEXT,
        opening_cash INTEGER NOT NULL DEFAULT 0,
        cash INTEGER NOT NULL DEFAULT 0,
        pos INTEGER NOT NULL DEFAULT 0,
        online INTEGER NOT NULL DEFAULT 0,
        jazzcash INTEGER NOT NULL DEFAULT 0,
        closing_cash INTEGER,
        notes TEXT,
        $_meta
      )''');
    batch.execute('''
      CREATE TABLE purchases (
        id TEXT PRIMARY KEY,
        date TEXT NOT NULL,
        amount INTEGER NOT NULL,
        supplier TEXT,
        invoice_no TEXT,
        payment_method TEXT NOT NULL,
        description TEXT,
        $_meta
      )''');
    batch.execute('''
      CREATE TABLE cash_handovers (
        id TEXT PRIMARY KEY,
        date TEXT NOT NULL,
        time TEXT,
        counter_id TEXT NOT NULL REFERENCES counters(id),
        cashier_id TEXT NOT NULL REFERENCES cashiers(id),
        purchaser_name TEXT NOT NULL,
        amount INTEGER NOT NULL,
        purpose TEXT,
        $_meta
      )''');
    batch.execute('''
      CREATE TABLE expenses (
        id TEXT PRIMARY KEY,
        date TEXT NOT NULL,
        amount INTEGER NOT NULL,
        category TEXT NOT NULL,
        counter_id TEXT REFERENCES counters(id),
        cashier_id TEXT REFERENCES cashiers(id),
        payment_method TEXT NOT NULL,
        description TEXT,
        $_meta
      )''');
    batch.execute('''
      CREATE TABLE audit_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ts INTEGER NOT NULL,
        user_id TEXT,
        user_name TEXT,
        action TEXT NOT NULL,
        entity TEXT NOT NULL,
        entity_id TEXT,
        summary TEXT,
        before_json TEXT,
        after_json TEXT
      )''');
    batch.execute('CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT)');
    for (final t in ['shift_sales', 'purchases', 'cash_handovers', 'expenses']) {
      batch.execute('CREATE INDEX idx_${t}_date ON $t(date)');
    }
    batch.execute('CREATE INDEX idx_audit_ts ON audit_log(ts)');

    // The mart has two counters to begin with; admins can rename/add more.
    final now = DateTime.now().millisecondsSinceEpoch;
    for (var i = 1; i <= 2; i++) {
      batch.insert('counters', {
        'id': const Uuid().v4(),
        'name': 'Counter $i',
        'sort_order': i,
        'is_active': 1,
        'created_at': now,
        'updated_at': now,
        'created_by': 'system',
        'updated_by': 'system',
      });
    }
    await batch.commit(noResult: true);
  }

  static Future<void> _upgrade(Database db, int from, int to) async {
    // Future schema migrations go here, e.g. `if (from < 2) { ... }`.
  }

  /// Checks that a file looks like a backup made by this app.
  static Future<bool> isValidBackup(String filePath) async {
    Database? probe;
    try {
      probe = await openReadOnlyDatabase(filePath);
      final rows = await probe.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('users','shift_sales','counters')");
      return rows.length == 3;
    } catch (_) {
      return false;
    } finally {
      await probe?.close();
    }
  }
}
