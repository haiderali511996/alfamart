import 'package:intl/intl.dart';

import '../core/date_range.dart';
import '../core/enums.dart';
import '../data/models/cash_handover.dart';
import '../data/models/cashier.dart';
import '../data/models/counter.dart';
import '../data/models/expense.dart';
import '../data/models/purchase.dart';
import '../data/models/shift_sale.dart';
import 'app_services.dart';

class CashierSummary {
  CashierSummary(this.cashierId, this.name);
  final String cashierId;
  final String name;
  int shifts = 0;
  final Map<PaymentMethod, int> byMethod = {for (final m in PaymentMethod.salesMethods) m: 0};
  int handovers = 0;
  int cashExpenses = 0;
  int shortExcess = 0;
  int get sales => byMethod.values.fold(0, (a, b) => a + b);
}

class CounterSummary {
  CounterSummary(this.counter);
  final Counter counter;
  final Map<PaymentMethod, int> byMethod = {for (final m in PaymentMethod.salesMethods) m: 0};
  int handovers = 0;
  int expenses = 0;
  int cashExpenses = 0;
  int shortExcess = 0;
  int shifts = 0;
  final Map<String, CashierSummary> cashiers = {};
  int get sales => byMethod.values.fold(0, (a, b) => a + b);
}

class TrendPoint {
  TrendPoint(this.key, this.label);
  final String key;
  final String label;
  int sales = 0;
  int purchases = 0;
  int expenses = 0;
}

/// Everything recorded in a date range plus the derived figures the
/// dashboard and the Excel export need. Both use this one class so the app
/// and the spreadsheet always agree.
class ReportData {
  ReportData({
    required this.range,
    required this.counters,
    required this.cashierById,
    required this.counterById,
    required this.shifts,
    required this.purchases,
    required this.handovers,
    required this.expenses,
  }) {
    _compute();
  }

  final DateRange range;
  final List<Counter> counters;
  final Map<String, Cashier> cashierById;
  final Map<String, Counter> counterById;
  final List<ShiftSale> shifts;
  final List<Purchase> purchases;
  final List<CashHandover> handovers;
  final List<Expense> expenses;

  final Map<PaymentMethod, int> salesByMethod = {for (final m in PaymentMethod.salesMethods) m: 0};
  final Map<PaymentMethod, int> purchasesByMethod = {};
  final Map<String, int> expensesByCategory = {};
  final Map<String, CounterSummary> byCounter = {};
  final Map<String, int> _handoverKey = {};
  final Map<String, int> _cashExpenseKey = {};
  int generalExpenses = 0;
  int shortExcess = 0;
  int uncountedShifts = 0;
  List<TrendPoint> trend = [];

  int get totalSales => salesByMethod.values.fold(0, (a, b) => a + b);
  int get totalPurchases => purchases.fold(0, (a, b) => a + b.amount);
  int get totalExpenses => expenses.fold(0, (a, b) => a + b.amount);
  int get totalHandovers => handovers.fold(0, (a, b) => a + b.amount);
  int get netCashFlow => totalSales - totalPurchases - totalExpenses;
  bool get isEmpty => shifts.isEmpty && purchases.isEmpty && handovers.isEmpty && expenses.isEmpty;

  String cashierName(String? id) => id == null ? '' : (cashierById[id]?.name ?? 'Unknown');
  String counterName(String? id) => id == null ? 'General' : (counterById[id]?.name ?? 'Unknown');

  static String _key(String date, String counterId, String cashierId) => '$date|$counterId|$cashierId';

  /// Cash the purchaser took from this cashier on that counter that day.
  int handoversFor(ShiftSale s) => _handoverKey[_key(s.date, s.counterId, s.cashierId)] ?? 0;

  /// Cash expenses paid out of this cashier's drawer that day.
  int cashExpensesFor(ShiftSale s) => _cashExpenseKey[_key(s.date, s.counterId, s.cashierId)] ?? 0;

  /// Cash that should be in the drawer at hand-over.
  int expectedCash(ShiftSale s) => s.openingCash + s.cash - handoversFor(s) - cashExpensesFor(s);

  /// Positive = excess, negative = short, null = not counted.
  int? difference(ShiftSale s) => s.closingCash == null ? null : s.closingCash! - expectedCash(s);

  CounterSummary _counter(String id) => byCounter.putIfAbsent(
      id, () => CounterSummary(counterById[id] ?? Counter(id: id, name: 'Unknown', isActive: false)));

  CashierSummary _cashier(CounterSummary c, String id) =>
      c.cashiers.putIfAbsent(id, () => CashierSummary(id, cashierName(id)));

