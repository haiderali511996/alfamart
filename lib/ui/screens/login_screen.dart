import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../services/auth_service.dart';
import '../../services/biometric_service.dart';
import '../widgets/common.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _user = TextEditingController();
  final _pw = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  bool _bioReady = false;

  @override
  void initState() {
    super.initState();
    _checkBiometric();
  }

  Future<void> _checkBiometric() async {
    final bio = context.read<BiometricService>();
    final linked = await bio.linkedUserId();
    final available = await bio.isAvailable();
    if (!mounted) return;
    setState(() => _bioReady = linked != null && available);
    if (_bioReady) _bioLogin();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on AuthException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _login() async {
    if (!_form.currentState!.validate()) return;
    final auth = context.read<AuthService>();
    await _run(() => auth.login(_user.text, _pw.text));
  }

  Future<void> _bioLogin() async {
    final auth = context.read<AuthService>();
    await _run(auth.loginWithBiometrics);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navyDark,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Image.asset('assets/images/splash_logo.png', height: 150),
                const SizedBox(height: 8),
                const Text('Cash Flow & Accounts',
                    style: TextStyle(color: Colors.white70, fontSize: 15, letterSpacing: 1)),
                const SizedBox(height: 28),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Form(
                      key: _form,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text('Admin / Manager Login',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.navy)),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _user,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(labelText: 'Username', prefixIcon: Icon(Icons.person)),
                            validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter username' : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _pw,
                            obscureText: _obscure,
                            onFieldSubmitted: (_) => _login(),
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: const Icon(Icons.lock),
                              suffixIcon: IconButton(
                                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                                onPressed: () => setState(() => _obscure = !_obscure),
                              ),
                            ),
                            validator: (v) => (v == null || v.isEmpty) ? 'Enter password' : null,
                          ),
                          const SizedBox(height: 20),
                          FilledButton(
                            onPressed: _busy ? null : _login,
                            child: _busy
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Text('Login'),
                          ),
                          if (_bioReady) ...[
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 50),
                                foregroundColor: AppColors.orange,
                                side: const BorderSide(color: AppColors.orange),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: _busy ? null : _bioLogin,
                              icon: const Icon(Icons.fingerprint, size: 28),
                              label: const Text('Login with Fingerprint'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Works fully offline · Data stays on this device',
                    style: TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
