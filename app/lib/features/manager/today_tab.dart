import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/theme.dart';
import '../../shared/app_sheet.dart';
import '../../shared/error_box.dart';
import '../../shared/notice.dart';
import '../employee/employee_models.dart';
import 'manager_models.dart';
import 'manager_providers.dart';
import 'manager_repository.dart';
import 'scan_page.dart';

class TodayTab extends ConsumerWidget {
  const TodayTab({super.key});

  Future<void> _scan(BuildContext context, WidgetRef ref) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => const ScanPage()));
    ref.invalidate(todayProvider);
    ref.invalidate(offeringBookingsProvider);
    ref.invalidate(managerWeekProvider);
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref, TodayMeal meal) async {
    final refunded = await showAppSheet<int>(context, builder: (_) => _CancelMealSheet(meal: meal));
    if (refunded == null || !context.mounted) return;
    await showNotice(
      context,
      kind: NoticeKind.refund,
      title: 'أُلغيت الوجبة',
      text: refunded == 0 ? 'لم يكن عليها حجز قائم.' : 'رجعت نقاط $refunded حجز إلى أصحابها.',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(todayProvider);
    final value = today.valueOrNull;
    if (value == null) {
      return LoadingOrError(error: today.error, onRetry: () => ref.invalidate(todayProvider));
    }
    final now = DateTime.now();
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(todayProvider);
        await ref.read(todayProvider.future);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          Text('وجبات اليوم', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 28)),
          const SizedBox(height: 14),
          FilledButton.icon(
            key: const Key('open-scan'),
            onPressed: () => _scan(context, ref),
            icon: const Icon(Icons.qr_code_scanner, size: 34),
            label: const Text('امسح الباركود'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(96),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              textStyle: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 14),
          if (value.isEmpty) const Text('لا توجد وجبات اليوم.', style: TextStyle(fontSize: 18)),
          for (final meal in value) ...[
            _TodayCard(
              meal: meal,
              now: now,
              onPeople: () => showAppSheet<void>(context, builder: (_) => _PeopleSheet(meal: meal)),
              onCancel: () => _cancel(context, ref, meal),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.meal, required this.now, required this.onPeople, required this.onCancel});

  final TodayMeal meal;
  final DateTime now;
  final VoidCallback onPeople;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
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
          Text(meal.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          Text(meal.whenText(now), style: const TextStyle(fontSize: 17, color: AppColors.inkMuted)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _Count(label: 'محجوز', value: meal.booked, background: AppColors.ground)),
              const SizedBox(width: 8),
              Expanded(child: _Count(label: 'مستلم', value: meal.collected, background: AppColors.primarySoft)),
              const SizedBox(width: 8),
              Expanded(child: _Count(label: 'متبقٍ', value: meal.waiting, background: AppColors.warningSoft)),
            ],
          ),
          const SizedBox(height: 10),
          OutlinedButton(key: Key('people-${meal.offeringId}'), onPressed: onPeople, child: const Text('الأسماء والتسليم اليدوي')),
          if (now.isBefore(meal.pickupUntil)) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              key: Key('cancel-${meal.offeringId}'),
              onPressed: onCancel,
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger, side: const BorderSide(color: AppColors.danger, width: 2)),
              child: const Text('إلغاء هذه الوجبة'),
            ),
          ],
        ],
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.label, required this.value, required this.background});

  final String label;
  final int value;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          Text('$value', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
          Text(label, style: const TextStyle(fontSize: 16)),
        ],
      ),
    );
  }
}

class _CancelMealSheet extends ConsumerStatefulWidget {
  const _CancelMealSheet({required this.meal});

  final TodayMeal meal;

  @override
  ConsumerState<_CancelMealSheet> createState() => _CancelMealSheetState();
}

