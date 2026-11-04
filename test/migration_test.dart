// Upgrading the app must keep the data already on the phone.
import 'dart:io';

import 'package:alfamart_cashflow/data/app_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('v1 database upgrades to v2 and keeps purchases', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // Own file, so it can run alongside the UI test.
    final path = p.join(await getDatabasesPath(), 'migration_test.db');
    if (File(path).existsSync()) File(path).deleteSync();

    // A version 1 database as shipped in the first APK.
    final v1 = await openDatabase(
      path,
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
        CREATE TABLE purchases (
          id TEXT PRIMARY KEY, date TEXT NOT NULL, amount INTEGER NOT NULL, supplier TEXT, invoice_no TEXT,
          payment_method TEXT NOT NULL, description TEXT,
          created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, created_by TEXT, updated_by TEXT,
          is_deleted INTEGER NOT NULL DEFAULT 0, sync_status INTEGER NOT NULL DEFAULT 1)''');
        await db.insert('purchases', {
          'id': 'p1',
          'date': '2026-11-01',
          'amount': 500000,
          'payment_method': 'cash',
          'created_at': 0,
          'updated_at': 0,
        });
      },
    );
    await v1.close();

    final db = await AppDatabase.open(path: path);
    final cols = (await db.db.rawQuery('PRAGMA table_info(purchases)')).map((r) => r['name']).toList();
    expect(cols, contains('purchaser_name'));
    expect((await db.db.query('purchases')).single['amount'], 500000);
    await db.db.insert('purchaser_advances', {
      'id': 'a1',
      'date': '2026-11-04',
      'purchaser_name': 'Kamran',
      'amount': 20000000,
      'created_at': 0,
      'updated_at': 0,
    });
    expect(await db.db.query('purchaser_advances'), hasLength(1));
    await db.close();
    File(path).deleteSync();
  });
}
