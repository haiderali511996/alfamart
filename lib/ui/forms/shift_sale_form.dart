import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/date_range.dart';
import '../../core/enums.dart';
import '../../core/money.dart';
import '../../core/shop_config.dart';
import '../../core/theme.dart';
import '../../data/models/cash_handover.dart';
import '../../data/models/expense.dart';
import '../../data/models/shift_sale.dart';
import '../../services/app_services.dart';
import '../../services/auth_service.dart';
import '../widgets/common.dart';
import 'entry_forms.dart';
import 'expense_form.dart';
import 'handover_form.dart';

class _DraftExpense {
  _DraftExpense(this.category, this.amount, this.details);
  final String category;
  final int amount;
  final String details;
}

class _DraftHandover {
  _DraftHandover(this.purchaser, this.amount, this.purpose);
  final String purchaser;
  final int amount;
  final String purpose;
}

/// One screen for a counter's day: sales by payment method, the expenses
/// paid from the drawer, cash given to the purchaser, and the cash check.
class ShiftSaleForm extends StatefulWidget {
  const ShiftSaleForm({super.key, this.existing});
  final ShiftSale? existing;

  @override
  State<ShiftSaleForm> createState() => _ShiftSaleFormState();
}

class _ShiftSaleFormState extends State<ShiftSaleForm> {
  final _form = GlobalKey<FormState>();
  late DateTime _date;
  String? _counterId;
  String? _cashierId;
  final _opening = TextEditingController();
  final _cash = TextEditingController();
  final _pos = TextEditingController();
  final _online = TextEditingController();
  final _jazz = TextEditingController();
  final _closing = TextEditingController();
  final _notes = TextEditingController();
  Lookups? _lookups;
  bool _saving = false;

  /// Already saved for this date / counter / cashier.
  List<Expense> _expenses = [];
  List<CashHandover> _handovers = [];

