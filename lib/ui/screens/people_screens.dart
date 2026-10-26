import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/date_range.dart';
import '../../core/enums.dart';
import '../../core/security.dart';
import '../../core/theme.dart';
import '../../data/models/app_user.dart';
import '../../data/models/cashier.dart';
import '../../data/models/counter.dart';
import '../../services/app_services.dart';
import '../../services/auth_service.dart';
import '../widgets/common.dart';

/// Counters (admin edits) and cashiers (admin & manager).
class PeopleScreen extends StatelessWidget {
  const PeopleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppServices>();
    final auth = context.watch<AuthService>();
    return Scaffold(
      appBar: AppBar(title: const Text('Counters & Cashiers')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editCashier(context, null),
        icon: const Icon(Icons.person_add),
        label: const Text('Add Cashier'),
      ),
      body: Reloader<(List<Counter>, List<Cashier>)>(
        load: () async => (
          await s.counters.query(orderBy: 'sort_order, name'),
          await s.cashiers.query(orderBy: 'is_active DESC, name'),
        ),
        builder: (context, data) {
          final (counters, cashiers) = data;
          String counterName(String? id) => counters.where((c) => c.id == id).firstOrNull?.name ?? 'Any counter';
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              SectionCard(
                title: 'Counters',
                trailing: auth.isAdmin
                    ? TextButton.icon(
                        onPressed: () => _editCounter(context, null, counters.length + 1),
                        icon: const Icon(Icons.add),
                        label: const Text('Add'))
                    : null,
                child: Column(children: [
                  for (final c in counters)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.storefront, color: c.isActive ? AppColors.navy : Colors.grey),
                      title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                          '${cashiers.where((x) => x.counterId == c.id && x.isActive).length} cashier(s)'
                          '${c.isActive ? '' : ' · inactive'}'),
                      trailing: auth.isAdmin ? const Icon(Icons.edit_outlined) : null,
                      onTap: auth.isAdmin ? () => _editCounter(context, c, c.sortOrder) : null,
                    ),
                ]),
              ),
              const SizedBox(height: 16),
              SectionCard(
                title: 'Cashiers',
                child: cashiers.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('No cashiers yet. Tap "Add Cashier".'),
                      )
                    : Column(children: [
                        for (final c in cashiers)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              backgroundColor: (c.isActive ? AppColors.orange : Colors.grey).withValues(alpha: 0.15),
                              child: Text(c.name[0].toUpperCase(),
                                  style: TextStyle(
                                      color: c.isActive ? AppColors.orange : Colors.grey,
                                      fontWeight: FontWeight.w800)),
                            ),
                            title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text('${counterName(c.counterId)}'
                                '${c.phone.isNotEmpty ? ' · ${c.phone}' : ''}${c.isActive ? '' : ' · inactive'}'),
                            trailing: const Icon(Icons.edit_outlined),
                            onTap: () => _editCashier(context, c),
                          ),
                      ]),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _editCounter(BuildContext context, Counter? c, int order) async {
    final name = TextEditingController(text: c?.name ?? 'Counter $order');
    var active = c?.isActive ?? true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(c == null ? 'Add Counter' : 'Edit Counter'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Counter name')),
            if (c != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active'),
                value: active,
                onChanged: (v) => setState(() => active = v),
              ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok != true || name.text.trim().isEmpty || !context.mounted) return;
    await context.read<AppServices>().counters.save(
          Counter(id: c?.id ?? const Uuid().v4(), name: name.text.trim(), sortOrder: order, isActive: active),
          context.read<AuthService>().actor,
        );
  }

  Future<void> _editCashier(BuildContext context, Cashier? c) async {
    final s = context.read<AppServices>();
    final counters = await s.activeCounters();
    if (!context.mounted) return;
    final name = TextEditingController(text: c?.name ?? '');
    final phone = TextEditingController(text: c?.phone ?? '');
    String? counterId = c?.counterId ?? counters.firstOrNull?.id;
    var active = c?.isActive ?? true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(c == null ? 'Add Cashier' : 'Edit Cashier'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Cashier name')),
              const SizedBox(height: 12),
              TextField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Phone (optional)')),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                isExpanded: true,
                initialValue: counterId,
                decoration: const InputDecoration(labelText: 'Usual counter'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Any counter')),
                  for (final x in counters) DropdownMenuItem(value: x.id, child: Text(x.name)),
                ],
                onChanged: (v) => setState(() => counterId = v),
              ),
              if (c != null)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active (still working)'),
                  value: active,
                  onChanged: (v) => setState(() => active = v),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    if (name.text.trim().isEmpty) {
      showSnack(context, 'Name is required', error: true);
      return;
    }
    await s.cashiers.save(
      Cashier(
        id: c?.id ?? const Uuid().v4(),
        name: name.text.trim(),
        phone: phone.text.trim(),
        counterId: counterId,
        isActive: active,
      ),
      context.read<AuthService>().actor,
    );
  }
}

