import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/date_range.dart';
import '../../core/enums.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/models/counter.dart';
import '../../services/app_services.dart';
import '../../services/auth_service.dart';
import '../../services/report_service.dart';
import '../widgets/common.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Period _period = Period.day;
  DateRange _range = DateRange.forPeriod(Period.day);
  String? _counterId;

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().currentUser!;
    final services = context.read<AppServices>();
    final reports = context.read<ReportService>();
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        title: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset('assets/images/app_icon.png', width: 38, height: 38),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Alfa Mart', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              Text('${user.fullName} · ${user.role.label}',
                  style: const TextStyle(fontSize: 12, color: Colors.white70)),
            ]),
          ),
        ]),
      ),
      body: Reloader<(ReportData, List<Counter>)>(
        reloadKey: (_range, _counterId),
        load: () async => (await reports.load(_range, counterId: _counterId), await services.activeCounters()),
        builder: (context, data) {
          final (r, counters) = data;
          return RefreshIndicator(
            onRefresh: () async => services.notifier.changed(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                PeriodSelector(
                  period: _period,
                  range: _range,
                  onChanged: (p, range) => setState(() {
                    _period = p;
                    _range = range;
                  }),
                ),
                const SizedBox(height: 8),
                _counterChips(counters),
                const SizedBox(height: 12),
                _tiles(r),
                const SizedBox(height: 16),
                _methods(r),
                const SizedBox(height: 16),
                _trend(r),
                const SizedBox(height: 16),
                for (final c in r.byCounter.values) ...[_counterCard(r, c), const SizedBox(height: 16)],
                if (r.expensesByCategory.isNotEmpty) _categories(r),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _counterChips(List<Counter> counters) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final c in [null, ...counters])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(c?.name ?? 'All Counters'),
                selected: _counterId == c?.id,
                showCheckmark: false,
                selectedColor: AppColors.navy,
                labelStyle: TextStyle(color: _counterId == c?.id ? Colors.white : AppColors.navy),
                onSelected: (_) => setState(() => _counterId = c?.id),
              ),
            ),
        ]),
      );

  Widget _tiles(ReportData r) {
    final se = r.shortExcess;
    final tiles = [
      StatTile(
        label: 'Sales',
        value: Money.format(r.totalSales),
        icon: Icons.point_of_sale,
        color: AppColors.sales,
        subtitle: '${r.shifts.length} shift entries',
      ),
      StatTile(
        label: 'Purchase',
        value: Money.format(r.totalPurchases),
        icon: Icons.shopping_cart,
        color: AppColors.purchase,
        subtitle: _counterId == null ? '${r.purchases.length} purchases' : 'Shop level only',
      ),
      StatTile(
        label: 'Expense',
        value: Money.format(r.totalExpenses),
        icon: Icons.receipt,
        color: AppColors.expense,
        subtitle: '${r.expenses.length} expense entries',
      ),
      StatTile(
        label: 'Net Cash Flow',
        value: Money.format(r.netCashFlow),
        icon: r.netCashFlow >= 0 ? Icons.trending_up : Icons.trending_down,
        color: r.netCashFlow >= 0 ? AppColors.net : AppColors.danger,
        subtitle: 'Sales − Purchase − Expense',
      ),
      StatTile(
        label: 'Cash to Purchaser',
        value: Money.format(r.totalHandovers),
        icon: Icons.handshake,
        color: AppColors.handover,
        subtitle: '${r.handovers.length} hand-overs',
      ),
      StatTile(
        label: se < 0 ? 'Cash Short' : 'Cash Excess',
        value: Money.format(se.abs()),
        icon: se == 0 ? Icons.verified : Icons.warning_amber,
        color: se == 0 ? AppColors.success : (se < 0 ? AppColors.danger : AppColors.warning),
        subtitle: r.uncountedShifts > 0 ? '${r.uncountedShifts} shift(s) not counted' : 'All drawers counted',
      ),
    ];
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth > 700 ? 3 : 2;
      final w = (c.maxWidth - (cols - 1) * 12) / cols;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [for (final t in tiles) SizedBox(width: w, height: 118, child: t)],
      );
    });
  }

  Widget _methods(ReportData r) {
    final total = r.totalSales;
    return SectionCard(
      title: 'Sales by Payment Method',
      child: Column(children: [
        for (final m in PaymentMethod.salesMethods)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(children: [
              Row(children: [
                Icon(m.icon, size: 18, color: AppColors.navy),
                const SizedBox(width: 8),
                Expanded(child: Text(m.label, style: const TextStyle(fontWeight: FontWeight.w600))),
                Text(Money.format(r.salesByMethod[m]!), style: const TextStyle(fontWeight: FontWeight.w700)),
                SizedBox(
                  width: 48,
                  child: Text(
                    total == 0 ? '0%' : '${(r.salesByMethod[m]! * 100 / total).toStringAsFixed(0)}%',
                    textAlign: TextAlign.right,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                ),
              ]),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: total == 0 ? 0 : r.salesByMethod[m]! / total,
                  minHeight: 6,
                  backgroundColor: Colors.grey.shade200,
                  color: AppColors.orange,
                ),
              ),
            ]),
          ),
      ]),
    );
  }

  Widget _trend(ReportData r) {
    final points = r.trend;
    final maxY = points.fold<int>(0, (a, p) => math.max(a, math.max(p.sales, math.max(p.purchases, p.expenses))));
    final step = math.max(1, (points.length / 8).ceil());
    return SectionCard(
      title: 'Trend',
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        _legend('Sales', AppColors.sales),
        _legend('Purchase', AppColors.purchase),
        _legend('Expense', AppColors.expense),
      ]),
      child: SizedBox(
        height: 200,
        child: maxY == 0
            ? Center(child: Text('No data in this period', style: TextStyle(color: Colors.grey.shade600)))
            : BarChart(
                BarChartData(
                  maxY: maxY * 1.15 / 100,
                  gridData: FlGridData(
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) => FlLine(color: Colors.grey.shade200, strokeWidth: 1),
                  ),
                  borderData: FlBorderData(show: false),
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (_) => AppColors.navy,
                      getTooltipItem: (group, gi, rod, ri) => BarTooltipItem(
                        '${points[group.x].label}\n${Money.format((rod.toY * 100).round())}',
                        const TextStyle(color: Colors.white, fontSize: 11),
                      ),
                    ),
                  ),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(),
                    rightTitles: const AxisTitles(),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 44,
                        getTitlesWidget: (v, meta) => Text(Money.compact((v * 100).round()).replaceFirst('Rs ', ''),
                            style: const TextStyle(fontSize: 10)),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 22,
                        getTitlesWidget: (v, meta) {
                          final i = v.toInt();
                          if (i < 0 || i >= points.length || i % step != 0) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(points[i].label, style: const TextStyle(fontSize: 10)),
                          );
                        },
                      ),
                    ),
                  ),
                  barGroups: [
                    for (var i = 0; i < points.length; i++)
                      BarChartGroupData(
                        x: i,
                        barsSpace: 1,
                        barRods: [
                          _rod(points[i].sales, AppColors.sales, points.length),
                          _rod(points[i].purchases, AppColors.purchase, points.length),
                          _rod(points[i].expenses, AppColors.expense, points.length),
                        ],
                      ),
                  ],
                ),
              ),
      ),
    );
  }

  BarChartRodData _rod(int paisa, Color c, int n) => BarChartRodData(
        toY: paisa / 100,
        color: c,
        width: n > 20 ? 2 : (n > 8 ? 4 : 8),
        borderRadius: BorderRadius.circular(2),
      );

  Widget _legend(String l, Color c) => Padding(
        padding: const EdgeInsets.only(left: 8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 4),
          Text(l, style: const TextStyle(fontSize: 11)),
        ]),
      );

  Widget _counterCard(ReportData r, CounterSummary c) {
    final cashiers = c.cashiers.values.where((x) => x.shifts > 0 || x.handovers > 0 || x.cashExpenses > 0).toList()
      ..sort((a, b) => b.sales.compareTo(a.sales));
    return SectionCard(
      title: c.counter.name,
      trailing: Text(Money.format(c.sales),
          style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.orange, fontSize: 16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final m in PaymentMethod.salesMethods) _chip(m.label, c.byMethod[m]!),
        ]),
        const Divider(height: 24),
        MoneyRow('Cash given to purchaser', c.handovers, color: AppColors.handover),
        MoneyRow('Counter expenses', c.expenses, color: AppColors.expense),
        MoneyRow(c.shortExcess < 0 ? 'Cash short' : 'Cash excess', c.shortExcess.abs(),
            bold: true,
            color: c.shortExcess == 0 ? AppColors.success : (c.shortExcess < 0 ? AppColors.danger : AppColors.warning)),
        if (cashiers.isNotEmpty) ...[
          const Divider(height: 24),
          const Text('Cashiers', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          for (final cs in cashiers)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                radius: 16,
                backgroundColor: AppColors.navy.withValues(alpha: 0.1),
                child: Text(cs.name.isEmpty ? '?' : cs.name[0].toUpperCase(),
                    style: const TextStyle(color: AppColors.navy, fontWeight: FontWeight.w700)),
              ),
              title: Text(cs.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('${cs.shifts} shift(s) · to purchaser ${Money.format(cs.handovers)}'
                  '${cs.shortExcess != 0 ? ' · ${cs.shortExcess < 0 ? 'short' : 'excess'} ${Money.format(cs.shortExcess.abs())}' : ''}'),
              trailing: Text(Money.format(cs.sales), style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
        ],
      ]),
    );
  }

  Widget _chip(String label, int v) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(8)),
        child: Text('$label: ${Money.format(v)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      );

  Widget _categories(ReportData r) {
    final entries = r.expensesByCategory.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return SectionCard(
      title: 'Expenses by Category',
      child: Column(children: [for (final e in entries) MoneyRow(e.key, e.value)]),
    );
  }
}
