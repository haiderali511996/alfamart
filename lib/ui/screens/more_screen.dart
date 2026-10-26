import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../services/auth_service.dart';
import '../widgets/common.dart';
import 'admin_screens.dart';
import 'export_screen.dart';
import 'people_screens.dart';
import 'settings_screens.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final user = auth.currentUser!;
    void open(Widget w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w));
    Widget item(IconData i, String t, String s, Widget page, {bool adminOnly = false}) {
      final locked = adminOnly && !auth.isAdmin;
      return ListTile(
        leading: Icon(i, color: locked ? Colors.grey : AppColors.navy),
        title: Text(t, style: TextStyle(fontWeight: FontWeight.w600, color: locked ? Colors.grey : null)),
        subtitle: Text(locked ? 'Admin only' : s),
        trailing: Icon(locked ? Icons.lock_outline : Icons.chevron_right),
        onTap: locked ? () => showSnack(context, 'Only an admin can open this') : () => open(page),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: AppColors.orange,
                child: Text(user.fullName.isEmpty ? '?' : user.fullName[0].toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
              ),
              title: Text(user.fullName, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('@${user.username} · ${user.role.label}'),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(children: [
              item(Icons.storefront, 'Counters & Cashiers', 'Add cashiers, set their counter', const PeopleScreen()),
              item(Icons.table_view, 'Export to Excel', 'Full linked workbook for any period', const ExportScreen(),
                  adminOnly: true),
              item(Icons.manage_accounts, 'Users', 'Admins and managers who can log in', const UsersScreen(),
                  adminOnly: true),
              item(Icons.history, 'Audit Log', 'Who changed what, and when', const AuditLogScreen(), adminOnly: true),
              item(Icons.backup, 'Backup & Restore', 'Keep your offline data safe', const BackupScreen(),
                  adminOnly: true),
            ]),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(children: [
              item(Icons.fingerprint, 'Security', 'Fingerprint login, change password', const SecurityScreen()),
              item(Icons.cloud_sync, 'Online Sync', 'Server connection (coming soon)', const SyncScreen()),
              item(Icons.info_outline, 'About', 'Alfa Mart Cash Flow', const AboutScreen()),
            ]),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.logout, color: AppColors.danger),
              title: const Text('Logout', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700)),
              onTap: () async {
                if (await confirm(context, 'Logout?', 'You will need to log in again.', ok: 'Logout')) {
                  if (context.mounted) await context.read<AuthService>().logout();
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
