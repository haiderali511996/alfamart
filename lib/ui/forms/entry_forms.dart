import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../data/models/cashier.dart';
import '../../data/models/counter.dart';
import '../../data/models/entity.dart';
import '../../data/repositories/repository.dart';
import '../../services/app_services.dart';
import '../../services/auth_service.dart';
import '../widgets/common.dart';
import 'expense_form.dart';
import 'handover_form.dart';
import 'purchase_form.dart';
import 'shift_sale_form.dart';

Future<void> showAddEntrySheet(BuildContext context) async {
  final choice = await showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('Add Daily Entry', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ),
            _option(
              ctx,
              0,
              Icons.point_of_sale,
              AppColors.sales,
              'Shift Sale',
              'Cashier sales on a counter (Cash, POS, Online, JazzCash)',
            ),
            _option(ctx, 1, Icons.shopping_cart, AppColors.purchase, 'Purchase', 'Stock purchased today'),
            _option(
              ctx,
              2,
              Icons.handshake,
              AppColors.handover,
              'Cash to Purchaser',
              'Cash taken from a cashier by the purchaser',
            ),
            _option(ctx, 3, Icons.receipt, AppColors.expense, 'Expense', 'Counter / cashier / shop expense'),
            const SizedBox(height: 12),
          ],
        ),
      ),
    ),
  );
  if (choice == null || !context.mounted) return;
  final page = switch (choice) {
    0 => const ShiftSaleForm(),
    1 => const PurchaseForm(),
    2 => const HandoverForm(),
    _ => const ExpenseForm(),
  };
  await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
}

Widget _option(BuildContext ctx, int v, IconData icon, Color color, String title, String sub) => ListTile(
  leading: CircleAvatar(
    backgroundColor: color.withValues(alpha: 0.12),
    child: Icon(icon, color: color),
  ),
  title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
  subtitle: Text(sub),
  trailing: const Icon(Icons.chevron_right),
  onTap: () => Navigator.pop(ctx, v),
);

/// Shared layout for all entry forms: scrolling fields, a delete action
/// (admins only, when editing) and a fixed Save button.
class EntryFormScaffold extends StatelessWidget {
  const EntryFormScaffold({
    super.key,
    required this.title,
    required this.formKey,
    required this.children,
    required this.onSave,
    required this.saving,
    this.onDelete,
  });

  final String title;
  final GlobalKey<FormState> formKey;
  final List<Widget> children;
  final VoidCallback onSave;
  final VoidCallback? onDelete;
  final bool saving;

  @override
  Widget build(BuildContext context) {
    final isAdmin = context.watch<AuthService>().isAdmin;
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (onDelete != null && isAdmin)
            IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline), onPressed: onDelete),
        ],
      ),
      body: Form(
        key: formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final c in children) Padding(padding: const EdgeInsets.only(bottom: 12), child: c),
            const SizedBox(height: 60),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: saving ? null : onSave,
            icon: saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check),
            label: const Text('Save'),
          ),
        ),
      ),
    );
  }
}

/// Lookup lists used by the forms (includes the currently selected
/// counter/cashier even if they were deactivated later).
class Lookups {
  Lookups(this.counters, this.cashiers);
  final List<Counter> counters;
  final List<Cashier> cashiers;

  static Future<Lookups> load(AppServices s, {String? counterId, String? cashierId}) async {
    final counters = await s.activeCounters();
    final cashiers = await s.activeCashiers();
    if (counterId != null && !counters.any((c) => c.id == counterId)) {
      final c = await s.counters.getById(counterId);
      if (c != null) counters.add(c);
    }
    if (cashierId != null && !cashiers.any((c) => c.id == cashierId)) {
      final c = await s.cashiers.getById(cashierId);
      if (c != null) cashiers.add(c);
    }
    return Lookups(counters, cashiers);
  }

  /// Cashiers whose usual counter is [counterId] first.
  List<Cashier> cashiersFor(String? counterId) => [
    ...cashiers.where((c) => c.counterId == counterId),
    ...cashiers.where((c) => c.counterId != counterId),
  ];
}

Widget counterDropdown(Lookups l, String? value, ValueChanged<String?> onChanged, {bool allowGeneral = false}) =>
    DropdownButtonFormField<String?>(
      isExpanded: true,
      key: ValueKey('counter-$value'),
      initialValue: value,
      decoration: const InputDecoration(labelText: 'Counter', prefixIcon: Icon(Icons.storefront)),
      items: [
        if (allowGeneral) const DropdownMenuItem(value: null, child: Text('General (not from a counter)')),
        for (final c in l.counters) DropdownMenuItem(value: c.id, child: Text(c.name)),
      ],
      onChanged: onChanged,
      validator: (v) => (!allowGeneral && v == null) ? 'Select a counter' : null,
    );

Widget cashierDropdown(
  Lookups l,
  String? counterId,
  String? value,
  ValueChanged<String?> onChanged, {
  bool optional = false,
}) => DropdownButtonFormField<String?>(
  key: ValueKey('cashier-$counterId-$value'),
  initialValue: value,
  isExpanded: true,
  decoration: const InputDecoration(labelText: 'Cashier', prefixIcon: Icon(Icons.person)),
  items: [
    if (optional) const DropdownMenuItem(value: null, child: Text('— Not a specific cashier —')),
    for (final c in l.cashiersFor(counterId))
      DropdownMenuItem(
        value: c.id,
        child: Text(
          c.counterId == counterId || c.counterId == null
              ? c.name
              : '${c.name} (${l.counters.where((x) => x.id == c.counterId).map((x) => x.name).firstOrNull ?? ''})',
        ),
      ),
  ],
  onChanged: onChanged,
  validator: (v) => (!optional && v == null) ? 'Select a cashier' : null,
);

Widget noCashiersHint(BuildContext context, Lookups l) => l.cashiers.isNotEmpty
    ? const SizedBox.shrink()
    : Card(
        color: Colors.orange.shade50,
        child: const Padding(
          padding: EdgeInsets.all(12),
          child: Text('No cashiers yet. Add cashiers from More → Counters & Cashiers.'),
        ),
      );

/// Saves and pops, reporting errors.
Future<void> saveEntity<T extends Entity>(
  BuildContext context,
  Repository<T> repo,
  T item,
  void Function(bool) setSaving,
) async {
  setSaving(true);
  try {
    await repo.save(item, context.read<AuthService>().actor);
    if (context.mounted) {
      showSnack(context, 'Saved');
      Navigator.pop(context, true);
    }
  } catch (e) {
    if (context.mounted) showSnack(context, 'Could not save: $e', error: true);
  } finally {
    setSaving(false);
  }
}

Future<void> deleteEntity<T extends Entity>(BuildContext context, Repository<T> repo, T item) async {
  final ok = await confirm(
    context,
    'Delete entry?',
    'This entry will be removed from all totals. The deletion is recorded in the audit log.',
    ok: 'Delete',
    danger: true,
  );
  if (!ok || !context.mounted) return;
  await repo.softDelete(item, context.read<AuthService>().actor);
  if (context.mounted) {
    showSnack(context, 'Deleted');
    Navigator.pop(context, true);
  }
}
