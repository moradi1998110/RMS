import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/theme.dart';
import '../../shared/app_sheet.dart';
import '../../shared/error_box.dart';
import 'employee_models.dart';
import 'employee_providers.dart';
import 'employee_repository.dart';

Future<void> showDelegatesSheet(BuildContext context) {
  return showAppSheet<void>(context, builder: (_) => const DelegatesSheet());
}

/// The colleagues' round pictures followed by the delegation icon; opens the sheet.
class DelegatesButton extends ConsumerWidget {
  const DelegatesButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final delegates = ref.watch(delegatesProvider).valueOrNull ?? const <Delegate>[];
    final names = delegates.map((delegate) => delegate.fullName).join('، ');
    return Semantics(
      button: true,
      label: delegates.isEmpty ? 'خوّل زميلاً باستلام وجباتك' : 'يستلم وجباتك: $names',
      excludeSemantics: true,
      child: InkWell(
        key: const Key('delegates-open'),
        borderRadius: BorderRadius.circular(28),
        onTap: () => showDelegatesSheet(context),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (index, delegate) in delegates.take(3).indexed)
                Align(
                  widthFactor: index == 0 ? 1 : 0.7,
                  child: _Avatar(delegate: delegate, key: Key('delegate-avatar-${delegate.delegationId}')),
                ),
              if (delegates.length > 3)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 4),
                  child: Text('+${delegates.length - 3}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              const SizedBox(width: 6),
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primarySoft,
                  border: Border.all(color: AppColors.primary, width: 1.5),
                ),
                child: const Icon(Icons.person_add_alt_1_rounded, color: AppColors.onPrimarySoft, size: 26),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({super.key, required this.delegate});

  final Delegate delegate;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.refundSoft,
        border: Border.all(color: AppColors.surface, width: 2),
      ),
      child: Text(delegate.initials, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.onRefundSoft)),
    );
  }
}

/// Who can collect my meals: the list, withdrawing someone, and adding a colleague.
class DelegatesSheet extends ConsumerStatefulWidget {
  const DelegatesSheet({super.key});

  @override
  ConsumerState<DelegatesSheet> createState() => _DelegatesSheetState();
}

class _DelegatesSheetState extends ConsumerState<DelegatesSheet> {
  final _username = TextEditingController();
  Colleague? _found;
  String? _confirmingRemove;
  String? _error;
  String? _done;
  bool _busy = false;

  // Kept across retries of adding the same colleague.
  String _key = const Uuid().v4();

