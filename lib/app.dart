import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'data/app_database.dart';
import 'data/repositories/repository.dart';
import 'services/app_services.dart';
import 'services/auth_service.dart';
import 'services/backup_service.dart';
import 'services/biometric_service.dart';
import 'services/excel_export_service.dart';
import 'services/report_service.dart';
import 'sync/remote_api.dart';
import 'sync/sync_service.dart';
import 'ui/screens/home_shell.dart';
import 'ui/screens/login_screen.dart';
import 'ui/screens/setup_screen.dart';
import 'ui/screens/splash_screen.dart';

class AlfaMartApp extends StatefulWidget {
  const AlfaMartApp({super.key});

  @override
  State<AlfaMartApp> createState() => _AlfaMartAppState();
}

class _AlfaMartAppState extends State<AlfaMartApp> {
  late final Future<_Bootstrap> _boot = _bootstrap();

  Future<_Bootstrap> _bootstrap() async {
    final started = DateTime.now();
    final db = await AppDatabase.open();
    final notifier = DataChangeNotifier();
    final services = AppServices(db, notifier);
    final auth = AuthService(services, BiometricService());
    await auth.init();
    // Keep the brand splash visible briefly.
    final elapsed = DateTime.now().difference(started);
    if (elapsed < const Duration(milliseconds: 1200)) {
      await Future.delayed(const Duration(milliseconds: 1200) - elapsed);
    }
    return _Bootstrap(services, auth);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_Bootstrap>(
      future: _boot,
      builder: (context, snap) {
        if (!snap.hasData) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildTheme(),
            home: SplashScreen(error: snap.error?.toString()),
          );
        }
        final b = snap.data!;
        return MultiProvider(
          providers: [
            Provider.value(value: b.services),
            ChangeNotifierProvider.value(value: b.services.notifier),
            ChangeNotifierProvider.value(value: b.auth),
            Provider.value(value: b.auth.biometrics),
            Provider(create: (_) => ReportService(b.services)),
            Provider(create: (_) => ExcelExportService()),
            Provider(create: (_) => BackupService(b.services.database)),
            // Swap OfflineRemoteApi for a real implementation once a server exists.
            Provider(create: (_) => SyncService(b.services.database, OfflineRemoteApi())),
          ],
          child: MaterialApp(
            title: 'Alfa Mart Cash Flow',
            debugShowCheckedModeBanner: false,
            theme: buildTheme(),
            home: const _AuthGate(),
          ),
        );
      },
    );
  }
}

class _Bootstrap {
  _Bootstrap(this.services, this.auth);
  final AppServices services;
  final AuthService auth;
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    if (auth.hasUsers == false) return const SetupScreen();
    if (!auth.isLoggedIn) return const LoginScreen();
    return HomeShell(key: ValueKey(auth.currentUser!.id));
  }
}
