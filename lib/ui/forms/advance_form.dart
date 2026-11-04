import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/date_range.dart';
import '../../core/money.dart';
import '../../data/models/purchaser_advance.dart';
import '../../services/app_services.dart';
import '../widgets/common.dart';
import 'entry_forms.dart';

/// Cash given to a purchaser before buying (e.g. Rs 2 lac in the morning).
class AdvanceForm extends StatefulWidget {
  const AdvanceForm({super.key, this.existing});
  final PurchaserAdvance? existing;

  @override
  State<AdvanceForm> createState() => _AdvanceFormState();
}

class _AdvanceFormState extends State<AdvanceForm> {
  final _form = GlobalKey<FormState>();
  late DateTime _date;
  final _amount = TextEditingController();
  final _name = TextEditingController();
  final _notes = TextEditingController();
  List<String> _names = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _date = e == null ? dateOnly(DateTime.now()) : fromDbDate(e.date);
    if (e != null) {
      _amount.text = Money.toInput(e.amount);
      _name.text = e.purchaserName;
      _notes.text = e.notes;
    }
    context.read<AppServices>().purchaserNames().then((n) {
      if (!mounted) return;
      setState(() {
        _names = n;
        if (widget.existing == null && n.length == 1) _name.text = n.first;
      });
    });
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    await saveEntity(
      context,
      context.read<AppServices>().advances,
      PurchaserAdvance(
        id: widget.existing?.id ?? const Uuid().v4(),
        date: toDbDate(_date),
        purchaserName: _name.text.trim(),
        amount: Money.tryParse(_amount.text)!,
        notes: _notes.text.trim(),
      ),
      (v) {
        if (mounted) setState(() => _saving = v);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return EntryFormScaffold(
      title: widget.existing == null ? 'Advance to Purchaser' : 'Edit Advance',
      formKey: _form,
      saving: _saving,
      onSave: _save,
      onDelete: widget.existing == null
          ? null
          : () => deleteEntity(context, context.read<AppServices>().advances, widget.existing!),
      children: [
        Text(
          'Cash given to the purchaser before buying. At the end of the day the app compares it with the '
          'cash purchases: if he spent more, the extra must be taken from a counter; if he spent less, '
          'the rest is shown in green to return.',
          style: TextStyle(color: Colors.grey.shade700),
        ),
        DateField(value: _date, onChanged: (d) => setState(() => _date = d)),
        PurchaserNameField(controller: _name, names: _names),
        AmountField(
          controller: _amount,
          label: 'Advance amount',
          icon: Icons.payments,
          required: true,
          allowZero: false,
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