  @override
  void dispose() {
    _username.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function(EmployeeRepository repository) action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _done = null;
    });
    try {
      await action(ref.read(employeeRepositoryProvider));
    } on EmployeeFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _find() async {
    final username = _username.text.trim();
    if (username.isEmpty) {
      setState(() => _error = 'اكتب اسم المستخدم لزميلك.');
      return;
    }
    await _run((repository) async {
      final colleague = await repository.findColleague(username);
      if (!mounted) return;
      setState(() {
        _found = colleague;
        _key = const Uuid().v4();
        if (colleague == null) _error = EmployeeFailure.fromServer('colleague_not_found', const {}).message;
      });
    });
  }

  Future<void> _add(Colleague colleague) async {
    await _run((repository) async {
      await repository.addDelegate(colleague.username, _key);
      ref.invalidate(delegatesProvider);
      if (!mounted) return;
      setState(() {
        _found = null;
        _username.clear();
        _done = 'أصبح ${colleague.fullName} يستطيع استلام وجباتك.';
      });
    });
  }

  Future<void> _remove(Delegate delegate) async {
    await _run((repository) async {
      await repository.removeDelegate(delegate.delegationId);
      ref.invalidate(delegatesProvider);
      if (!mounted) return;
      setState(() {
        _confirmingRemove = null;
        _done = 'لم يعد ${delegate.fullName} يستطيع استلام وجباتك.';
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final delegates = ref.watch(delegatesProvider);
    final list = delegates.valueOrNull;
    final found = _found;
    return PopScope(
      canPop: !_busy,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('من يستلم وجباتي', style: textTheme.titleLarge),
          const SizedBox(height: 6),
          const Text(
            'يستطيع كل زميل تختاره أن يستلم أي وجبة لك حين يبدأ وقت استلامها. إذا استلمها أحدكم لا يستطيع غيره استلامها.',
            style: TextStyle(fontSize: 17, color: AppColors.inkMuted),
          ),
          const SizedBox(height: 14),
          if (list == null)
            delegates.hasError
                ? const Text('تعذّر عرض القائمة. تأكد من الإنترنت.', style: TextStyle(fontSize: 18))
                : const Center(child: CircularProgressIndicator())
          else if (list.isEmpty)
            const Text('لم تختر أحداً بعد.', key: Key('delegates-empty'), style: TextStyle(fontSize: 18))
          else
            for (final delegate in list) _row(delegate),
          const SizedBox(height: 16),
          if (list != null && list.length >= maxDelegates)
            const Text(
              'اخترت $maxDelegates زملاء، وهو الحد الأقصى. ألغِ أحدهم لتضيف غيره.',
              key: Key('delegates-full'),
              style: TextStyle(fontSize: 17, color: AppColors.inkMuted),
            )
          else if (found == null) ...[
            TextField(
              key: const Key('delegate-username'),
              controller: _username,
              enabled: !_busy,
              textDirection: TextDirection.ltr,
              autocorrect: false,
              style: const TextStyle(fontSize: 18),
              decoration: const InputDecoration(labelText: 'اسم المستخدم لزميلك'),
              onChanged: (_) => setState(() => _error = null),
              onSubmitted: (_) => _find(),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              key: const Key('delegate-find'),
              onPressed: _busy ? null : _find,
              icon: const Icon(Icons.search_rounded),
              label: const Text('ابحث'),
            ),
          ] else ...[
            FactBox(lines: [
              ('الزميل:', found.fullName),
              if (found.department != null && found.department!.isNotEmpty) ('القسم:', found.department!),
            ]),
            const SizedBox(height: 10),
            FilledButton(
              key: const Key('delegate-add'),
              onPressed: _busy ? null : () => _add(found),
              child: Text(_busy ? 'جارٍ الحفظ...' : 'خوّل ${found.fullName}'),
            ),
            TextButton(
              onPressed: _busy ? null : () => setState(() => _found = null),
              style: TextButton.styleFrom(minimumSize: const Size.fromHeight(52), foregroundColor: AppColors.ink),
              child: const Text('ليس هو، ابحث مرة أخرى'),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            ErrorBox(_error!),
          ],
          if (_done != null) ...[
            const SizedBox(height: 12),
            Container(
              key: const Key('delegates-done'),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(12)),
              child: Text(_done!, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.onPrimarySoft)),
            ),
          ],
          const SizedBox(height: 12),
          TextButton(
            key: const Key('delegates-close'),
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(minimumSize: const Size.fromHeight(56), backgroundColor: AppColors.line, foregroundColor: AppColors.ink),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  Widget _row(Delegate delegate) {
    final confirming = _confirmingRemove == delegate.delegationId;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _Avatar(delegate: delegate),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(delegate.fullName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    if (delegate.department != null && delegate.department!.isNotEmpty)
                      Text(delegate.department!, style: const TextStyle(fontSize: 16, color: AppColors.inkMuted)),
                  ],
                ),
              ),
              if (!confirming)
                TextButton(
                  key: Key('delegate-remove-${delegate.delegationId}'),
                  onPressed: _busy ? null : () => setState(() => _confirmingRemove = delegate.delegationId),
                  style: TextButton.styleFrom(foregroundColor: AppColors.danger, minimumSize: const Size(64, 48)),
                  child: const Text('إلغاء'),
                ),
            ],
          ),
          if (confirming) ...[
            const SizedBox(height: 8),
            Text('إلغاء تخويل ${delegate.fullName}؟ لن يستطيع استلام وجباتك بعد الآن.', style: const TextStyle(fontSize: 17)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    key: const Key('delegate-remove-confirm'),
                    onPressed: _busy ? null : () => _remove(delegate),
                    style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
                    child: const Text('نعم، ألغِ'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : () => setState(() => _confirmingRemove = null),
                    child: const Text('تراجع'),
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
