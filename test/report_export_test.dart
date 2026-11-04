import 'dart:io';

import 'package:alfamart_cashflow/core/date_range.dart';
import 'package:alfamart_cashflow/core/enums.dart';
import 'package:alfamart_cashflow/data/models/cash_handover.dart';
import 'package:alfamart_cashflow/data/models/cashier.dart';
import 'package:alfamart_cashflow/data/models/counter.dart';
import 'package:alfamart_cashflow/data/models/entity.dart';
import 'package:alfamart_cashflow/data/models/expense.dart';
import 'package:alfamart_cashflow/data/models/purchase.dart';
import 'package:alfamart_cashflow/data/models/purchaser_advance.dart';
import 'package:alfamart_cashflow/data/models/shift_sale.dart';
import 'package:alfamart_cashflow/services/excel_export_service.dart';
import 'package:alfamart_cashflow/services/report_service.dart';
import 'package:flutter_test/flutter_test.dart';

ReportData sample() {
  final meta = RecordMeta(createdAt: DateTime(2026), updatedAt: DateTime(2026));
  final c1 = Counter(id: 'c1', name: 'Counter 1', sortOrder: 1, meta: meta);
  final c2 = Counter(id: 'c2', name: 'Counter 2', sortOrder: 2, meta: meta);
  final cashiers = [
    Cashier(id: 'a', name: 'Ali', counterId: 'c1', meta: meta),
    Cashier(id: 'b', name: 'Bilal', counterId: 'c1', meta: meta),
    Cashier(id: 'z', name: 'Zara', counterId: 'c2', meta: meta),
  ];
  return ReportData(
    range: DateRange(DateTime(2026, 10, 25), DateTime(2026, 10, 26)),
    counters: [c1, c2],
    counterById: {'c1': c1, 'c2': c2},
    cashierById: {for (final c in cashiers) c.id: c},
    shifts: [
      ShiftSale(
        id: 's1',
        date: '2026-10-25',
        counterId: 'c1',
        cashierId: 'a',
        openingCash: 500000,
        cash: 2000000,
        pos: 500000,
        online: 300000,
        jazzcash: 100000,
        closingCash: 2400000,
      ),
      ShiftSale(id: 's2', date: '2026-10-25', counterId: 'c1', cashierId: 'b', cash: 1000000, pos: 200000),
      ShiftSale(
        id: 's3',
        date: '2026-10-26',
        counterId: 'c2',
        cashierId: 'z',
        openingCash: 100000,
        cash: 1500000,
        jazzcash: 250000,
        closingCash: 1600000,
      ),
    ],
    purchases: [
      Purchase(id: 'p1', date: '2026-10-25', amount: 1000000, supplier: 'Nestle', purchaserName: 'Kamran'),
      Purchase(id: 'p2', date: '2026-10-26', amount: 500000, supplier: 'Unilever', method: PaymentMethod.online),
    ],
    handovers: [
      CashHandover(
        id: 'h1',
        date: '2026-10-25',
        counterId: 'c1',
        cashierId: 'a',
        purchaserName: 'Kamran',
        amount: 100000,
      ),
    ],
    expenses: [
      Expense(id: 'e1', date: '2026-10-25', amount: 50000, category: 'Tea / Food', counterId: 'c1', cashierId: 'a'),
      Expense(id: 'e2', date: '2026-10-26', amount: 2000000, category: 'Rent', method: PaymentMethod.online),
    ],
    advances: [PurchaserAdvance(id: 'v1', date: '2026-10-25', purchaserName: 'Kamran', amount: 1500000)],
  );
}

void main() {
  test('report totals and reconciliation', () {
    final d = sample();
    expect(d.totalSales, 2900000 + 1200000 + 1750000);
    expect(d.salesByMethod[PaymentMethod.cash], 4500000);
    expect(d.totalPurchases, 1500000);
    expect(d.totalExpenses, 2050000);
    expect(d.netCashFlow, 5850000 - 1500000 - 2050000);
    // Ali: 5000 + 20000 - 1000 (purchaser) - 500 (tea) = 23500 expected, counted 24000 => +500
    expect(d.expectedCash(d.shifts[0]), 2350000);
    expect(d.difference(d.shifts[0]), 50000);
    // Zara: 1000 + 15000 = 16000 expected, counted 16000 => 0
    expect(d.difference(d.shifts[2]), 0);
    expect(d.shortExcess, 50000);
    expect(d.uncountedShifts, 1);
    expect(d.byCounter['c1']!.cashiers['a']!.handovers, 100000);
    expect(d.generalExpenses, 2000000);
  });

  test('excel workbook builds', () {
    final wb = ExcelExportService().build(sample(), generatedBy: 'Test');
    expect(wb.sheets.map((s) => s.name), [
      'Summary',
      'Daily',
      'Counter 1',
      'Counter 2',
      'Purchases',
      'Cash to Purchaser',
      'Expenses',
      'Purchaser Advances',
      'Purchaser Account',
    ]);
    final bytes = wb.encode();
    final out = Platform.environment['XLSX_OUT'];
    if (out != null) File(out).writeAsBytesSync(bytes);
    expect(bytes.length, greaterThan(1000));
  });

  group('purchaser account', () {
    ReportData day({required int purchases, int fromCounter = 0}) {
      final meta = RecordMeta(createdAt: DateTime(2026), updatedAt: DateTime(2026));
      final c1 = Counter(id: 'c1', name: 'Counter 1', meta: meta);
      final ali = Cashier(id: 'a', name: 'Ali', counterId: 'c1', meta: meta);
      return ReportData(
        range: DateRange(DateTime(2026, 11, 4), DateTime(2026, 11, 4)),
        counters: [c1],
        counterById: {'c1': c1},
        cashierById: {'a': ali},
        shifts: [],
        purchases: [
          Purchase(id: 'p', date: '2026-11-04', amount: purchases, supplier: 'Market', purchaserName: 'Kamran'),
          // Paid online by the shop: not from the purchaser's cash.
          Purchase(id: 'q', date: '2026-11-04', amount: 99900, method: PaymentMethod.online, purchaserName: 'kamran'),
        ],
        handovers: [
          if (fromCounter > 0)
            CashHandover(
              id: 'h',
              date: '2026-11-04',
              counterId: 'c1',
              cashierId: 'a',
              purchaserName: 'Kamran',
              amount: fromCounter,
            ),
        ],
        expenses: [],
        advances: [PurchaserAdvance(id: 'v', date: '2026-11-04', purchaserName: 'Kamran', amount: 20000000)],
      );
    }

    test('spent 2.5 lac on a 2 lac advance: 50K taken from Counter 1 settles it', () {
      final d = day(purchases: 25000000, fromCounter: 5000000);
      expect(d.purchaserDays, hasLength(1));
      final k = d.purchaserDays.single;
      expect(k.name, 'Kamran');
      expect(k.advance, 20000000);
      expect(k.fromCounters, 5000000);
      expect(k.byCounter['c1'], 5000000);
      expect(k.cashPurchases, 25000000);
      expect(k.otherPurchases, 99900);
      expect(k.balance, 0);
      expect(d.byCounter['c1']!.handovers, 5000000); // counted on Counter 1 that day
    });

    test('spent 2.5 lac without recording the counter cash: 50K not covered', () {
      expect(day(purchases: 25000000).purchaserDays.single.balance, -5000000);
    });

    test('spent 1.5 lac on a 2 lac advance: 50K to return', () {
      final d = day(purchases: 15000000);
      expect(d.purchaserDays.single.balance, 5000000);
      expect(d.purchaserBalance, 5000000);
    });
  });
}
