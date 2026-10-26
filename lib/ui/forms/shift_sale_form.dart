import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/date_range.dart';
import '../../core/enums.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/models/shift_sale.dart';
import '../../services/app_services.dart';
import '../widgets/common.dart';
import 'entry_forms.dart';

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
  String _start = '';
  String _end = '';
  final _opening = TextEditingController();
  final _cash = TextEditingController();
  final _pos = TextEditingController();
  final _online = TextEditingController();
  final _jazz = TextEditingController();
  final _closing = TextEditingController();
  final _notes = TextEditingController();
  Lookups? _lookups;
  bool _saving = false;
  int _handed = 0;
  int _cashExp = 0;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _date = e == null ? dateOnly(DateTime.now()) : fromDbDate(e.date);
    if (e != null) {
      _counterId = e.counterId;
      _cashierId = e.cashierId;
      _start = e.startTime;
      _end = e.endTime;
      _opening.text = Money.toInput(e.openingCash);
      _cash.text = Money.toInput(e.cash);
      _pos.text = Money.toInput(e.pos);
      _online.text = Money.toInput(e.online);
      _jazz.text = Money.toInput(e.jazzcash);
      _closing.text = e.closingCash == null ? '' : (e.closingCash == 0 ? '0' : Money.toInput(e.closingCash!));
      _notes.text = e.notes;
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
    _loadDeductions();
  }

  /// Cash taken by the purchaser and cash expenses for this cashier/day –
  /// needed to know how much cash must be in the drawer.
  Future<void> _loadDeductions() async {
    if (_counterId == null || _cashierId == null) {
      setState(() => _handed = _cashExp = 0);
      return;
    }
    final s = context.read<AppServices>();
    final d = toDbDate(_date);
    final args = [d, _counterId, _cashierId];
    final h = await s.handovers.query(where: 'date = ? AND counter_id = ? AND cashier_id = ?', args: args);
    final e = await s.expenses.query(
        where: "date = ? AND counter_id = ? AND cashier_id = ? AND payment_method = 'cash'", args: args);
    if (!mounted) return;
    setState(() {
      _handed = h.fold(0, (a, b) => a + b.amount);
      _cashExp = e.fold(0, (a, b) => a + b.amount);
    });
  }

  int _v(TextEditingController c) => Money.tryParse(c.text) ?? 0;

  ShiftSale _build() => ShiftSale(
        id: widget.existing?.id ?? const Uuid().v4(),
        date: toDbDate(_date),
        counterId: _counterId!,
        cashierId: _cashierId!,
        startTime: _start,
        endTime: _end,
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
        !await confirm(context, 'Possible duplicate',
            'This cashier already has ${dup.length} shift entry on this counter for ${displayDate(item.date)}. '
            'Save another one?',
            ok: 'Save anyway')) {
      return;
    }
    if (!mounted) return;
    final expected = item.openingCash + item.cash - _handed - _cashExp;
    if (item.closingCash != null && item.closingCash != expected) {
      final diff = item.closingCash! - expected;
      if (!await confirm(context, diff < 0 ? 'Cash is SHORT' : 'Cash is in EXCESS',
          'Expected ${Money.format(expected)} but counted ${Money.format(item.closingCash!)}.\n'
          'Difference: ${Money.format(diff.abs())} ${diff < 0 ? 'short' : 'excess'}.\n\nSave this shift?',
          ok: 'Save')) {
        return;
      }
    }
    if (!mounted) return;
    await saveEntity(context, s.shifts, item, (v) {
      if (mounted) setState(() => _saving = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = _lookups;
    if (l == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final total = _v(_cash) + _v(_pos) + _v(_online) + _v(_jazz);
    final expected = _v(_opening) + _v(_cash) - _handed - _cashExp;
    final counted = _closing.text.trim().isEmpty ? null : _v(_closing);
    final diff = counted == null ? null : counted - expected;
    void refresh(_) => setState(() {});

    return EntryFormScaffold(
      title: widget.existing == null ? 'New Shift Sale' : 'Edit Shift Sale',
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
              _loadDeductions();
            }),
        counterDropdown(l, _counterId, (v) {
          setState(() => _counterId = v);
          _loadDeductions();
        }),
        cashierDropdown(l, _counterId, _cashierId, (v) {
          setState(() => _cashierId = v);
          _loadDeductions();
        }),
        Row(children: [
          Expanded(child: TimeField(label: 'Duty start', value: _start, onChanged: (v) => setState(() => _start = v))),
          const SizedBox(width: 12),
          Expanded(child: TimeField(label: 'Duty end', value: _end, onChanged: (v) => setState(() => _end = v))),
        ]),
        AmountField(
            controller: _opening,
            label: 'Opening cash in drawer (float)',
            icon: Icons.inventory_2_outlined,
            onChanged: refresh),
        const Text('Sales by payment method',
            style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.navy, fontSize: 15)),
        AmountField(controller: _cash, label: PaymentMethod.cash.label, icon: PaymentMethod.cash.icon, onChanged: refresh),
        AmountField(controller: _pos, label: PaymentMethod.pos.label, icon: PaymentMethod.pos.icon, onChanged: refresh),
        AmountField(
            controller: _online, label: PaymentMethod.online.label, icon: PaymentMethod.online.icon, onChanged: refresh),
        AmountField(
            controller: _jazz, label: PaymentMethod.jazzcash.label, icon: PaymentMethod.jazzcash.icon, onChanged: refresh),
        Card(
          color: AppColors.navy,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              const Expanded(
                  child: Text('Total Sale', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
              Text(Money.format(total),
                  style: const TextStyle(color: AppColors.orange, fontWeight: FontWeight.w900, fontSize: 20)),
            ]),
          ),
        ),
        AmountField(
          controller: _closing,
          label: 'Cash counted at hand-over (optional)',
          icon: Icons.calculate_outlined,
          helper: 'Count the drawer when the cashier hands over to check for shortage',
          onChanged: refresh,
        ),
        SectionCard(
          title: 'Cash Reconciliation',
          child: Column(children: [
            MoneyRow('Opening cash', _v(_opening)),
            MoneyRow('+ Cash sales', _v(_cash)),
            MoneyRow('− Cash given to purchaser', _handed, color: AppColors.handover),
            MoneyRow('− Cash expenses from drawer', _cashExp, color: AppColors.expense),
            const Divider(),
            MoneyRow('Expected cash in drawer', expected, bold: true),
            if (diff != null)
              MoneyRow(
                diff == 0 ? 'Balanced ✓' : (diff < 0 ? 'SHORT' : 'EXCESS'),
                diff.abs(),
                bold: true,
                color: diff == 0 ? AppColors.success : (diff < 0 ? AppColors.danger : AppColors.warning),
              ),
          ]),
        ),
        TextFormField(
          controller: _notes,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'Notes (optional)', prefixIcon: Icon(Icons.notes)),
        ),
      ],
    );
  }
}
