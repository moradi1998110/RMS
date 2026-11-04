import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../shared/error_box.dart';
import '../../shared/notice.dart';
import 'auth_controller.dart';
import 'auth_models.dart';

class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final problem = newPasswordProblem(_password.text, _confirmation.text);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final navigator = Navigator.of(context, rootNavigator: true);
    try {
      await ref.read(authControllerProvider.notifier).changePassword(_password.text);
      if (navigator.mounted) {
        showNotice(navigator.context, kind: NoticeKind.done, title: 'تم تغيير كلمة المرور');
      }
    } on AuthFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 32),
          children: [
            Text('اختر كلمة مرور جديدة', style: textTheme.headlineMedium),
            const SizedBox(height: 12),
            Text('هذه الخطوة مرة واحدة، حتى تكون كلمة المرور معروفة لك وحدك.', style: textTheme.bodyLarge),
            const SizedBox(height: 28),
            TextField(
              key: const Key('password-new'),
              controller: _password,
              decoration: const InputDecoration(labelText: 'كلمة المرور الجديدة'),
              style: const TextStyle(fontSize: 20),
              textDirection: TextDirection.ltr,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.newPassword],
            ),
            const SizedBox(height: 18),
            TextField(
              key: const Key('password-confirm'),
              controller: _confirmation,
              decoration: const InputDecoration(labelText: 'أعد كتابتها للتأكيد'),
              style: const TextStyle(fontSize: 20),
              textDirection: TextDirection.ltr,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              ErrorBox(_error!),
            ],
            const SizedBox(height: 24),
            FilledButton(
              key: const Key('password-submit'),
              onPressed: _busy ? null : _submit,
              child: Text(_busy ? 'جارٍ الحفظ...' : 'حفظ'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy ? null : () => ref.read(authControllerProvider.notifier).signOut(),
              child: const Text('تسجيل الخروج'),
            ),
          ],
        ),
      ),
    );
  }
}
