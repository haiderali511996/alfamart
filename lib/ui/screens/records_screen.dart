import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/date_range.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../services/report_service.dart';
import '../forms/expense_form.dart';
import '../forms/handover_form.dart';
import '../forms/purchase_form.dart';
import '../forms/shift_sale_form.dart';
import '../widgets/common.dart';

/// All entries for a period, one tab per entry type. Tap to edit.
class RecordsScreen extends StatefulWidget {
  const RecordsScreen({super.key});

  @override
  State<RecordsScreen> createState() => _RecordsScreenState();
}

class _RecordsScreenState extends State<RecordsScreen> {
  Period _period = Period.week;
  DateRange _range = DateRange.forPeriod(Period.week);

  void _open(Widget page) => Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final reports = context.read<ReportService>();
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Records'),
          bottom: const TabBar(
            isScrollable: true,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: AppColors.orange,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Shift Sales'),
              Tab(text: 'Purchases'),
              Tab(text: 'Cash to Purchaser'),
              Tab(text: 'Expenses'),
            ],
          ),
        ),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: PeriodSelector(
              period: _period,
              range: _range,
              onChanged: (p, r) => setState(() {
                _period = p;
                _range = r;
              }),
            ),
          ),
          Expanded(
            child: Reloader<ReportData>(
              reloadKey: _range,
              load: () => reports.load(_range),
              builder: (context, d) => TabBarView(children: [
                _list(
                  d.shifts.reversed.toList(),
                  (s) {
                    final diff = d.difference(s);
                    return _tile(
                      icon: Icons.point_of_sale,
                      color: AppColors.sales,
                      title: '${d.cashierName(s.cashierId)} · ${d.counterName(s.counterId)}',
                      subtitle: '${displayDate(s.date)}'
                          '${s.startTime.isNotEmpty ? ' · ${s.startTime}–${s.endTime}' : ''}\n'
                          'Cash ${Money.format(s.cash)} · POS ${Money.format(s.pos)} · '
                          'Online ${Money.format(s.online)} · JazzCash ${Money.format(s.jazzcash)}',
                      amount: s.totalSale,
                      badge: diff == null
                          ? null
                          : (diff == 0
                              ? ('Balanced', AppColors.success)
                              : (diff < 0
                                  ? ('Short ${Money.format(-diff)}', AppColors.danger)
                                  : ('Excess ${Money.format(diff)}', AppColors.warning))),
                      onTap: () => _open(ShiftSaleForm(existing: s)),
                    );
                  },
                  'No shift sales in this period',
                ),
                _list(
                  d.purchases.reversed.toList(),
                  (p) => _tile(
                    icon: Icons.shopping_cart,
                    color: AppColors.purchase,
                    title: p.supplier.isEmpty ? 'Purchase' : p.supplier,
                    subtitle: '${displayDate(p.date)} · ${p.method.label}'
                        '${p.invoiceNo.isNotEmpty ? ' · #${p.invoiceNo}' : ''}'
                        '${p.description.isNotEmpty ? '\n${p.description}' : ''}',
                    amount: p.amount,
                    onTap: () => _open(PurchaseForm(existing: p)),
                  ),
                  'No purchases in this period',
                ),
                _list(
                  d.handovers.reversed.toList(),
                  (h) => _tile(
                    icon: Icons.handshake,
                    color: AppColors.handover,
                    title: '${h.purchaserName} ← ${d.cashierName(h.cashierId)}',
                    subtitle: '${displayDate(h.date)} ${h.time} · ${d.counterName(h.counterId)}'
                        '${h.purpose.isNotEmpty ? '\n${h.purpose}' : ''}',
                    amount: h.amount,
                    onTap: () => _open(HandoverForm(existing: h)),
                  ),
                  'No cash given to purchasers in this period',
                ),
                _list(
                  d.expenses.reversed.toList(),
                  (e) => _tile(
                    icon: Icons.receipt,
                    color: AppColors.expense,
                    title: e.category,
                    subtitle: '${displayDate(e.date)} · ${d.counterName(e.counterId)}'
                        '${e.cashierId != null ? ' · ${d.cashierName(e.cashierId)}' : ''} · ${e.method.label}'
                        '${e.description.isNotEmpty ? '\n${e.description}' : ''}',
                    amount: e.amount,
                    onTap: () => _open(ExpenseForm(existing: e)),
                  ),
                  'No expenses in this period',
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _list<T>(List<T> items, Widget Function(T) tile, String empty) {
    if (items.isEmpty) return EmptyState(icon: Icons.inbox_outlined, message: empty);
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) => tile(items[i]),
    );
  }

  Widget _tile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required int amount,
    required VoidCallback onTap,
    (String, Color)? badge,
  }) =>
      Card(
        child: ListTile(
          onTap: onTap,
          isThreeLine: subtitle.contains('\n'),
          leading: CircleAvatar(backgroundColor: color.withValues(alpha: 0.12), child: Icon(icon, color: color)),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(subtitle, maxLines: 3, overflow: TextOverflow.ellipsis),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(Money.format(amount), style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.navy)),
              if (badge != null)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                      color: badge.$2.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                  child: Text(badge.$1, style: TextStyle(fontSize: 10, color: badge.$2, fontWeight: FontWeight.w700)),
                ),
            ],
          ),
        ),
      );
}
