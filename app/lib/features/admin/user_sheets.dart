import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../shared/app_sheet.dart';
import '../../shared/error_box.dart';
import '../../shared/notice.dart';
import '../auth/auth_models.dart';
import 'admin_models.dart';
import 'admin_providers.dart';
import 'admin_repository.dart';

/// Adds a user and hands over the temporary password.
Future<void> addUser(BuildContext context) async {
  final credentials = await showAppSheet<NewCredentials>(context, builder: (_) => const UserFormSheet());
  if (credentials == null || !context.mounted) return;
  await showPasswordSheet(context, credentials);
}

Future<void> editUser(BuildContext context, AdminUser user) async {
  final saved = await showAppSheet<bool>(context, builder: (_) => UserFormSheet(user: user));
  if (saved != true || !context.mounted) return;
  await showNotice(context, kind: NoticeKind.done, title: 'حُفظت التعديلات', text: user.username);
}

Future<void> showPasswordSheet(BuildContext context, NewCredentials credentials) {
  return showAppSheet<void>(context, builder: (_) => _PasswordSheet(credentials: credentials));
}

/// Creates a user, or edits one when [user] is given.
class UserFormSheet extends ConsumerStatefulWidget {
  const UserFormSheet({super.key, this.user});

  final AdminUser? user;

  @override
  ConsumerState<UserFormSheet> createState() => _UserFormSheetState();
}

class _UserFormSheetState extends ConsumerState<UserFormSheet> {
  late final _name = TextEditingController(text: widget.user?.fullName);
  late final _username = TextEditingController(text: widget.user?.username);
  late final _department = TextEditingController(text: widget.user?.department);
  late UserRole _role = widget.user?.role ?? UserRole.employee;
  late String? _restaurantId = widget.user?.restaurantId;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _department.dispose();
    super.dispose();
  }

  Future<void> _save(List<Place> places) async {
    if (_busy) return;
    final problem = newUserProblem(fullName: _name.text, username: _username.text, role: _role, restaurantId: _restaurantId);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    final repository = ref.read(adminRepositoryProvider);
    final user = widget.user;
    try {
      if (user == null) {
        final credentials = await repository.createUser(
          fullName: _name.text,
          username: _username.text,
          department: _department.text,
          role: _role,
          restaurantId: _restaurantId,
        );
        refreshAdminData(ref);
        navigator.pop(credentials);
        return;
      }
      // A meal already booked belongs to the old restaurant, and to someone able to
      // collect it, so these two wait until the bookings are settled.
      if (_role != user.role || _restaurantId != user.restaurantId) {
        final live = await repository.liveBookingCount(user.id);
        if (live > 0) {
          if (mounted) {
            setState(() {
              _busy = false;
              _error = 'لهذا المستخدم حجوزات قائمة ($live). لا يمكن تغيير دوره أو مطعمه حتى تُستلم أو تُلغى.';
            });
          }
          return;
        }
      }
      await repository.updateUser(
        user.id,
        fullName: _name.text,
        department: _department.text,
        role: _role,
        place: places.where((place) => place.id == _restaurantId).firstOrNull,
      );
      refreshAdminData(ref);
      navigator.pop(true);
    } on AdminFailure catch (failure) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = failure.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final isSelf = user != null && user.id == ref.read(adminRepositoryProvider).currentUserId;
    final places = (ref.watch(placesProvider).valueOrNull ?? const <Place>[]).where((place) => place.isActive || place.id == _restaurantId).toList();
    final textTheme = Theme.of(context).textTheme;

    return PopScope(
      canPop: !_busy,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(user == null ? 'مستخدم جديد' : 'تعديل المستخدم', style: textTheme.titleLarge),
          const SizedBox(height: 16),
          TextField(
            key: const Key('user-name'),
            controller: _name,
            decoration: const InputDecoration(labelText: 'الاسم الكامل'),
            style: const TextStyle(fontSize: 19),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 14),
          TextField(
            key: const Key('user-username'),
            controller: _username,
            enabled: user == null,
            decoration: const InputDecoration(labelText: 'اسم المستخدم (إنجليزي)'),
            style: const TextStyle(fontSize: 19),
            textDirection: TextDirection.ltr,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 14),
          TextField(
            key: const Key('user-department'),
            controller: _department,
            decoration: const InputDecoration(labelText: 'القسم (اختياري)'),
            style: const TextStyle(fontSize: 19),
            textInputAction: TextInputAction.done,
          ),
          if (!isSelf) ...[
            const SizedBox(height: 14),
            const Text('الدور', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
            const SizedBox(height: 6),
            Row(
              children: [
                for (final role in const [UserRole.employee, UserRole.manager, UserRole.admin])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: ChoiceBox(
                        key: Key('role-${role.name}'),
                        label: roleLabels[role]!,
                        selected: _role == role,
                        center: true,
                        onTap: () => setState(() => _role = role),
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (_role != UserRole.admin) ...[
            const SizedBox(height: 14),
            const Text('المطعم', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
            const SizedBox(height: 6),
            if (places.isEmpty) const Text('لا يوجد مطعم بعد. أضف موقعاً ومطعماً من تبويب المطاعم أولاً.', style: TextStyle(fontSize: 17, color: AppColors.inkMuted)),
            for (final place in places)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: ChoiceBox(
                  key: Key('place-${place.id}'),
                  label: place.name,
                  selected: _restaurantId == place.id,
                  onTap: () => setState(() => _restaurantId = place.id),
                ),
              ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            ErrorBox(_error!),
          ],
          const SizedBox(height: 14),
          FilledButton(
            key: const Key('user-save'),
            onPressed: _busy ? null : () => _save(places),
            child: Text(_busy ? 'جارٍ الحفظ...' : (user == null ? 'إنشاء الحساب' : 'حفظ')),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: const Text('رجوع'),
          ),
        ],
      ),
    );
  }
}

class _PasswordSheet extends StatelessWidget {
  const _PasswordSheet({required this.credentials});

  final NewCredentials credentials;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('سلّم هذه البيانات لصاحب الحساب', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Text.rich(
            TextSpan(children: [
              const TextSpan(text: 'اسم المستخدم: '),
              TextSpan(text: credentials.username, style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
            style: const TextStyle(fontSize: 18),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.ground, borderRadius: BorderRadius.circular(14)),
            child: SelectableText(
              credentials.password,
              key: const Key('temporary-password'),
              textAlign: TextAlign.center,
              textDirection: TextDirection.ltr,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: 2),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: credentials.password));
              HapticFeedback.mediumImpact();
            },
            child: const Text('انسخ الكلمة'),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: AppColors.warningSoft, borderRadius: BorderRadius.circular(12)),
            child: const Text(
              'تظهر هذه الكلمة مرة واحدة فقط، وسيُطلب منه تغييرها عند أول دخول.',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w500, color: AppColors.onWarningSoft),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('password-done'),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('تم'),
          ),
        ],
      ),
    );
  }
}
