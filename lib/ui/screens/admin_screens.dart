import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/date_range.dart';
import '../../core/theme.dart';
import '../../data/models/audit_entry.dart';
import '../../services/app_services.dart';
import '../../services/auth_service.dart';
import '../../services/backup_service.dart';
import '../widgets/common.dart';

class AuditLogScreen extends StatefulWidget {
  const AuditLogScreen({super.key});

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  int _limit = 200;

  @override
  Widget build(BuildContext context) {
    final db = context.read<AppServices>().database;
    return Scaffold(
      appBar: AppBar(title: const Text('Audit Log')),
      body: Reloader<List<AuditEntry>>(
        reloadKey: _limit,
        load: () async =>
            (await db.db.query('audit_log', orderBy: 'ts DESC', limit: _limit)).map(AuditEntry.fromMap).toList(),
        builder: (context, entries) {
          if (entries.isEmpty) return const EmptyState(icon: Icons.history, message: 'No activity yet');
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: entries.length + 1,
            itemBuilder: (context, i) {
              if (i == entries.length) {
                return entries.length < _limit
                    ? const SizedBox.shrink()
                    : TextButton(onPressed: () => setState(() => _limit += 200), child: const Text('Load more'));
              }
              final e = entries[i];
              final (icon, color) = switch (e.action) {
                'create' => (Icons.add_circle_outline, AppColors.success),
                'update' => (Icons.edit_outlined, AppColors.sales),
                'delete' => (Icons.delete_outline, AppColors.danger),
                _ => (Icons.login, AppColors.navy),
              };
              return Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: ExpansionTile(
                  leading: Icon(icon, color: color),
                  title: Text(e.summary, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  subtitle: Text('${e.action.toUpperCase()} · ${e.entity} · ${e.userName} · '
                      '${displayDateTime(e.timestamp)}', style: const TextStyle(fontSize: 11)),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (e.before != null) SelectableText('Before: ${e.before}', style: const TextStyle(fontSize: 11)),
                    if (e.after != null) SelectableText('After: ${e.after}', style: const TextStyle(fontSize: 11)),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _busy = false;

  Future<void> _backup() async {
    setState(() => _busy = true);
    try {
      final file = await context.read<BackupService>().createBackup();
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path)],
        subject: 'Alfa Mart backup',
        text: 'Alfa Mart Cash Flow backup ${p.basename(file.path)}',
      ));
    } catch (e) {
      if (mounted) showSnack(context, 'Backup failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final picked = await FilePicker.pickFile(dialogTitle: 'Choose Alfa Mart backup (.db)');
    if (picked == null || !mounted) return;
    final ok = await confirm(
      context,
      'Restore backup?',
      'ALL current data on this phone will be replaced by "${picked.name}". '
          'A safety copy of the current data is saved first. You will be logged out.',
      ok: 'Restore',
      danger: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final tmp = File(p.join((await getTemporaryDirectory()).path, 'picked_backup.db'));
      await tmp.writeAsBytes(await picked.xFile.readAsBytes(), flush: true);
      if (!mounted) return;
      final restored = await context.read<BackupService>().restore(tmp);
      if (!mounted) return;
      if (!restored) {
        showSnack(context, 'That file is not an Alfa Mart backup', error: true);
        return;
      }
      final auth = context.read<AuthService>();
      context.read<AppServices>().notifier.changed();
      Navigator.of(context).popUntil((r) => r.isFirst);
      await auth.init();
      await auth.logout(reason: 'restore');
    } catch (e) {
      if (mounted) showSnack(context, 'Restore failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Backup & Restore')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SectionCard(
            title: 'Why backup?',
            child: Text(
              'All data is stored offline on this phone. If the phone is lost, reset or damaged the data is gone. '
              'Make a backup every day and save it to Google Drive, email or WhatsApp.',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _backup,
            icon: const Icon(Icons.backup),
            label: const Text('Create Backup & Share'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 50),
              foregroundColor: AppColors.danger,
              side: const BorderSide(color: AppColors.danger),
            ),
            onPressed: _busy ? null : _restore,
            icon: const Icon(Icons.restore),
            label: const Text('Restore from Backup'),
          ),
          if (_busy) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
        ],
      ),
    );
  }
}