class _CancelMealSheetState extends ConsumerState<_CancelMealSheet> {
  final _reason = TextEditingController();
  final _key = const Uuid().v4();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_busy) return;
    if (_reason.text.trim().isEmpty) {
      setState(() => _error = 'اكتب السبب.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    try {
      final refunded = await ref.read(managerRepositoryProvider).cancelMeal(widget.meal.offeringId, _reason.text, _key);
      refreshManagerData(ref);
      navigator.pop(refunded);
    } on ManagerFailure catch (failure) {
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
          Text('إلغاء ${widget.meal.name}؟', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'ترجع النقاط فوراً إلى ${widget.meal.waiting} موظف لم يستلم بعد. الوجبات المستلمة تبقى كما هي.',
            style: const TextStyle(fontSize: 18),
          ),
          const SizedBox(height: 14),
          TextField(
            key: const Key('cancel-reason'),
            controller: _reason,
            decoration: const InputDecoration(labelText: 'السبب'),
            style: const TextStyle(fontSize: 18),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            ErrorBox(_error!),
          ],
          const SizedBox(height: 14),
          FilledButton(
            key: const Key('cancel-meal-confirm'),
            onPressed: _busy ? null : _confirm,
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: Text(_busy ? 'جارٍ الإلغاء...' : 'نعم، ألغِ الوجبة'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: const Text('لا، أبقِها'),
          ),
        ],
      ),
    );
  }
}

class _PeopleSheet extends ConsumerStatefulWidget {
  const _PeopleSheet({required this.meal});

  final TodayMeal meal;

  @override
  ConsumerState<_PeopleSheet> createState() => _PeopleSheetState();
}

class _PeopleSheetState extends ConsumerState<_PeopleSheet> {
  final _reason = TextEditingController();
  String? _delivering;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _deliver(String bookingId) async {
    if (_busy) return;
    if (_reason.text.trim().isEmpty) {
      setState(() => _error = 'اكتب سبب التسليم اليدوي، مثل: انقطع الإنترنت.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(managerRepositoryProvider).recordDelivery(bookingId, _reason.text, const Uuid().v4());
      refreshManagerData(ref);
      if (mounted) {
        _reason.clear();
        setState(() => _delivering = null);
      }
    } on ManagerFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _statusText(BookingStatus status) => switch (status) {
        BookingStatus.pickedUp => 'استلم',
        BookingStatus.noShow => 'لم يستلم',
        _ => 'بانتظار الاستلام',
      };

  @override
  Widget build(BuildContext context) {
    final bookings = ref.watch(offeringBookingsProvider(widget.meal.offeringId));
    final value = bookings.valueOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(widget.meal.name, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        if (value == null)
          SizedBox(
            height: 160,
            child: LoadingOrError(error: bookings.error, onRetry: () => ref.invalidate(offeringBookingsProvider(widget.meal.offeringId))),
          )
        else if (value.isEmpty)
          const Text('لا توجد حجوزات على هذه الوجبة.', style: TextStyle(fontSize: 18)),
        for (final booking in value ?? const <TodayBooking>[])
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(booking.employeeName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
                    const SizedBox(width: 8),
                    Text(_statusText(booking.status), style: const TextStyle(fontSize: 16, color: AppColors.inkMuted)),
                  ],
                ),
                if (booking.status != BookingStatus.pickedUp && _delivering != booking.id)
                  TextButton(
                    key: Key('deliver-${booking.id}'),
                    onPressed: () => setState(() {
                      _delivering = booking.id;
                      _error = null;
                    }),
                    style: TextButton.styleFrom(foregroundColor: AppColors.primary),
                    child: const Text('سجّل تسليماً يدوياً'),
                  ),
                if (_delivering == booking.id) ...[
                  const SizedBox(height: 6),
                  TextField(
                    key: const Key('deliver-reason'),
                    controller: _reason,
                    decoration: const InputDecoration(labelText: 'السبب'),
                    style: const TextStyle(fontSize: 18),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    ErrorBox(_error!),
                  ],
                  const SizedBox(height: 8),
                  OutlinedButton(
                    key: const Key('deliver-confirm'),
                    onPressed: _busy ? null : () => _deliver(booking.id),
                    child: Text(_busy ? 'جارٍ التسجيل...' : 'تأكيد التسليم'),
                  ),
                ],
                const Divider(color: AppColors.line),
              ],
            ),
          ),
        const SizedBox(height: 4),
        TextButton(
          key: const Key('people-close'),
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          child: const Text('إغلاق'),
        ),
      ],
    );
  }
}
