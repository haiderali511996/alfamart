import 'package:sqflite/sqflite.dart';

import '../data/app_database.dart';
import '../data/models/app_user.dart';
import '../data/models/cash_handover.dart';
import '../data/models/cashier.dart';
import '../data/models/counter.dart';
import '../data/models/expense.dart';
import '../data/models/purchase.dart';
import '../data/models/shift_sale.dart';
import '../data/repositories/repository.dart';

/// Holds the database and one repository per table. Provided at the root of
/// the widget tree.
class AppServices {
  AppServices(this.database, this.notifier)
      : users = Repository(database, 'users', AppUser.fromMap, notifier, entityName: 'User'),
        counters = Repository(database, 'counters', Counter.fromMap, notifier, entityName: 'Counter'),
        cashiers = Repository(database, 'cashiers', Cashier.fromMap, notifier, entityName: 'Cashier'),
        shifts = Repository(database, 'shift_sales', ShiftSale.fromMap, notifier, entityName: 'Shift sale'),
        purchases = Repository(database, 'purchases', Purchase.fromMap, notifier, entityName: 'Purchase'),
        handovers =
            Repository(database, 'cash_handovers', CashHandover.fromMap, notifier, entityName: 'Cash to purchaser'),
        expenses = Repository(database, 'expenses', Expense.fromMap, notifier, entityName: 'Expense');

  final AppDatabase database;
  final DataChangeNotifier notifier;
  final Repository<AppUser> users;
  final Repository<Counter> counters;
  final Repository<Cashier> cashiers;
  final Repository<ShiftSale> shifts;
  final Repository<Purchase> purchases;
  final Repository<CashHandover> handovers;
  final Repository<Expense> expenses;

  Future<List<Counter>> activeCounters() =>
      counters.query(where: 'is_active = 1', orderBy: 'sort_order, name');

  Future<List<Cashier>> activeCashiers() => cashiers.query(where: 'is_active = 1', orderBy: 'name');

  Future<String?> getSetting(String key) async {
    final rows = await database.db.query('settings', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> setSetting(String key, String? value) async {
    await database.db.insert('settings', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
