import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../shared/error_box.dart';
import 'auth_controller.dart';
import 'auth_models.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _showPassword = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_username.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'اكتب اسم المستخدم وكلمة المرور.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).signIn(_username.text, _password.text);
    } on AuthFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 32),
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(20)),
                child: const Icon(Icons.restaurant, color: AppColors.surface, size: 38),
              ),
            ),
            const SizedBox(height: 20),
            Text('أهلاً بك في\nالمائدة', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 28),
            TextField(
              key: const Key('login-username'),
              controller: _username,
              decoration: const InputDecoration(labelText: 'اسم المستخدم'),
              style: const TextStyle(fontSize: 20),
              textDirection: TextDirection.ltr,
              keyboardType: TextInputType.visiblePassword,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.username],
            ),
            const SizedBox(height: 18),
            TextField(
              key: const Key('login-password'),
              controller: _password,
              decoration: InputDecoration(
                labelText: 'كلمة المرور',
                suffixIcon: TextButton(
                  onPressed: () => setState(() => _showPassword = !_showPassword),
                  child: Text(_showPassword ? 'إخفاء' : 'إظهار'),
                ),
              ),
              style: const TextStyle(fontSize: 20),
              textDirection: TextDirection.ltr,
              obscureText: !_showPassword,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.password],
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              ErrorBox(_error!),
            ],
            const SizedBox(height: 24),
            FilledButton(
              key: const Key('login-submit'),
              onPressed: _busy ? null : _submit,
              child: Text(_busy ? 'جارٍ الدخول...' : 'دخول'),
            ),
            const SizedBox(height: 16),
            Text(
              'نسيت كلمة المرور؟ راجع مسؤول النظام.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.inkMuted),
            ),
          ],
        ),
      ),
    );
  }
}
