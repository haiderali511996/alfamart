import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/date_range.dart';
import '../../core/money.dart';
import '../../data/models/cash_handover.dart';
import '../../services/app_services.dart';
import '../widgets/common.dart';
import 'entry_forms.dart';

/// Purchaser takes cash out of a cashier's drawer.
class HandoverForm extends StatefulWidget {
  const HandoverForm({super.key, this.existing});
  final CashHandover? existing;

  @override
  State<HandoverForm> createState() => _HandoverFormState();
}

class _HandoverFormState extends State<HandoverForm> {
  final _form = GlobalKey<FormState>();
  late DateTime _date;
  String _time = '';
  String? _counterId;
  String? _cashierId;
  final _amount = TextEditingController();
  final _purchaser = TextEditingController();
  final _purpose = TextEditingController();
  final _purchaserFocus = FocusNode();
  Lookups? _lookups;
  List<String> _knownPurchasers = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _date = e == null ? dateOnly(DateTime.now()) : fromDbDate(e.date);
    if (e != null) {
      _time = e.time;
      _counterId = e.counterId;
      _cashierId = e.cashierId;
      _amount.text = Money.toInput(e.amount);
      _purchaser.text = e.purchaserName;
      _purpose.text = e.purpose;
    } else {
      final now = TimeOfDay.now();
      _time = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    }
    _load();
  }

  Future<void> _load() async {
    final s = context.read<AppServices>();
    final l = await Lookups.load(s, counterId: _counterId, cashierId: _cashierId);
    final rows = await s.database.db.rawQuery(
        'SELECT DISTINCT purchaser_name FROM cash_handovers WHERE is_deleted = 0 ORDER BY purchaser_name');
    if (!mounted) return;
    setState(() {
      _lookups = l;
      _counterId ??= l.counters.firstOrNull?.id;
      _knownPurchasers = rows.map((r) => r['purchaser_name'] as String).toList();
    });
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final s = context.read<AppServices>();
    await saveEntity(
      context,
      s.handovers,
      CashHandover(
        id: widget.existing?.id ?? const Uuid().v4(),
        date: toDbDate(_date),
        time: _time,
        counterId: _counterId!,
        cashierId: _cashierId!,
        purchaserName: _purchaser.text.trim(),
        amount: Money.tryParse(_amount.text)!,
        purpose: _purpose.text.trim(),
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
    return EntryFormScaffold(
      title: widget.existing == null ? 'Cash to Purchaser' : 'Edit Cash to Purchaser',
      formKey: _form,
      saving: _saving,
      onSave: _save,
      onDelete: widget.existing == null
          ? null
          : () => deleteEntity(context, context.read<AppServices>().handovers, widget.existing!),
      children: [
        noCashiersHint(context, l),
        Row(children: [
          Expanded(flex: 3, child: DateField(value: _date, onChanged: (d) => setState(() => _date = d))),
          const SizedBox(width: 12),
          Expanded(flex: 2, child: TimeField(label: 'Time', value: _time, onChanged: (v) => setState(() => _time = v))),
        ]),
        counterDropdown(l, _counterId, (v) => setState(() => _counterId = v)),
        cashierDropdown(l, _counterId, _cashierId, (v) => setState(() => _cashierId = v)),
        RawAutocomplete<String>(
          textEditingController: _purchaser,
          focusNode: _purchaserFocus,
          optionsViewBuilder: (context, onSelected, options) => Align(
            alignment: Alignment.topLeft,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220, maxWidth: 360),
                child: ListView(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  children: [for (final o in options) ListTile(title: Text(o), onTap: () => onSelected(o))],
                ),
              ),
            ),
          ),
          optionsBuilder: (v) => _knownPurchasers
              .where((p) => p.toLowerCase().contains(v.text.toLowerCase()) && p.toLowerCase() != v.text.toLowerCase()),
          fieldViewBuilder: (context, controller, focus, onSubmit) {
            return TextFormField(
              controller: controller,
              focusNode: focus,
              decoration: const InputDecoration(labelText: 'Purchaser name', prefixIcon: Icon(Icons.badge)),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            );
          },
        ),
        AmountField(controller: _amount, label: 'Amount taken', icon: Icons.payments, required: true, allowZero: false),
        TextFormField(
          controller: _purpose,
          maxLines: 3,
          decoration: const InputDecoration(
              labelText: 'Purpose / details (what will be bought)', prefixIcon: Icon(Icons.notes)),
        ),
      ],
    );
  }
}