  /// Added on this screen, saved together with the sale.
  final List<_DraftExpense> _newExpenses = [];
  final List<_DraftHandover> _newHandovers = [];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _date = e == null ? dateOnly(DateTime.now()) : fromDbDate(e.date);
    if (e != null) {
      _counterId = e.counterId;
      _cashierId = e.cashierId;
      _opening.text = e.openingCash == 0 ? '0' : Money.toInput(e.openingCash);
      _cash.text = Money.toInput(e.cash);
      _pos.text = Money.toInput(e.pos);
      _online.text = Money.toInput(e.online);
      _jazz.text = Money.toInput(e.jazzcash);
      _closing.text = e.closingCash == null ? '' : (e.closingCash == 0 ? '0' : Money.toInput(e.closingCash!));
      _notes.text = e.notes;
    } else {
      _opening.text = Money.toInput(ShopConfig.openingCash);
    }
    _load();
  }

  Future<void> _load() async {
    final s = context.read<AppServices>();
    final l = await Lookups.load(s, counterId: _counterId, cashierId: _cashierId);
    if (!mounted) return;
    setState(() {
      _lookups = l;
      _counterId ??= l.counters.firstOrNull?.id;
    });
    _loadLinked();
  }

  /// Expenses and cash to purchaser already recorded for this cashier/day.
  Future<void> _loadLinked() async {
    if (_counterId == null || _cashierId == null) {
      setState(() {
        _expenses = [];
        _handovers = [];
      });
      return;
    }
    final s = context.read<AppServices>();
    final args = [toDbDate(_date), _counterId, _cashierId];
    const where = 'date = ? AND counter_id = ? AND cashier_id = ?';
    final h = await s.handovers.query(where: where, args: args, orderBy: 'created_at');
    final e = await s.expenses.query(where: where, args: args, orderBy: 'created_at');
    if (!mounted) return;
    setState(() {
      _handovers = h;
      _expenses = e;
    });
  }

  int _v(TextEditingController c) => Money.tryParse(c.text) ?? 0;

  int get _expenseTotal => _expenses.fold(0, (a, b) => a + b.amount) + _newExpenses.fold(0, (a, b) => a + b.amount);

  /// Only cash expenses come out of the drawer.
  int get _cashExpenseTotal =>
      _expenses.where((e) => e.method == PaymentMethod.cash).fold(0, (a, b) => a + b.amount) +
      _newExpenses.fold(0, (a, b) => a + b.amount);

  int get _handoverTotal => _handovers.fold(0, (a, b) => a + b.amount) + _newHandovers.fold(0, (a, b) => a + b.amount);

  ShiftSale _build() => ShiftSale(
    id: widget.existing?.id ?? const Uuid().v4(),
    date: toDbDate(_date),
    counterId: _counterId!,
    cashierId: _cashierId!,
    startTime: ShopConfig.dutyStart,
    endTime: ShopConfig.dutyEnd,
    openingCash: _v(_opening),
    cash: _v(_cash),
    pos: _v(_pos),
    online: _v(_online),
    jazzcash: _v(_jazz),
    closingCash: _closing.text.trim().isEmpty ? null : _v(_closing),
    notes: _notes.text.trim(),
  );

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final item = _build();
    final s = context.read<AppServices>();
    final dup = await s.shifts.query(
      where: 'date = ? AND counter_id = ? AND cashier_id = ? AND id != ?',
      args: [item.date, item.counterId, item.cashierId, item.id],
    );
    if (!mounted) return;
    if (dup.isNotEmpty &&
        !await confirm(
          context,
          'Possible duplicate',
          'This cashier already has ${dup.length} sale entry on this counter for ${displayDate(item.date)}. '
              'Save another one?',
          ok: 'Save anyway',
        )) {
      return;
    }
    if (!mounted) return;
    final expected = item.openingCash + item.cash - _handoverTotal - _cashExpenseTotal;
    if (item.closingCash != null && item.closingCash != expected) {
      final diff = item.closingCash! - expected;
      if (!await confirm(
        context,
        diff < 0 ? 'Cash is SHORT' : 'Cash is in EXCESS',
        'Expected ${Money.format(expected)} but counted ${Money.format(item.closingCash!)}.\n'
        'Difference: ${Money.format(diff.abs())} ${diff < 0 ? 'short' : 'excess'}.\n\nSave this sale?',
        ok: 'Save',
      )) {
        return;
      }
    }
    if (!mounted) return;
    setState(() => _saving = true);
    try {
      final actor = context.read<AuthService>().actor;
      await s.shifts.save(item, actor);
      for (final d in _newExpenses) {
        await s.expenses.save(
          Expense(
            id: const Uuid().v4(),
            date: item.date,
            amount: d.amount,
            category: d.category,
            counterId: item.counterId,
            cashierId: item.cashierId,
            method: PaymentMethod.cash,
            description: d.details,
          ),
          actor,
        );
      }
      for (final d in _newHandovers) {
        await s.handovers.save(
          CashHandover(
            id: const Uuid().v4(),
            date: item.date,
            counterId: item.counterId,
            cashierId: item.cashierId,
            purchaserName: d.purchaser,
            amount: d.amount,
            purpose: d.purpose,
          ),
          actor,
        );
      }
      if (mounted) {
        showSnack(context, 'Saved');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) showSnack(context, 'Could not save: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addExpense() async {
    final amount = TextEditingController();
    final details = TextEditingController();
    var category = expenseCategories.first;
    final key = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Add Expense'),
          content: Form(
            key: key,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: category,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: [for (final c in expenseCategories) DropdownMenuItem(value: c, child: Text(c))],
                    onChanged: (v) => setState(() => category = v ?? category),
                  ),
                  const SizedBox(height: 12),
                  AmountField(controller: amount, label: 'Amount', required: true, allowZero: false),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: details,
                    decoration: const InputDecoration(labelText: 'Details'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Please describe the expense' : null,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (key.currentState!.validate()) Navigator.pop(ctx, true);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      setState(() => _newExpenses.add(_DraftExpense(category, Money.tryParse(amount.text)!, details.text.trim())));
    }
  }

  Future<void> _addHandover() async {
    final names = await context.read<AppServices>().purchaserNames();
    if (!mounted) return;
    final amount = TextEditingController();
    final purpose = TextEditingController();
    final name = TextEditingController(text: names.length == 1 ? names.first : '');
    final key = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cash Given to Purchaser'),
        content: Form(
          key: key,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PurchaserNameField(controller: name, names: names),
                const SizedBox(height: 12),
                AmountField(controller: amount, label: 'Amount given', required: true, allowZero: false),
                const SizedBox(height: 12),
                TextFormField(
                  controller: purpose,
                  decoration: const InputDecoration(labelText: 'Purpose (optional)'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (key.currentState!.validate()) Navigator.pop(ctx, true);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (ok == true) {
      setState(
        () => _newHandovers.add(_DraftHandover(name.text.trim(), Money.tryParse(amount.text)!, purpose.text.trim())),
      );
    }
  }

  Future<void> _open(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    _loadLinked();
  }

  @override
  Widget build(BuildContext context) {
    final l = _lookups;
    if (l == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final total = _v(_cash) + _v(_pos) + _v(_online) + _v(_jazz);
    final expected = _v(_opening) + _v(_cash) - _handoverTotal - _cashExpenseTotal;
    final counted = _closing.text.trim().isEmpty ? null : _v(_closing);
    final diff = counted == null ? null : counted - expected;
    final ready = _counterId != null && _cashierId != null;
    void refresh(_) => setState(() {});

    return EntryFormScaffold(
      title: widget.existing == null ? 'Counter Sale' : 'Edit Counter Sale',
      formKey: _form,
      saving: _saving,
      onSave: _save,
      onDelete: widget.existing == null
          ? null
          : () => deleteEntity(context, context.read<AppServices>().shifts, widget.existing!),
      children: [
        noCashiersHint(context, l),
        DateField(
          value: _date,
          onChanged: (d) {
            setState(() => _date = d);
            _loadLinked();
          },
        ),
        counterDropdown(l, _counterId, (v) {
          setState(() => _counterId = v);
          _loadLinked();
        }),
        cashierDropdown(l, _counterId, _cashierId, (v) {
          setState(() => _cashierId = v);
          _loadLinked();
        }),
        Row(
          children: [
            const Icon(Icons.schedule, size: 18, color: AppColors.navy),
            const SizedBox(width: 6),
            Expanded(
              child: Text('Duty time: ${ShopConfig.dutyLabel}', style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        AmountField(
          controller: _opening,
          label: 'Opening cash in drawer',
          icon: Icons.inventory_2_outlined,
          helper: 'Every counter starts with ${Money.format(ShopConfig.openingCash)}',
          onChanged: refresh,
        ),

        // ── Sales
        _heading('Sales by payment method', AppColors.sales),
        AmountField(
          controller: _cash,
          label: PaymentMethod.cash.label,
          icon: PaymentMethod.cash.icon,
          onChanged: refresh,
        ),
        AmountField(controller: _pos, label: PaymentMethod.pos.label, icon: PaymentMethod.pos.icon, onChanged: refresh),
        AmountField(
          controller: _online,
          label: PaymentMethod.online.label,
          icon: PaymentMethod.online.icon,
          onChanged: refresh,
        ),
        AmountField(
          controller: _jazz,
          label: PaymentMethod.jazzcash.label,
          icon: PaymentMethod.jazzcash.icon,
          onChanged: refresh,
        ),
        _totalBar('Total Sale', total),

        // ── Expenses
        _heading(
          'Expenses from this counter',
          AppColors.expense,
          trailing: TextButton.icon(
            onPressed: ready ? _addExpense : null,
            icon: const Icon(Icons.add),
            label: const Text('Add expense'),
          ),
        ),
        _lineCard(
          empty: ready ? 'No expenses yet' : 'Select the counter and cashier first',
          lines: [
            for (final e in _expenses)
              _line(
                e.category,
                e.description,
                e.amount,
                note: e.method == PaymentMethod.cash ? null : 'paid by ${e.method.label}',
                onTap: () => _open(ExpenseForm(existing: e)),
              ),
            for (final d in _newExpenses)
              _line(
                d.category,
                d.details,
                d.amount,
                isNew: true,
                onRemove: () => setState(() => _newExpenses.remove(d)),
              ),
          ],
          total: _expenseTotal,
          color: AppColors.expense,
        ),

        // ── Cash to purchaser
        _heading(
          'Cash given to purchaser',
          AppColors.handover,
          trailing: TextButton.icon(
            onPressed: ready ? _addHandover : null,
            icon: const Icon(Icons.add),
            label: const Text('Add'),
          ),
        ),
        _lineCard(
          empty: ready ? 'No cash given to the purchaser' : 'Select the counter and cashier first',
          lines: [
            for (final h in _handovers)
              _line(h.purchaserName, h.purpose, h.amount, onTap: () => _open(HandoverForm(existing: h))),
            for (final d in _newHandovers)
              _line(
                d.purchaser,
                d.purpose,
                d.amount,
                isNew: true,
                onRemove: () => setState(() => _newHandovers.remove(d)),
              ),
          ],
          total: _handoverTotal,
          color: AppColors.handover,
        ),

        // ── Day summary
        SectionCard(
          title: 'Counter Summary',
          child: Column(
            children: [
              MoneyRow('Total sale', total, bold: true, color: AppColors.sales),
              MoneyRow('− Expenses', _expenseTotal, color: AppColors.expense),
              MoneyRow('− Given to purchaser', _handoverTotal, color: AppColors.handover),
              const Divider(),
              MoneyRow('Sale after expenses & purchaser', total - _expenseTotal - _handoverTotal, bold: true),
            ],
          ),
        ),
        AmountField(
          controller: _closing,
          label: 'Cash counted in drawer (optional)',
          icon: Icons.calculate_outlined,
          helper: 'Count the drawer at closing to check for shortage',
          onChanged: refresh,
        ),
        SectionCard(
          title: 'Cash in Drawer',
          child: Column(
            children: [
              MoneyRow('Opening cash', _v(_opening)),
              MoneyRow('+ Cash sales', _v(_cash)),
              MoneyRow('− Cash expenses', _cashExpenseTotal, color: AppColors.expense),
              MoneyRow('− Given to purchaser', _handoverTotal, color: AppColors.handover),
              const Divider(),
              MoneyRow('Expected cash in drawer', expected, bold: true),
              if (diff != null)
                MoneyRow(
                  diff == 0 ? 'Balanced ✓' : (diff < 0 ? 'SHORT' : 'EXCESS'),
                  diff.abs(),
                  bold: true,
                  color: diff == 0 ? AppColors.success : (diff < 0 ? AppColors.danger : AppColors.warning),
                ),
            ],
          ),
        ),
        TextFormField(
          controller: _notes,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'Notes (optional)', prefixIcon: Icon(Icons.notes)),
        ),
      ],
    );
  }

  Widget _heading(String text, Color color, {Widget? trailing}) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(
      children: [
        Container(width: 4, height: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.navy, fontSize: 15),
          ),
        ),
        ?trailing,
      ],
    ),
  );

  Widget _totalBar(String label, int amount) => Card(
    color: AppColors.navy,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ),
          Text(
            Money.format(amount),
            style: const TextStyle(color: AppColors.orange, fontWeight: FontWeight.w900, fontSize: 20),
          ),
        ],
      ),
    ),
  );

  Widget _lineCard({required String empty, required List<Widget> lines, required int total, required Color color}) =>
      Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (lines.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(empty, style: TextStyle(color: Colors.grey.shade600)),
                )
              else ...[
                ...lines,
                const Divider(),
                MoneyRow('Total', total, bold: true, color: color),
              ],
            ],
          ),
        ),
      );

  Widget _line(
    String title,
    String subtitle,
    int amount, {
    String? note,
    bool isNew = false,
    VoidCallback? onTap,
    VoidCallback? onRemove,
  }) => ListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    onTap: onTap,
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
    subtitle: Text([if (subtitle.isNotEmpty) subtitle, ?note, if (isNew) 'new – saved with this sale'].join(' · ')),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(Money.format(amount), style: const TextStyle(fontWeight: FontWeight.w700)),
        if (onRemove != null)
          IconButton(tooltip: 'Remove', icon: const Icon(Icons.close, size: 18), onPressed: onRemove),
      ],
    ),
  );
}