  void _compute() {
    for (final c in counters) {
      _counter(c.id);
    }
    for (final h in handovers) {
      final k = _key(h.date, h.counterId, h.cashierId);
      _handoverKey[k] = (_handoverKey[k] ?? 0) + h.amount;
      final c = _counter(h.counterId)..handovers += h.amount;
      _cashier(c, h.cashierId).handovers += h.amount;
    }
    for (final e in expenses) {
      expensesByCategory[e.category] = (expensesByCategory[e.category] ?? 0) + e.amount;
      if (e.counterId == null) {
        generalExpenses += e.amount;
        continue;
      }
      final c = _counter(e.counterId!)..expenses += e.amount;
      if (e.reducesDrawer) {
        c.cashExpenses += e.amount;
        if (e.cashierId != null) {
          final k = _key(e.date, e.counterId!, e.cashierId!);
          _cashExpenseKey[k] = (_cashExpenseKey[k] ?? 0) + e.amount;
          _cashier(c, e.cashierId!).cashExpenses += e.amount;
        }
      }
    }
    for (final p in purchases) {
      purchasesByMethod[p.method] = (purchasesByMethod[p.method] ?? 0) + p.amount;
    }
    for (final s in shifts) {
      final c = _counter(s.counterId)..shifts += 1;
      final cs = _cashier(c, s.cashierId)..shifts += 1;
      final amounts = {
        PaymentMethod.cash: s.cash,
        PaymentMethod.pos: s.pos,
        PaymentMethod.online: s.online,
        PaymentMethod.jazzcash: s.jazzcash,
      };
      amounts.forEach((m, v) {
        salesByMethod[m] = salesByMethod[m]! + v;
        c.byMethod[m] = c.byMethod[m]! + v;
        cs.byMethod[m] = cs.byMethod[m]! + v;
      });
      final diff = difference(s);
      if (diff == null) {
        uncountedShifts++;
      } else {
        shortExcess += diff;
        c.shortExcess += diff;
        cs.shortExcess += diff;
      }
    }
    _buildTrend();
  }

  void _buildTrend() {
    final monthly = range.days > 62;
    final points = <String, TrendPoint>{};
    if (monthly) {
      var d = DateTime(range.start.year, range.start.month);
      while (!d.isAfter(range.end)) {
        final k = DateFormat('yyyy-MM').format(d);
        points[k] = TrendPoint(k, DateFormat('MMM yy').format(d));
        d = DateTime(d.year, d.month + 1);
      }
    } else {
      for (var i = 0; i < range.days; i++) {
        final d = range.start.add(Duration(days: i));
        final k = toDbDate(d);
        points[k] = TrendPoint(k, DateFormat(range.days <= 7 ? 'EEE' : 'd/M').format(d));
      }
    }
    String keyOf(String date) => monthly ? date.substring(0, 7) : date;
    for (final s in shifts) {
      points[keyOf(s.date)]?.sales += s.totalSale;
    }
    for (final p in purchases) {
      points[keyOf(p.date)]?.purchases += p.amount;
    }
    for (final e in expenses) {
      points[keyOf(e.date)]?.expenses += e.amount;
    }
    trend = points.values.toList();
  }
}

class ReportService {
  ReportService(this.services);
  final AppServices services;

  Future<ReportData> load(DateRange range, {String? counterId}) async {
    final s = range.startDb, e = range.endDb;
    final counterFilter = counterId == null ? null : 'counter_id = ?';
    final counterArgs = counterId == null ? null : [counterId];
    final allCounters = await services.counters.query(includeDeleted: true, orderBy: 'sort_order, name');
    final allCashiers = await services.cashiers.query(includeDeleted: true);
    final results = await Future.wait([
      services.shifts.inRange(s, e, extraWhere: counterFilter, extraArgs: counterArgs),
      counterId == null ? services.purchases.inRange(s, e) : Future.value(<Purchase>[]),
      services.handovers.inRange(s, e, extraWhere: counterFilter, extraArgs: counterArgs),
      services.expenses.inRange(s, e, extraWhere: counterFilter, extraArgs: counterArgs),
    ]);
    final shownCounters = allCounters
        .where((c) => counterId == null ? c.isActive : c.id == counterId)
        .toList();
    return ReportData(
      range: range,
      counters: shownCounters,
      counterById: {for (final c in allCounters) c.id: c},
      cashierById: {for (final c in allCashiers) c.id: c},
      shifts: (results[0] as List<ShiftSale>)..sort(_byDateAsc),
      purchases: (results[1] as List<Purchase>)..sort((a, b) => a.date.compareTo(b.date)),
      handovers: (results[2] as List<CashHandover>)..sort((a, b) => a.date.compareTo(b.date)),
      expenses: (results[3] as List<Expense>)..sort((a, b) => a.date.compareTo(b.date)),
    );
  }

  static int _byDateAsc(ShiftSale a, ShiftSale b) {
    final d = a.date.compareTo(b.date);
    return d != 0 ? d : a.startTime.compareTo(b.startTime);
  }
}
