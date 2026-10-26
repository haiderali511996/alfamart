import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/date_range.dart';
import '../core/enums.dart';
import '../data/models/shift_sale.dart';
import 'report_service.dart';
import 'xlsx_writer.dart';

/// Builds the admin Excel workbook:
///
/// * **Summary** – overview, payment methods, counter, cashier, purchase and
///   expense breakdowns. Every number is a formula pointing at the other
///   sheets.
/// * **Daily** – day by day totals (formulas).
/// * **One sheet per counter** – every shift with its cash reconciliation,
///   plus a cashier-wise summary table.
/// * **Purchases**, **Cash to Purchaser**, **Expenses** – raw entries.
///
/// Because the workbook is linked with formulas (and set to recalculate on
/// open), changing any amount on any sheet updates every total everywhere.
class ExcelExportService {
  static const _first = 4; // zero based index of first data row (Excel row 5)
  static const _lastExcelRow = 5000;

  static String _rng(String col) => '\$$col\$${_first + 1}:\$$col\$$_lastExcelRow';
  static String _str(String s) => '"${s.replaceAll('"', '""')}"';
  static double _rs(int paisa) => paisa / 100;

  Future<File> export(ReportData data, {required String generatedBy}) async {
    final bytes = build(data, generatedBy: generatedBy).encode();
    final dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'exports'));
    await dir.create(recursive: true);
    final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final file = File(p.join(dir.path, 'AlfaMart_CashFlow_${data.range.startDb}_to_${data.range.endDb}_$stamp.xlsx'));
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  XlsxWorkbook build(ReportData data, {required String generatedBy}) {
    final wb = XlsxWorkbook();
    final summary = wb.addSheet('Summary');
    final daily = wb.addSheet('Daily');
    final counterSheets = <String, XlsxSheet>{};
    for (final c in data.byCounter.values) {
      counterSheets[c.counter.id] = wb.addSheet(c.counter.name);
    }
    final purchases = wb.addSheet('Purchases');
    final handovers = wb.addSheet('Cash to Purchaser');
    final expenses = wb.addSheet('Expenses');

    _purchases(purchases, data);
    _handovers(handovers, data);
    _expenses(expenses, data);
    final cashierRows = <String, List<(String, int, CashierSummary)>>{};
    for (final c in data.byCounter.values) {
      cashierRows[c.counter.id] = _counterSheet(counterSheets[c.counter.id]!, c, data, handovers, expenses);
    }
    _daily(daily, data, counterSheets, purchases, expenses, handovers);
    _summary(summary, data, counterSheets, cashierRows, purchases, expenses, handovers, generatedBy);
    return wb;
  }

  void _sheetHeader(XlsxSheet s, String title, List<String> headers, List<double> widths) {
    s.text(0, 0, title, style: XStyle.title);
    s.text(2, 0, 'Add or edit rows below row 4 – all totals and the Summary sheet update automatically.',
        style: XStyle.note);
    for (var i = 0; i < headers.length; i++) {
      s.text(3, i, headers[i], style: XStyle.header);
      s.width(i, widths[i]);
    }
    s.freezeRows = 4;
  }

  void _totalRow(XlsxSheet s, List<int> moneyCols, Map<int, int> cached) {
    s.text(1, 0, 'TOTAL', style: XStyle.totalLabel);
    for (final c in moneyCols) {
      final col = XlsxSheet.colName(c);
      s.formula(1, c, 'SUM(${_rng(col)})', cached: _rs(cached[c] ?? 0), style: XStyle.totalMoney);
    }
  }

  // ---------------------------------------------------------------- raw sheets

  void _purchases(XlsxSheet s, ReportData d) {
    _sheetHeader(s, 'Purchases', ['Date', 'Supplier', 'Invoice #', 'Description', 'Payment Method', 'Amount (Rs)'],
        [12, 24, 14, 34, 18, 16]);
    var r = _first;
    for (final x in d.purchases) {
      s.text(r, 0, x.date);
      s.text(r, 1, x.supplier);
      s.text(r, 2, x.invoiceNo);
      s.text(r, 3, x.description);
      s.text(r, 4, x.method.label);
      s.number(r, 5, _rs(x.amount));
      r++;
    }
    _totalRow(s, [5], {5: d.totalPurchases});
  }

  void _handovers(XlsxSheet s, ReportData d) {
    _sheetHeader(s, 'Cash Given to Purchaser (from cashier drawers)',
        ['Date', 'Time', 'Counter', 'Cashier', 'Purchaser', 'Amount (Rs)', 'Purpose / Details'],
        [12, 9, 14, 20, 20, 16, 36]);
    var r = _first;
    for (final x in d.handovers) {
      s.text(r, 0, x.date);
      s.text(r, 1, x.time);
      s.text(r, 2, d.counterName(x.counterId));
      s.text(r, 3, d.cashierName(x.cashierId));
      s.text(r, 4, x.purchaserName);
      s.number(r, 5, _rs(x.amount));
      s.text(r, 6, x.purpose);
      r++;
    }
    _totalRow(s, [5], {5: d.totalHandovers});
  }

  void _expenses(XlsxSheet s, ReportData d) {
    _sheetHeader(s, 'Expenses',
        ['Date', 'Counter', 'Cashier', 'Category', 'Payment Method', 'Amount (Rs)', 'Details'],
        [12, 14, 20, 28, 18, 16, 36]);
    var r = _first;
    for (final x in d.expenses) {
      s.text(r, 0, x.date);
      s.text(r, 1, d.counterName(x.counterId));
      s.text(r, 2, d.cashierName(x.cashierId));
      s.text(r, 3, x.category);
      s.text(r, 4, x.method.label);
      s.number(r, 5, _rs(x.amount));
      s.text(r, 6, x.description);
      r++;
    }
    _totalRow(s, [5], {5: d.totalExpenses});
  }

  // -------------------------------------------------------------- counter sheet

  /// Returns where each cashier's summary row is, for the Summary sheet.
  List<(String, int, CashierSummary)> _counterSheet(
      XlsxSheet s, CounterSummary c, ReportData d, XlsxSheet handoverSheet, XlsxSheet expenseSheet) {
    final name = c.counter.name;
    _sheetHeader(
      s,
      '$name – Shift Sales & Cash Reconciliation',
      [
        'Date', 'Cashier', 'Start', 'End', 'Opening Cash', 'Cash', 'POS Machine', 'Online Banking', 'JazzCash',
        'Total Sale', 'Cash to Purchaser', 'Cash Expenses', 'Expected Cash', 'Counted Cash', 'Short(-)/Excess(+)',
        'Notes',
      ],
      [12, 20, 8, 8, 14, 14, 14, 15, 13, 15, 15, 14, 15, 14, 16, 28],
    );
    final shifts = d.shifts.where((x) => x.counterId == c.counter.id).toList()
      ..sort((a, b) {
        final n = d.cashierName(a.cashierId).compareTo(d.cashierName(b.cashierId));
        if (n != 0) return n;
        final dt = a.date.compareTo(b.date);
        return dt != 0 ? dt : a.startTime.compareTo(b.startTime);
      });

    final h = handoverSheet.quoted, e = expenseSheet.quoted;
    final totals = <int, int>{};
    void add(int col, int v) => totals[col] = (totals[col] ?? 0) + v;
    final perCashier = <String, Map<int, int>>{};

    var r = _first;
    for (final x in shifts) {
      final row = r + 1;
      final handed = d.handoversFor(x);
      final cashExp = d.cashExpensesFor(x);
      final expected = d.expectedCash(x);
      final diff = d.difference(x);
      final cName = d.cashierName(x.cashierId);
      s.text(r, 0, x.date);
      s.text(r, 1, cName);
      s.text(r, 2, x.startTime);
      s.text(r, 3, x.endTime);
      s.number(r, 4, _rs(x.openingCash));
      s.number(r, 5, _rs(x.cash));
      s.number(r, 6, _rs(x.pos));
      s.number(r, 7, _rs(x.online));
      s.number(r, 8, _rs(x.jazzcash));
      s.formula(r, 9, 'SUM(F$row:I$row)', cached: _rs(x.totalSale), style: XStyle.moneyBold);
      s.formula(
          r,
          10,
          'SUMIFS($h!${_rng('F')},$h!${_rng('A')},\$A$row,$h!${_rng('C')},${_str(name)},'
          '$h!${_rng('D')},\$B$row)',
          cached: _rs(handed));
      s.formula(
          r,
          11,
          'SUMIFS($e!${_rng('F')},$e!${_rng('A')},\$A$row,$e!${_rng('B')},${_str(name)},'
          '$e!${_rng('C')},\$B$row,$e!${_rng('E')},${_str(PaymentMethod.cash.label)})',
          cached: _rs(cashExp));
      s.formula(r, 12, 'E$row+F$row-K$row-L$row', cached: _rs(expected), style: XStyle.moneyBold);
      if (x.closingCash != null) s.number(r, 13, _rs(x.closingCash!));
      if (diff == null) {
        s.formula(r, 14, 'IF(N$row="","",N$row-M$row)', cachedText: '');
      } else {
        s.formula(r, 14, 'IF(N$row="","",N$row-M$row)', cached: _rs(diff), style: XStyle.moneyBold);
      }
      s.text(r, 15, x.notes);

      final values = {
        4: x.openingCash, 5: x.cash, 6: x.pos, 7: x.online, 8: x.jazzcash, 9: x.totalSale, 10: handed,
        11: cashExp, 12: expected, 13: x.closingCash ?? 0, 14: diff ?? 0,
      };
      final pc = perCashier.putIfAbsent(x.cashierId, () => {});
      values.forEach((k, v) {
        add(k, v);
        pc[k] = (pc[k] ?? 0) + v;
      });
      pc[-1] = (pc[-1] ?? 0) + 1;
      r++;
    }
    _totalRow(s, [4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14], totals);

    // Cashier-wise summary to the right of the shift table.
    const base = 17; // column R
    s.text(2, base, 'Cashier-wise Summary – $name', style: XStyle.subtitle);
    final headers = [
      'Cashier', 'Shifts', 'Cash', 'POS Machine', 'Online Banking', 'JazzCash', 'Total Sale', 'Cash to Purchaser',
      'Cash Expenses', 'Short(-)/Excess(+)',
    ];
    final sourceCols = ['', '', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'O'];
    final sourceIdx = [0, -1, 5, 6, 7, 8, 9, 10, 11, 14];
    for (var i = 0; i < headers.length; i++) {
      s.text(3, base + i, headers[i], style: XStyle.header);
      s.width(base + i, i == 0 ? 20 : 15);
    }
    s.width(base - 1, 3);

    final cashierIds = <String>{
      ...c.cashiers.keys,
      ...d.cashierById.values
          .where((x) => x.counterId == c.counter.id && x.isActive && x.meta != null)
          .map((x) => x.id),
    }.toList()
      ..sort((a, b) => d.cashierName(a).compareTo(d.cashierName(b)));

    final result = <(String, int, CashierSummary)>[];
    var cr = _first;
    final tableTotals = <int, int>{};
    for (final id in cashierIds) {
      final row = cr + 1;
      final nameCell = '\$${XlsxSheet.colName(base)}$row';
      final pc = perCashier[id] ?? const {};
      s.text(cr, base, d.cashierName(id), style: XStyle.text);
      s.formula(cr, base + 1, 'COUNTIF(${_rng('B')},$nameCell)', cached: pc[-1] ?? 0, style: XStyle.integer);
      tableTotals[1] = (tableTotals[1] ?? 0) + (pc[-1] ?? 0);
      for (var i = 2; i < headers.length; i++) {
        final src = sourceCols[i];
        final v = pc[sourceIdx[i]] ?? 0;
        tableTotals[i] = (tableTotals[i] ?? 0) + v;
        s.formula(cr, base + i, 'SUMIF(${_rng('B')},$nameCell,${_rng(src)})',
            cached: _rs(v), style: i == 6 ? XStyle.moneyBold : XStyle.money);
      }
      result.add((s.name, cr, c.cashiers[id] ?? CashierSummary(id, d.cashierName(id))));
      cr++;
    }
    final totalRow = cr;
    s.text(totalRow, base, 'TOTAL', style: XStyle.totalLabel);
    for (var i = 1; i < headers.length; i++) {
      final col = XlsxSheet.colName(base + i);
      final f = cashierIds.isEmpty ? '0' : 'SUM($col${_first + 1}:$col$totalRow)';
      s.formula(totalRow, base + i, f,
          cached: i == 1 ? (tableTotals[1] ?? 0) : _rs(tableTotals[i] ?? 0),
          style: i == 1 ? XStyle.integer : XStyle.totalMoney);
    }
    return result;
  }

  // ---------------------------------------------------------------- daily sheet

  void _daily(XlsxSheet s, ReportData d, Map<String, XlsxSheet> counters, XlsxSheet purchases, XlsxSheet expenses,
      XlsxSheet handovers) {
    final counterList = d.byCounter.values.toList();
    final headers = [
      'Date',
      for (final c in counterList) '${c.counter.name} Sales',
      'Total Sales', 'Purchases', 'Expenses', 'Cash to Purchaser', 'Net Cash Flow',
    ];
    _sheetHeader(s, 'Day-wise Summary', headers, [12, for (final _ in headers.skip(1)) 16]);
    s.text(2, 0, 'Every value here is a formula that reads the other sheets.', style: XStyle.note);

    final nC = counterList.length;
    final totalCol = 1 + nC, purCol = totalCol + 1, expCol = purCol + 1, hanCol = expCol + 1, netCol = hanCol + 1;
    final totals = <int, int>{};
    void add(int col, int v) => totals[col] = (totals[col] ?? 0) + v;

    var r = _first;
    for (var i = 0; i < d.range.days; i++) {
      final date = toDbDate(d.range.start.add(Duration(days: i)));
      final row = r + 1;
      s.text(r, 0, date);
      var dayTotal = 0;
      for (var k = 0; k < nC; k++) {
        final cs = counters[counterList[k].counter.id]!.quoted;
        final v = d.shifts
            .where((x) => x.date == date && x.counterId == counterList[k].counter.id)
            .fold<int>(0, (a, b) => a + b.totalSale);
        dayTotal += v;
        add(1 + k, v);
        s.formula(r, 1 + k, 'SUMIF($cs!${_rng('A')},\$A$row,$cs!${_rng('J')})', cached: _rs(v));
      }
      final pur = d.purchases.where((x) => x.date == date).fold<int>(0, (a, b) => a + b.amount);
      final exp = d.expenses.where((x) => x.date == date).fold<int>(0, (a, b) => a + b.amount);
      final han = d.handovers.where((x) => x.date == date).fold<int>(0, (a, b) => a + b.amount);
      add(totalCol, dayTotal);
      add(purCol, pur);
      add(expCol, exp);
      add(hanCol, han);
      add(netCol, dayTotal - pur - exp);
      final first = XlsxSheet.colName(1), last = XlsxSheet.colName(nC);
      s.formula(r, totalCol, nC == 0 ? '0' : 'SUM($first$row:$last$row)', cached: _rs(dayTotal),
          style: XStyle.moneyBold);
      s.formula(r, purCol, 'SUMIF(${purchases.quoted}!${_rng('A')},\$A$row,${purchases.quoted}!${_rng('F')})',
          cached: _rs(pur));
      s.formula(r, expCol, 'SUMIF(${expenses.quoted}!${_rng('A')},\$A$row,${expenses.quoted}!${_rng('F')})',
          cached: _rs(exp));
      s.formula(r, hanCol, 'SUMIF(${handovers.quoted}!${_rng('A')},\$A$row,${handovers.quoted}!${_rng('F')})',
          cached: _rs(han));
      final t = XlsxSheet.colName(totalCol), pc = XlsxSheet.colName(purCol), ec = XlsxSheet.colName(expCol);
      s.formula(r, netCol, '$t$row-$pc$row-$ec$row', cached: _rs(dayTotal - pur - exp), style: XStyle.moneyBold);
      r++;
    }
    _totalRow(s, [for (var c = 1; c <= netCol; c++) c], totals);
  }

  // -------------------------------------------------------------- summary sheet

  void _summary(
    XlsxSheet s,
    ReportData d,
    Map<String, XlsxSheet> counters,
    Map<String, List<(String, int, CashierSummary)>> cashierRows,
    XlsxSheet purchases,
    XlsxSheet expenses,
    XlsxSheet handovers,
    String generatedBy,
  ) {
    for (final (c, w) in [(0, 32.0), (1, 18.0), (2, 18.0), (3, 18.0), (4, 18.0), (5, 18.0), (6, 18.0)]) {
      s.width(c, w);
    }
    s.text(0, 0, 'ALFA MART – Cash Flow Report', style: XStyle.title);
    s.text(1, 0, 'Period: ${d.range.label}', style: XStyle.subtitle);
    s.text(2, 0,
        'Generated ${DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now())} by $generatedBy. '
        'All figures are live formulas – edit any sheet and this page updates.',
        style: XStyle.note);

    final counterList = d.byCounter.values.toList();
    String cRef(CounterSummary c, String cell) => '${counters[c.counter.id]!.quoted}!\$$cell\$2';
    String sumCounters(String col) =>
        counterList.isEmpty ? '0' : counterList.map((c) => cRef(c, col)).join('+');

    var r = 4;
    // Overview
    s.text(r++, 0, 'Overview', style: XStyle.subtitle);
    s.text(r, 0, 'Item', style: XStyle.header);
    s.text(r++, 1, 'Amount (Rs)', style: XStyle.header);
    final salesRow = r + 1;
    s.text(r, 0, 'Total Sales');
    s.formula(r++, 1, sumCounters('J'), cached: _rs(d.totalSales), style: XStyle.moneyBold);
    s.text(r, 0, 'Total Purchases');
    s.formula(r++, 1, '${purchases.quoted}!\$F\$2', cached: _rs(d.totalPurchases));
    s.text(r, 0, 'Total Expenses');
    s.formula(r++, 1, '${expenses.quoted}!\$F\$2', cached: _rs(d.totalExpenses));
    s.text(r, 0, 'Net Cash Flow (Sales − Purchases − Expenses)', style: XStyle.totalLabel);
    s.formula(r++, 1, 'B$salesRow-B${salesRow + 1}-B${salesRow + 2}',
        cached: _rs(d.netCashFlow), style: XStyle.totalMoney);
    s.text(r, 0, 'Cash Given to Purchasers');
    s.formula(r++, 1, '${handovers.quoted}!\$F\$2', cached: _rs(d.totalHandovers));
    s.text(r, 0, 'Cash Short (−) / Excess (+)');
    s.formula(r++, 1, sumCounters('O'), cached: _rs(d.shortExcess), style: XStyle.moneyBold);

    // Sales by payment method
    r++;
    s.text(r++, 0, 'Sales by Payment Method', style: XStyle.subtitle);
    s.text(r, 0, 'Payment Method', style: XStyle.header);
    for (var i = 0; i < counterList.length; i++) {
      s.text(r, 1 + i, counterList[i].counter.name, style: XStyle.header);
    }
    final totCol = 1 + counterList.length;
    s.text(r, totCol, 'Total', style: XStyle.header);
    s.text(r, totCol + 1, 'Share', style: XStyle.header);
    s.width(totCol + 1, 12);
    r++;
    final methodCols = {
      PaymentMethod.cash: 'F',
      PaymentMethod.pos: 'G',
      PaymentMethod.online: 'H',
      PaymentMethod.jazzcash: 'I',
    };
    final firstMethodRow = r + 1;
    final grandRow = firstMethodRow + methodCols.length;
    final tc = XlsxSheet.colName(totCol);
    for (final m in PaymentMethod.salesMethods) {
      final row = r + 1;
      s.text(r, 0, m.label);
      for (var i = 0; i < counterList.length; i++) {
        s.formula(r, 1 + i, cRef(counterList[i], methodCols[m]!), cached: _rs(counterList[i].byMethod[m]!));
      }
      s.formula(r, totCol,
          counterList.isEmpty ? '0' : 'SUM(B$row:${XlsxSheet.colName(counterList.length)}$row)',
          cached: _rs(d.salesByMethod[m]!), style: XStyle.moneyBold);
      s.formula(r, totCol + 1, 'IF(\$$tc\$$grandRow=0,0,$tc$row/\$$tc\$$grandRow)',
          cached: d.totalSales == 0 ? 0 : d.salesByMethod[m]! / d.totalSales, style: XStyle.percent);
      r++;
    }
    s.text(r, 0, 'TOTAL', style: XStyle.totalLabel);
    for (var i = 0; i <= counterList.length; i++) {
      final col = XlsxSheet.colName(1 + i);
      final cached = i < counterList.length ? counterList[i].sales : d.totalSales;
      s.formula(r, 1 + i, 'SUM($col$firstMethodRow:$col${grandRow - 1})', cached: _rs(cached),
          style: XStyle.totalMoney);
    }
    r += 2;

    // Counter summary
    s.text(r++, 0, 'Counter Summary', style: XStyle.subtitle);
    for (final (i, hText) in [
      'Counter', 'Shifts', 'Total Sale', 'Cash to Purchaser', 'Counter Expenses', 'Short(-)/Excess(+)'
    ].indexed) {
      s.text(r, i, hText, style: XStyle.header);
    }
    r++;
    final h = handovers.quoted, e = expenses.quoted;
    for (final c in counterList) {
      final cs = counters[c.counter.id]!.quoted;
      s.text(r, 0, c.counter.name);
      s.formula(r, 1, 'COUNTA($cs!${_rng('A')})', cached: c.shifts, style: XStyle.integer);
      s.formula(r, 2, cRef(c, 'J'), cached: _rs(c.sales), style: XStyle.moneyBold);
      s.formula(r, 3, 'SUMIF($h!${_rng('C')},${_str(c.counter.name)},$h!${_rng('F')})',
          cached: _rs(c.handovers));
      s.formula(r, 4, 'SUMIF($e!${_rng('B')},${_str(c.counter.name)},$e!${_rng('F')})',
          cached: _rs(c.expenses));
      s.formula(r, 5, cRef(c, 'O'), cached: _rs(c.shortExcess), style: XStyle.moneyBold);
      r++;
    }
    s.text(r, 0, 'General shop expenses (not from a counter)');
    s.formula(r, 4, 'SUMIF($e!${_rng('B')},"General",$e!${_rng('F')})', cached: _rs(d.generalExpenses));
    r += 2;

    // Cashier summary, read from each counter sheet's cashier table.
    s.text(r++, 0, 'Cashier Summary', style: XStyle.subtitle);
    for (final (i, hText) in [
      'Cashier', 'Counter', 'Shifts', 'Total Sale', 'Cash to Purchaser', 'Cash Expenses', 'Short(-)/Excess(+)'
    ].indexed) {
      s.text(r, i, hText, style: XStyle.header);
    }
    r++;
    for (final c in counterList) {
      final sheet = counters[c.counter.id]!;
      for (final (_, row, cs) in cashierRows[c.counter.id]!) {
        final ex = row + 1;
        String at(int offset) => '${sheet.quoted}!\$${XlsxSheet.colName(17 + offset)}\$$ex';
        s.formula(r, 0, at(0), cachedText: cs.name, style: XStyle.text);
        s.text(r, 1, c.counter.name);
        s.formula(r, 2, at(1), cached: cs.shifts, style: XStyle.integer);
        s.formula(r, 3, at(6), cached: _rs(_sumRow(d, c, cs.cashierId, (x) => x.totalSale)),
            style: XStyle.moneyBold);
        s.formula(r, 4, at(7), cached: _rs(_sumRow(d, c, cs.cashierId, d.handoversFor)));
        s.formula(r, 5, at(8), cached: _rs(_sumRow(d, c, cs.cashierId, d.cashExpensesFor)));
        s.formula(r, 6, at(9), cached: _rs(_sumRow(d, c, cs.cashierId, (x) => d.difference(x) ?? 0)),
            style: XStyle.moneyBold);
        r++;
      }
    }
    r++;

    // Purchases by method
    s.text(r++, 0, 'Purchases by Payment Method', style: XStyle.subtitle);
    s.text(r, 0, 'Payment Method', style: XStyle.header);
    s.text(r++, 1, 'Amount (Rs)', style: XStyle.header);
    final pq = purchases.quoted;
    for (final m in PaymentMethod.values) {
      s.text(r, 0, m.label);
      s.formula(r++, 1, 'SUMIF($pq!${_rng('E')},${_str(m.label)},$pq!${_rng('F')})',
          cached: _rs(d.purchasesByMethod[m] ?? 0));
    }
    r++;

    // Expenses by category
    s.text(r++, 0, 'Expenses by Category', style: XStyle.subtitle);
    s.text(r, 0, 'Category', style: XStyle.header);
    s.text(r++, 1, 'Amount (Rs)', style: XStyle.header);
    final cats = {...expenseCategories, ...d.expensesByCategory.keys};
    for (final cat in cats) {
      s.text(r, 0, cat);
      s.formula(r++, 1, 'SUMIF($e!${_rng('D')},${_str(cat)},$e!${_rng('F')})',
          cached: _rs(d.expensesByCategory[cat] ?? 0));
    }
  }

  int _sumRow(ReportData d, CounterSummary c, String cashierId, int Function(ShiftSale) f) => d.shifts
      .where((x) => x.counterId == c.counter.id && x.cashierId == cashierId)
      .fold<int>(0, (a, b) => a + f(b));
}
