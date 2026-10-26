import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/date_range.dart';
import '../../core/enums.dart';
import '../../core/money.dart';
import '../../data/models/purchase.dart';
import '../../services/app_services.dart';
import '../widgets/common.dart';
import 'entry_forms.dart';

class PurchaseForm extends StatefulWidget {
  const PurchaseForm({super.key, this.existing});
  final Purchase? existing;

  @override
  State<PurchaseForm> createState() => _PurchaseFormState();
}

class _PurchaseFormState extends State<PurchaseForm> {
  final _form = GlobalKey<FormState>();
  late DateTime _date;
  PaymentMethod _method = PaymentMethod.cash;
  final _amount = TextEditingController();
  final _supplier = TextEditingController();
  final _invoice = TextEditingController();
  final _desc = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _date = e == null ? dateOnly(DateTime.now()) : fromDbDate(e.date);
    if (e != null) {
      _method = e.method;
      _amount.text = Money.toInput(e.amount);
      _supplier.text = e.supplier;
      _invoice.text = e.invoiceNo;
      _desc.text = e.description;
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final s = context.read<AppServices>();
    await saveEntity(
      context,
      s.purchases,
      Purchase(
        id: widget.existing?.id ?? const Uuid().v4(),
        date: toDbDate(_date),
        amount: Money.tryParse(_amount.text)!,
        supplier: _supplier.text.trim(),
        invoiceNo: _invoice.text.trim(),
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
    return EntryFormScaffold(
      title: widget.existing == null ? 'New Purchase' : 'Edit Purchase',
      formKey: _form,
      saving: _saving,
      onSave: _save,
      onDelete: widget.existing == null
          ? null
          : () => deleteEntity(context, context.read<AppServices>().purchases, widget.existing!),
      children: [
        DateField(value: _date, onChanged: (d) => setState(() => _date = d)),
        TextFormField(
          controller: _supplier,
          decoration: const InputDecoration(labelText: 'Supplier / Vendor', prefixIcon: Icon(Icons.local_shipping)),
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
        ),
        TextFormField(
          controller: _invoice,
          decoration: const InputDecoration(labelText: 'Invoice / Bill # (optional)', prefixIcon: Icon(Icons.tag)),
        ),
        AmountField(controller: _amount, label: 'Purchase amount', icon: Icons.payments, required: true, allowZero: false),
        DropdownButtonFormField<PaymentMethod>(
          isExpanded: true,
          initialValue: _method,
          decoration: const InputDecoration(labelText: 'Paid by', prefixIcon: Icon(Icons.account_balance_wallet)),
          items: [
            for (final m in PaymentMethod.values) DropdownMenuItem(value: m, child: Text(m.label)),
          ],
          onChanged: (v) => setState(() => _method = v ?? PaymentMethod.cash),
        ),
        TextFormField(
          controller: _desc,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Items / details', prefixIcon: Icon(Icons.notes)),
        ),
      ],
    );
  }
}
