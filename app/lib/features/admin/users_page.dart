import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../shared/app_sheet.dart';
import '../../shared/notice.dart';
import 'admin_models.dart';
import 'admin_providers.dart';
import 'admin_repository.dart';
import 'user_sheets.dart';

class UsersPage extends ConsumerStatefulWidget {
  const UsersPage({super.key});

  @override
  ConsumerState<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends ConsumerState<UsersPage> {
  String _query = '';

  /// Runs a server action behind a spinner, and reports a failure as a notice.
  Future<T?> _withProgress<T>(Future<T> Function() action) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(canPop: false, child: Center(child: CircularProgressIndicator())),
    );
    try {
      final result = await action();
      navigator.pop();
      return result;
    } on AdminFailure catch (failure) {
      navigator.pop();
      if (navigator.mounted) {
        await showNotice(navigator.context, kind: NoticeKind.warning, title: 'لم تتم العملية', text: failure.message);
      }
      return null;
    }
  }

  Future<bool> _confirm({required String title, required String text, required String yes}) async {
    final answer = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(text, style: const TextStyle(fontSize: 18)),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('لا')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text(yes)),
        ],
      ),
    );
    return answer == true;
  }

  Future<void> _reset(AdminUser user) async {
    final confirmed = await _confirm(
      title: 'تصفير كلمة المرور؟',
      text: 'سيخرج ${user.fullName} من التطبيق، وتُعطى له كلمة مؤقتة جديدة.',
      yes: 'نعم، صفّرها',
    );
    if (!confirmed || !mounted) return;
    final repository = ref.read(adminRepositoryProvider);
    final password = await _withProgress(() => repository.resetPassword(user.id));
    if (password == null || !mounted) return;
    refreshAdminData(ref);
    await showPasswordSheet(context, NewCredentials(username: user.username, password: password));
  }

  Future<void> _toggle(AdminUser user) async {
    if (user.isActive) {
      final confirmed = await _confirm(
        title: 'تعطيل الحساب؟',
        text: 'لن يستطيع ${user.fullName} الدخول. يبقى رصيده وسجله وحجوزاته كما هي.',
        yes: 'نعم، عطّله',
      );
      if (!confirmed || !mounted) return;
    }
    final repository = ref.read(adminRepositoryProvider);
    final done = await _withProgress(() async {
      await repository.setActive(user.id, !user.isActive);
      return true;
    });
    if (done != true || !mounted) return;
    refreshAdminData(ref);
    await showNotice(
      context,
      kind: NoticeKind.done,
      title: user.isActive ? 'عُطّل الحساب' : 'فُعّل الحساب',
      text: user.isActive ? 'بقي رصيده وسجله محفوظين.' : user.fullName,
    );
  }

  @override
  Widget build(BuildContext context) {
    final users = ref.watch(usersProvider);
    final value = users.valueOrNull;
    if (value == null) {
      return LoadingOrError(error: users.error, onRetry: () => ref.invalidate(usersProvider));
    }
    final shown = value.where((user) => user.matches(_query)).toList();
    final selfId = ref.read(adminRepositoryProvider).currentUserId;

    return RefreshIndicator(
      onRefresh: () async {
        refreshAdminData(ref);
        await ref.read(usersProvider.future);
      },
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        itemCount: shown.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('المستخدمون', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 28)),
                const SizedBox(height: 12),
                FilledButton(
                  key: const Key('add-user'),
                  onPressed: () => addUser(context),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(60), textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                  child: const Text('إضافة مستخدم'),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('user-search'),
                  decoration: const InputDecoration(labelText: 'ابحث عن مستخدم', hintText: 'الاسم أو اسم المستخدم'),
                  style: const TextStyle(fontSize: 18),
                  onChanged: (text) => setState(() => _query = text),
                ),
                const SizedBox(height: 12),
                if (shown.isEmpty)
                  const Text('لا يوجد مستخدم بهذا الاسم.', style: TextStyle(fontSize: 18)),
              ],
            );
          }
          final user = shown[index - 1];
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _UserCard(
              user: user,
              isSelf: user.id == selfId,
              onEdit: () => editUser(context, user),
              onReset: () => _reset(user),
              onToggle: () => _toggle(user),
            ),
          );
        },
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({required this.user, required this.isSelf, required this.onEdit, required this.onReset, required this.onToggle});

  final AdminUser user;
  final bool isSelf;
  final VoidCallback onEdit;
  final VoidCallback onReset;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final toggleColor = user.isActive ? AppColors.danger : AppColors.primary;
    const smallText = TextStyle(fontSize: 16, fontWeight: FontWeight.w700);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(user.fullName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                decoration: BoxDecoration(
                  color: user.isActive ? AppColors.primarySoft : AppColors.closed,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  user.isActive ? 'فعّال' : 'معطّل',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: user.isActive ? AppColors.onPrimarySoft : AppColors.inkMuted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('${roleLabels[user.role]} · ${user.restaurantName ?? 'كل المطاعم'}', style: const TextStyle(fontSize: 17, color: AppColors.inkMuted)),
          Text(user.username, textDirection: TextDirection.ltr, textAlign: TextAlign.end, style: const TextStyle(fontSize: 17)),
          const SizedBox(height: 8),
          OutlinedButton(key: Key('edit-${user.username}'), onPressed: onEdit, child: const Text('تعديل البيانات والدور')),
          if (isSelf) ...[
            const SizedBox(height: 8),
            const Text('هذا حسابك.', style: TextStyle(fontSize: 17, color: AppColors.inkMuted)),
          ] else ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: Key('reset-${user.username}'),
                    onPressed: onReset,
                    style: OutlinedButton.styleFrom(textStyle: smallText, padding: const EdgeInsets.symmetric(horizontal: 6)),
                    child: const Text('تصفير كلمة المرور', textAlign: TextAlign.center),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    key: Key('toggle-${user.username}'),
                    onPressed: onToggle,
                    style: OutlinedButton.styleFrom(
                      textStyle: smallText,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      foregroundColor: toggleColor,
                      side: BorderSide(color: toggleColor, width: 2),
                    ),
                    child: Text(user.isActive ? 'تعطيل الحساب' : 'تفعيل الحساب', textAlign: TextAlign.center),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
