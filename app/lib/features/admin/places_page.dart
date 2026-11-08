import 'package:flutter/material.dart';
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

class PlacesPage extends ConsumerWidget {
  const PlacesPage({super.key});

  Future<void> _add(BuildContext context) async {
    final saved = await showAppSheet<bool>(context, builder: (_) => const _PlaceSheet());
    if (saved != true || !context.mounted) return;
    await showNotice(context, kind: NoticeKind.done, title: 'أُضيف الموقع والمطعم');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final places = ref.watch(placesProvider);
    final users = ref.watch(usersProvider);
    final placesValue = places.valueOrNull;
    final usersValue = users.valueOrNull;
    if (placesValue == null || usersValue == null) {
      return LoadingOrError(error: places.error ?? users.error, onRetry: () => refreshAdminData(ref));
    }

    return RefreshIndicator(
      onRefresh: () async {
        refreshAdminData(ref);
        await ref.read(placesProvider.future);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          Text('المواقع والمطاعم', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 28)),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('add-place'),
            onPressed: () => _add(context),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(60), textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            child: const Text('إضافة موقع ومطعم'),
          ),
          const SizedBox(height: 12),
          if (placesValue.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text('لا يوجد مطعم بعد. ابدأ بإضافة أول موقع ومطعم.', style: TextStyle(fontSize: 18)),
            ),
          for (final place in placesValue) ...[
            _PlaceCard(place: place, users: usersValue.where((user) => user.restaurantId == place.id).toList()),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 6),
          const Text('تواريخ رمضان', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          const _RamadanCard(),
        ],
      ),
    );
  }
}

class _PlaceCard extends StatelessWidget {
  const _PlaceCard({required this.place, required this.users});

  final Place place;
  final List<AdminUser> users;

  @override
  Widget build(BuildContext context) {
    final managers = users.where((user) => user.role == UserRole.manager && user.isActive).map((user) => user.fullName).toList();
    final employees = users.where((user) => user.role == UserRole.employee && user.isActive).length;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(place.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          Text('الموقع: ${place.siteName}', style: const TextStyle(fontSize: 17, color: AppColors.inkMuted)),
          Text('المدير: ${managers.isEmpty ? 'لم يُحدَّد بعد' : managers.join('، ')}', style: const TextStyle(fontSize: 17)),
          Text('الموظفون: $employees', style: const TextStyle(fontSize: 17)),
        ],
      ),
    );
  }
}

class _PlaceSheet extends ConsumerStatefulWidget {
  const _PlaceSheet();

  @override
  ConsumerState<_PlaceSheet> createState() => _PlaceSheetState();
}

