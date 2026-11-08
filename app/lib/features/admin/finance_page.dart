import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../shared/app_sheet.dart';
import '../../shared/error_box.dart';
import '../../shared/notice.dart';
import '../auth/auth_models.dart';
import 'admin_models.dart';
import 'admin_providers.dart';
import 'admin_repository.dart';

const _suggestedAmounts = [25000, 50000, 75000];

class FinancePage extends ConsumerStatefulWidget {
  const FinancePage({super.key});

  @override
  ConsumerState<FinancePage> createState() => _FinancePageState();
}

class _FinancePageState extends ConsumerState<FinancePage> {
  final _amount = TextEditingController(text: '50000');
  final _selected = <String>{};
  String _query = '';
  bool _busy = false;
  String? _error;

  // Kept across retries of the same choice, so a lost reply can never credit twice.
  String _key = const Uuid().v4();

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _changed(void Function() change) {
    setState(() {
      change();
      _error = null;
      _key = const Uuid().v4();
    });
  }

  int get _amountValue => int.tryParse(_amount.text) ?? 0;

  Future<void> _confirm() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final count = _selected.length;
    final amount = _amountValue;
    try {
      await ref.read(adminRepositoryProvider).topUp(_selected.toList(), amount, _key);
      refreshAdminData(ref);
      if (!mounted) return;
      setState(() {
        _selected.clear();
        _key = const Uuid().v4();
      });
      await showNotice(context, kind: NoticeKind.done, title: 'تم الشحن', text: '$count موظف بـ ${points(amount)} لكل واحد');
    } on AdminFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final users = ref.watch(usersProvider);
    final value = users.valueOrNull;
    if (value == null) {
      return LoadingOrError(error: users.error, onRetry: () => ref.invalidate(usersProvider));
    }
    final employees = value.where((user) => user.role == UserRole.employee && user.isActive).toList();
    final shown = employees.where((user) => user.matches(_query)).toList();
    final allShownSelected = shown.isNotEmpty && shown.every((user) => _selected.contains(user.id));
    final searching = _query.trim().isNotEmpty;
    final amount = _amountValue;
    final canTopUp = amount > 0 && _selected.isNotEmpty;
    final ledger = ref.watch(ledgerProvider).valueOrNull ?? const <LedgerLine>[];

    return RefreshIndicator(
      onRefresh: () async {
        refreshAdminData(ref);
        await ref.read(usersProvider.future);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          Text('شحن الرصيد', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 28)),
          const SizedBox(height: 12),
          TextField(
            key: const Key('wallet-search'),
            decoration: const InputDecoration(labelText: 'ابحث عن موظف', hintText: 'الاسم أو اسم المستخدم'),
            style: const TextStyle(fontSize: 18),
            onChanged: (text) => setState(() => _query = text),
          ),
          const SizedBox(height: 12),
          if (shown.isEmpty)
            Text(employees.isEmpty ? 'لا يوجد موظفون بعد.' : 'لا يوجد موظف بهذا الاسم.', style: const TextStyle(fontSize: 18))
          else
            OutlinedButton(
              key: const Key('select-all'),
              onPressed: () => _changed(() {
                final ids = shown.map((user) => user.id);
                if (allShownSelected) {
                  _selected.removeAll(ids);
                } else {
                  _selected.addAll(ids);
                }
              }),
              child: Text(searching
                  ? (allShownSelected ? 'إلغاء تحديد النتائج' : 'اختر كل النتائج')
                  : (allShownSelected ? 'إلغاء تحديد الجميع' : 'اختر الجميع')),
            ),
          const SizedBox(height: 12),
          for (final user in shown) ...[
            ChoiceBox(
              key: Key('wallet-${user.username}'),
              label: user.fullName,
              trailing: points(user.available),
              selected: _selected.contains(user.id),
              onTap: () => _changed(() {
                if (!_selected.remove(user.id)) _selected.add(user.id);
              }),
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 4),
          const Text('النقاط لكل موظف', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final suggestion in _suggestedAmounts)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceBox(
                      key: Key('amount-$suggestion'),
                      label: money(suggestion),
                      selected: amount == suggestion,
                      center: true,
                      onTap: () => _changed(() => _amount.text = '$suggestion'),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            key: const Key('amount-field'),
            controller: _amount,
            decoration: const InputDecoration(labelText: 'أو اكتب عدداً آخر'),
            style: const TextStyle(fontSize: 22),
            textDirection: TextDirection.ltr,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(9)],
            onChanged: (_) => _changed(() {}),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.line),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              canTopUp
                  ? 'سيُشحن ${_selected.length} موظف بـ ${points(amount)} لكل واحد. المجموع ${points(amount * _selected.length)}.'
                  : 'اختر موظفاً واحداً على الأقل واكتب عدد النقاط.',
              style: const TextStyle(fontSize: 18),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            ErrorBox(_error!),
          ],
          if (canTopUp) ...[
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('topup-confirm'),
              onPressed: _busy ? null : _confirm,
              child: Text(_busy ? 'جارٍ الشحن...' : 'تأكيد الشحن'),
            ),
          ],
          const SizedBox(height: 18),
          const Text('السجل المالي', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          if (ledger.isEmpty) const Text('لا توجد عمليات شحن بعد.', style: TextStyle(fontSize: 18, color: AppColors.inkMuted)),
          for (final line in ledger) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border.all(color: AppColors.line),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(line.text, style: const TextStyle(fontSize: 17)),
                  Text(shortDate(line.createdAt), style: const TextStyle(fontSize: 16, color: AppColors.inkMuted)),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}
