import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/date_range.dart';
import '../../core/security.dart';
import '../../core/theme.dart';
import '../../services/auth_service.dart';
import '../../services/biometric_service.dart';
import '../../sync/sync_service.dart';
import '../widgets/common.dart';

class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key});

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  bool? _available;
  String? _linkedId;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final bio = context.read<BiometricService>();
    final available = await bio.isAvailable();
    final linked = await bio.linkedUserId();
    if (mounted) {
      setState(() {
        _available = available;
        _linkedId = linked;
      });
    }
  }

  Future<void> _toggle(bool enable) async {
    final bio = context.read<BiometricService>();
    final user = context.read<AuthService>().currentUser!;
    if (enable) {
      final ok = await bio.authenticate('Confirm your fingerprint to enable fingerprint login');
      if (!ok) {
        if (mounted) showSnack(context, 'Fingerprint not confirmed', error: true);
        return;
      }
      await bio.link(user.id);
    } else {
      await bio.unlink();
    }
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().currentUser!;
    final linkedToMe = _linkedId == user.id;
    return Scaffold(
      appBar: AppBar(title: const Text('Security')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionCard(
            title: 'Fingerprint Login',
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (_available == null)
                const LinearProgressIndicator()
              else if (_available == false)
                const Text('No fingerprint is set up on this phone, or the phone does not support it. '
                    'Add a fingerprint in the phone Settings first.')
              else ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.fingerprint, color: AppColors.orange, size: 32),
                  title: const Text('Use fingerprint to log in'),
                  subtitle: Text(linkedToMe
                      ? 'Enabled for ${user.username} on this phone'
                      : (_linkedId != null ? 'Currently linked to another user' : 'Disabled')),
                  value: linkedToMe,
                  onChanged: _toggle,
                ),
                Text('Only one account can use fingerprint on a phone. Any fingerprint registered on this phone '
                    'will be able to open this account, so only enable it on your own phone.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
              ],
            ]),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Password',
            child: FilledButton.icon(
              onPressed: () => _changePassword(context),
              icon: const Icon(Icons.password),
              label: const Text('Change Password'),
            ),
          ),
          const SizedBox(height: 16),
          const SectionCard(
            title: 'Protection',
            child: Text('• Passwords are stored as salted PBKDF2 hashes.\n'
                '• 5 wrong passwords lock the account for 5 minutes.\n'
                '• The app logs out after 5 minutes in the background.\n'
                '• Every add, edit and delete is recorded in the audit log.\n'
                '• Deleted entries are kept (hidden) for audit.'),
          ),
        ],
      ),
    );
  }

  Future<void> _changePassword(BuildContext context) async {
    final oldPw = TextEditingController();
    final newPw = TextEditingController();
    final key = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change Password'),
        content: Form(
          key: key,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
                controller: oldPw,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Current password')),
            const SizedBox(height: 12),
            TextFormField(
              controller: newPw,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'New password'),
              validator: PasswordHasher.validateStrength,
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
              onPressed: () {
                if (key.currentState!.validate()) Navigator.pop(ctx, true);
              },
              child: const Text('Change')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await context.read<AuthService>().changePassword(oldPw.text, newPw.text);
      if (context.mounted) showSnack(context, 'Password changed');
    } on AuthException catch (e) {
      if (context.mounted) showSnack(context, e.message, error: true);
    }
  }
}

class SyncScreen extends StatelessWidget {
  const SyncScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final sync = context.read<SyncService>();
    return Scaffold(
      appBar: AppBar(title: const Text('Online Sync')),
      body: Reloader<(int, DateTime?)>(
        load: () async => (await sync.pendingCount(), await sync.lastSync()),
        builder: (context, d) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SectionCard(
              title: 'Status',
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(sync.api.isConfigured ? Icons.cloud_done : Icons.cloud_off,
                      color: sync.api.isConfigured ? AppColors.success : Colors.grey),
                  const SizedBox(width: 8),
                  Text(sync.api.isConfigured ? 'Server connected' : 'Offline mode – no server yet',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 12),
                Text('Records waiting to sync: ${d.$1}'),
                Text('Last sync: ${d.$2 == null ? 'never' : displayDateTime(d.$2!)}'),
              ]),
            ),
            const SizedBox(height: 16),
            const SectionCard(
              title: 'How online sync will work',
              child: Text(
                'The app is offline-first: everything is saved on the phone instantly. Every record already has '
                'a unique ID, a last-changed time and a "waiting to sync" flag. When your server is ready it only '
                'needs to be connected in the app – your existing data will upload automatically and several '
                'phones can then share the same data.',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: sync.api.isConfigured
                  ? () async {
                      try {
                        final r = await sync.syncNow();
                        if (context.mounted) showSnack(context, 'Uploaded ${r.pushed}, downloaded ${r.pulled}');
                      } catch (e) {
                        if (context.mounted) showSnack(context, 'Sync failed: $e', error: true);
                      }
                    }
                  : null,
              icon: const Icon(Icons.sync),
              label: const Text('Sync Now'),
            ),
          ],
        ),
      ),
    );
  }
}

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('About')),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Image.asset('assets/images/logo.png', height: 80),
            const SizedBox(height: 24),
            const Text('Alfa Mart Cash Flow',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.navy)),
            const SizedBox(height: 4),
            const Text('Version 1.0.0', textAlign: TextAlign.center),
            const SizedBox(height: 24),
            const Text(
              'Daily accounts for Alfa Mart: counter and cashier sales by payment method (Cash, POS Machine, '
              'Online Banking, JazzCash), purchases, cash given to purchasers, expenses, cash reconciliation, '
              'dashboard and linked Excel export.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
}
