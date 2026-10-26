import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/date_range.dart';
import '../../core/enums.dart';
import '../../core/money.dart';
import '../../data/models/expense.dart';
import '../../services/app_services.dart';
import '../widgets/common.dart';
import 'entry_forms.dart';

class ExpenseForm extends StatefulWidget {
  const ExpenseForm({super.key, this.existing});
  final Expense? existing;

  @override
  State<ExpenseForm> createState() => _ExpenseFormState();
}

class _ExpenseFormState extends State<ExpenseForm> {
  final _form = GlobalKey<FormState>();
  late DateTime _date;
  String? _counterId;
  String? _cashierId;
  String _category = expenseCategories.first;
  PaymentMethod _method = PaymentMethod.cash;
  final _amount = TextEditingController();
  final _desc = TextEditingController();
  Lookups? _lookups;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _date = e == null ? dateOnly(DateTime.now()) : fromDbDate(e.date);
    if (e != null) {
      _counterId = e.counterId;
      _cashierId = e.cashierId;
      _category = e.category;
      _method = e.method;
      _amount.text = Money.toInput(e.amount);
      _desc.text = e.description;
    }
    _load();
  }

  Future<void> _load() async {
    final l = await Lookups.load(context.read<AppServices>(), counterId: _counterId, cashierId: _cashierId);
    if (!mounted) return;
    setState(() {
      _lookups = l;
      if (widget.existing == null) _counterId = l.counters.firstOrNull?.id;
    });
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final s = context.read<AppServices>();
    await saveEntity(
      context,
      s.expenses,
      Expense(
        id: widget.existing?.id ?? const Uuid().v4(),
        date: toDbDate(_date),
        amount: Money.tryParse(_amount.text)!,
        category: _category,
        counterId: _counterId,
        cashierId: _counterId == null ? null : _cashierId,
        method: _method,
        description: _desc.text.trim(),
      ),
      (v) {
        if (mounted) setState(() => _saving = v);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = _lookups;
    if (l == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final categories = {...expenseCategories, _category}.toList();
    return EntryFormScaffold(
      title: widget.existing == null ? 'New Expense' : 'Edit Expense',
      formKey: _form,
      saving: _saving,
      onSave: _save,
      onDelete: widget.existing == null
          ? null
          : () => deleteEntity(context, context.read<AppServices>().expenses, widget.existing!),
      children: [
        DateField(value: _date, onChanged: (d) => setState(() => _date = d)),
        counterDropdown(l, _counterId, (v) => setState(() {
              _counterId = v;
              if (v == null) _cashierId = null;
            }), allowGeneral: true),
        if (_counterId != null)
          cashierDropdown(l, _counterId, _cashierId, (v) => setState(() => _cashierId = v), optional: true),
        DropdownButtonFormField<String>(
          initialValue: _category,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Category', prefixIcon: Icon(Icons.category)),
          items: [for (final c in categories) DropdownMenuItem(value: c, child: Text(c))],
          onChanged: (v) => setState(() => _category = v ?? _category),
        ),
        AmountField(controller: _amount, label: 'Amount', icon: Icons.payments, required: true, allowZero: false),
        DropdownButtonFormField<PaymentMethod>(
          isExpanded: true,
          initialValue: _method,
          decoration: const InputDecoration(labelText: 'Paid by', prefixIcon: Icon(Icons.account_balance_wallet)),
          items: [for (final m in PaymentMethod.salesMethods) DropdownMenuItem(value: m, child: Text(m.label))],
          onChanged: (v) => setState(() => _method = v ?? PaymentMethod.cash),
        ),
        if (_counterId != null && _cashierId != null && _method == PaymentMethod.cash)
          Text('This cash will be deducted from the cashier\'s expected drawer cash.',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
        TextFormField(
          controller: _desc,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Details', prefixIcon: Icon(Icons.notes)),
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Please describe the expense' : null,
        ),
      ],
    );
  }
}