class _PlaceSheetState extends ConsumerState<_PlaceSheet> {
  final _site = TextEditingController();
  final _name = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _site.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    if (_site.text.trim().isEmpty || _name.text.trim().isEmpty) {
      setState(() => _error = 'اكتب اسم الموقع واسم المطعم.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    try {
      await ref.read(adminRepositoryProvider).addPlace(siteName: _site.text, restaurantName: _name.text);
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
    return PopScope(
      canPop: !_busy,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('موقع ومطعم جديدان', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          TextField(
            key: const Key('place-site'),
            controller: _site,
            decoration: const InputDecoration(labelText: 'اسم الموقع'),
            style: const TextStyle(fontSize: 19),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 14),
          TextField(
            key: const Key('place-name'),
            controller: _name,
            decoration: const InputDecoration(labelText: 'اسم المطعم'),
            style: const TextStyle(fontSize: 19),
            textInputAction: TextInputAction.done,
          ),
          const SizedBox(height: 12),
          const Text('تُضاف أوقات الفطور والغداء والعشاء الافتراضية تلقائياً، ويعدّلها مدير المطعم.', style: TextStyle(fontSize: 17, color: AppColors.inkMuted)),
          if (_error != null) ...[
            const SizedBox(height: 12),
            ErrorBox(_error!),
          ],
          const SizedBox(height: 14),
          FilledButton(
            key: const Key('place-save'),
            onPressed: _busy ? null : _save,
            child: Text(_busy ? 'جارٍ الحفظ...' : 'حفظ'),
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

class _RamadanCard extends ConsumerStatefulWidget {
  const _RamadanCard();

  @override
  ConsumerState<_RamadanCard> createState() => _RamadanCardState();
}

class _RamadanCardState extends ConsumerState<_RamadanCard> {
  DateTime? _start;
  DateTime? _end;
  RamadanImpact? _impact;
  bool _busy = false;
  String? _error;
  String _key = const Uuid().v4();

  void _changed(void Function() change) {
    setState(() {
      change();
      _impact = null;
      _error = null;
      _key = const Uuid().v4();
    });
  }

  Future<void> _pick(DateTime? current, ValueChanged<DateTime> onPicked) async {
    final today = dayOf(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? today,
      firstDate: DateTime(today.year - 1),
      lastDate: DateTime(today.year + 10),
    );
    if (picked != null && mounted) _changed(() => onPicked(picked));
  }

  Future<void> _review() async {
    final start = _start;
    final end = _end;
    if (start == null || end == null || start.isAfter(end)) {
      await showNotice(context, kind: NoticeKind.warning, title: datesRule);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final impact = await ref.read(adminRepositoryProvider).previewRamadan(hijriYearOf(start), start, end);
      if (mounted) setState(() => _impact = impact);
    } on AdminFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final start = _start!;
    final end = _end!;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(adminRepositoryProvider).saveRamadan(hijriYearOf(start), start, end, _key);
      ref.invalidate(ramadanProvider);
      if (!mounted) return;
      setState(() {
        _start = null;
        _end = null;
        _impact = null;
        _key = const Uuid().v4();
      });
      await showNotice(context, kind: NoticeKind.done, title: 'حُفظت تواريخ رمضان', text: 'تُعرض في هذه الأيام وجبتا السحور والإفطار فقط.');
    } on AdminFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = dayOf(DateTime.now());
    final saved = (ref.watch(ramadanProvider).valueOrNull ?? const <RamadanPeriod>[]).where((period) => !period.end.isBefore(today)).toList();
    final impact = _impact;
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
          for (final period in saved)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text('المحفوظ: من ${longDate(period.start)} إلى ${longDate(period.end)}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500)),
            ),
          _DateField(key: const Key('ramadan-start'), label: 'أول يوم', value: _start, onTap: _busy ? null : () => _pick(_start, (day) => _start = day)),
          const SizedBox(height: 10),
          _DateField(key: const Key('ramadan-end'), label: 'آخر يوم', value: _end, onTap: _busy ? null : () => _pick(_end ?? _start, (day) => _end = day)),
          const SizedBox(height: 10),
          OutlinedButton(
            key: const Key('ramadan-review'),
            onPressed: _busy ? null : _review,
            child: const Text('راجع الأثر قبل الحفظ'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            ErrorBox(_error!),
          ],
          if (impact != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: AppColors.warningSoft, borderRadius: BorderRadius.circular(12)),
              child: Text(
                impact.offerings == 0
                    ? 'لن تُلغى أي وجبة منشورة.'
                    : 'ستُلغى ${mealCount(impact.offerings)} منشورة داخل هذه التواريخ، وترجع نقاط ${impact.bookings} حجز إلى أصحابها.',
                style: const TextStyle(fontSize: 17, color: AppColors.onWarningSoft),
              ),
            ),
            const SizedBox(height: 10),
            FilledButton(
              key: const Key('ramadan-save'),
              onPressed: _busy ? null : _save,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(60), textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              child: const Text('تأكيد التواريخ'),
            ),
          ],
        ],
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({super.key, required this.label, required this.value, required this.onTap});

  final String label;
  final DateTime? value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.fieldBorder, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    value == null ? 'اختر التاريخ' : longDate(value!),
                    textAlign: TextAlign.end,
                    style: TextStyle(fontSize: 18, color: value == null ? AppColors.inkMuted : AppColors.ink),
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.calendar_month, color: AppColors.inkMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
