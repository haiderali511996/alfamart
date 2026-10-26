import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/app_database.dart';

/// Offline safety net: the whole database can be copied out (to WhatsApp,
/// Google Drive, USB…) and restored on the same or a new phone.
class BackupService {
  BackupService(this.database);
  final AppDatabase database;

  Future<File> createBackup() async {
    final dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'backups'));
    await dir.create(recursive: true);
    final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final target = File(p.join(dir.path, 'AlfaMart_Backup_$stamp.db'));
    // Flush the WAL into the main file so the copy is complete.
    await database.db.rawQuery('PRAGMA wal_checkpoint(FULL)');
    await database.close();
    try {
      await File(database.path).copy(target.path);
    } finally {
      await database.reopen();
    }
    return target;
  }

  /// Validates and restores. Returns false when the file is not a backup.
  Future<bool> restore(File file) async {
    final tmp = File(p.join((await getTemporaryDirectory()).path, 'restore_candidate.db'));
    await file.copy(tmp.path);
    if (!await AppDatabase.isValidBackup(tmp.path)) return false;
    // Keep a safety copy of the current data first.
    await createBackup();
    await database.replaceWith(tmp);
    return true;
  }
}