/// Admin: manage who can log in.
class UsersScreen extends StatelessWidget {
  const UsersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppServices>();
    final me = context.watch<AuthService>().currentUser!;
    return Scaffold(
      appBar: AppBar(title: const Text('Users')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addUser(context),
        icon: const Icon(Icons.person_add),
        label: const Text('Add User'),
      ),
      body: Reloader<List<AppUser>>(
        load: () => s.users.query(orderBy: 'role, username'),
        builder: (context, users) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            for (final u in users)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  child: ListTile(
                    leading: Icon(u.isAdmin ? Icons.admin_panel_settings : Icons.manage_accounts,
                        color: u.isActive ? AppColors.navy : Colors.grey),
                    title: Text('${u.fullName}${u.id == me.id ? ' (you)' : ''}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('@${u.username} · ${u.role.label}${u.isActive ? '' : ' · disabled'}\n'
                        'Last login: ${u.lastLogin == null ? 'never' : displayDateTime(u.lastLogin!)}'),
                    isThreeLine: true,
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) => _action(context, u, v),
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'reset', child: Text('Reset password')),
                        PopupMenuItem(
                            value: 'role',
                            child: Text(u.isAdmin ? 'Make Manager' : 'Make Admin')),
                        PopupMenuItem(value: 'active', child: Text(u.isActive ? 'Disable login' : 'Enable login')),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _action(BuildContext context, AppUser u, String action) async {
    final auth = context.read<AuthService>();
    try {
      switch (action) {
        case 'reset':
          final pw = await _askPassword(context, 'New password for ${u.username}');
          if (pw != null) {
            await auth.setPassword(u, pw);
            if (context.mounted) showSnack(context, 'Password updated');
          }
        case 'role':
          await auth.updateUser(u.copyWith(role: u.isAdmin ? UserRole.manager : UserRole.admin));
        case 'active':
          await auth.updateUser(u.copyWith(isActive: !u.isActive));
      }
    } on AuthException catch (e) {
      if (context.mounted) showSnack(context, e.message, error: true);
    }
  }

  Future<String?> _askPassword(BuildContext context, String title) async {
    final c = TextEditingController();
    final key = GlobalKey<FormState>();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Form(
          key: key,
          child: TextFormField(
            controller: c,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Password'),
            validator: PasswordHasher.validateStrength,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () {
                if (key.currentState!.validate()) Navigator.pop(ctx, c.text);
              },
              child: const Text('Save')),
        ],
      ),
    );
  }

  Future<void> _addUser(BuildContext context) async {
    final name = TextEditingController();
    final user = TextEditingController();
    final pw = TextEditingController();
    var role = UserRole.manager;
    final key = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Add User'),
          content: SingleChildScrollView(
            child: Form(
              key: key,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextFormField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Full name'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: user,
                  decoration: const InputDecoration(labelText: 'Username'),
                  validator: (v) => (v == null || v.trim().length < 3) ? 'At least 3 characters' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: pw,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password'),
                  validator: PasswordHasher.validateStrength,
                ),
                const SizedBox(height: 12),
                SegmentedButton<UserRole>(
                  segments: const [
                    ButtonSegment(value: UserRole.manager, label: Text('Manager')),
                    ButtonSegment(value: UserRole.admin, label: Text('Admin')),
                  ],
                  selected: {role},
                  onSelectionChanged: (v) => setState(() => role = v.first),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
                onPressed: () {
                  if (key.currentState!.validate()) Navigator.pop(ctx, true);
                },
                child: const Text('Create')),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await context
          .read<AuthService>()
          .createUser(username: user.text, fullName: name.text, password: pw.text, role: role);
      if (context.mounted) showSnack(context, 'User created');
    } on AuthException catch (e) {
      if (context.mounted) showSnack(context, e.message, error: true);
    }
  }
}
