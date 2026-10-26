import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/date_range.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../services/auth_service.dart';
import '../../services/excel_export_service.dart';
import '../../services/report_service.dart';
import '../widgets/common.dart';

class ExportScreen extends StatefulWidget {
  const ExportScreen({super.key});

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  Period _period = Period.month;
  DateRange _range = DateRange.forPeriod(Period.month);
  bool _busy = false;

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final data = await context.read<ReportService>().load(_range);
      if (!mounted) return;
      final user = context.read<AuthService>().currentUser!;
      final file = await context.read<ExcelExportService>().export(data, generatedBy: user.fullName);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')],
        subject: 'Alfa Mart Cash Flow ${_range.label}',
        text: 'Alfa Mart cash flow report: ${_range.label}',
      ));
    } catch (e) {
      if (mounted) showSnack(context, 'Export failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reports = context.read<ReportService>();
    return Scaffold(
      appBar: AppBar(title: const Text('Export to Excel')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          PeriodSelector(
            period: _period,
            range: _range,
            onChanged: (p, r) => setState(() {
              _period = p;
              _range = r;
            }),
          ),
          const SizedBox(height: 16),
          Reloader<ReportData>(
            reloadKey: _range,
            load: () => reports.load(_range),
            builder: (context, d) => SectionCard(
              title: 'This export will contain',
              child: Column(children: [
                MoneyRow('Sales (${d.shifts.length} shifts)', d.totalSales),
                MoneyRow('Purchases (${d.purchases.length})', d.totalPurchases),
                MoneyRow('Expenses (${d.expenses.length})', d.totalExpenses),
                MoneyRow('Cash to purchaser (${d.handovers.length})', d.totalHandovers),
                const Divider(),
                MoneyRow('Net cash flow', d.netCashFlow, bold: true),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Workbook sheets',
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _sheet('Summary', 'Main page – totals, payment methods, counters, cashiers, purchases, expenses'),
              _sheet('Daily', 'Day-by-day sales, purchases, expenses and net cash flow'),
              _sheet('Counter 1, Counter 2 …', 'Every shift per cashier with cash reconciliation + cashier summary'),
              _sheet('Purchases', 'All purchase entries'),
              _sheet('Cash to Purchaser', 'Cash taken from cashiers'),
              _sheet('Expenses', 'All expenses with details'),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.orange.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'All sheets are linked with formulas. Change any amount in Excel and every total, the Daily '
                  'sheet and the Summary page update automatically.',
                  style: TextStyle(fontSize: 13),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : _export,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.table_view),
            label: const Text('Generate & Share Excel'),
          ),
          const SizedBox(height: 8),
          Text('Amounts are in ${Money.symbol}. Save to Drive/Files, or send via WhatsApp / email.',
              textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _sheet(String name, String desc) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.grid_on, size: 18, color: AppColors.success),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(TextSpan(children: [
              TextSpan(text: '$name  ', style: const TextStyle(fontWeight: FontWeight.w700)),
              TextSpan(text: desc, style: TextStyle(color: Colors.grey.shade700)),
            ])),
          ),
        ]),
      );
}
