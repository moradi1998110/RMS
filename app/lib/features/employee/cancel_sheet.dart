import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../shared/app_sheet.dart';
import '../../shared/error_box.dart';
import 'employee_models.dart';
import 'employee_providers.dart';
import 'employee_repository.dart';

Future<CancelResult?> showCancelSheet(BuildContext context, Booking booking) {
  return showAppSheet<CancelResult>(context, builder: (_) => CancelSheet(booking: booking));
}

class CancelSheet extends ConsumerStatefulWidget {
  const CancelSheet({super.key, required this.booking});

  final Booking booking;

  @override
  ConsumerState<CancelSheet> createState() => _CancelSheetState();
}

class _CancelSheetState extends ConsumerState<CancelSheet> {
  bool _more = false;
  bool _busy = false;
  String? _error;

  // Kept across retries of the same choice, so a lost reply can never refund twice.
  String _key = const Uuid().v4();

  Future<void> _confirm() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    final repository = ref.read(employeeRepositoryProvider);
    try {
      final result = _more
          ? await repository.cancelSeries(widget.booking.id, _key)
          : await repository.cancel(widget.booking.id, _key);
      refreshEmployeeData(ref);
      navigator.pop(result);
    } on EmployeeFailure catch (failure) {
      refreshEmployeeData(ref);
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
    final booking = widget.booking;
    final now = DateTime.now();
    final series = cancelSeriesFor(booking, ref.watch(activeBookingsProvider).valueOrNull ?? const [], now);
    final chosenCount = _more ? series.cancellable.length + 1 : 1;
    final refund = booking.amount + (_more ? series.cancellable.fold<int>(0, (sum, other) => sum + other.amount) : 0);
    final textTheme = Theme.of(context).textTheme;
    final weekday = weekdayName(booking.serviceDate);

    return PopScope(
      canPop: !_busy,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('إلغاء هذا الحجز؟', style: textTheme.titleLarge),
          const SizedBox(height: 12),
          Text(booking.mealName, style: textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('${booking.period.label} ${relativeDay(booking.serviceDate, dayOf(now))}', style: textTheme.bodyLarge),
          if (series.cancellable.isNotEmpty) ...[
            const SizedBox(height: 12),
            OptionSwitch(
              key: const Key('cancel-more'),
              label: 'ألغِ أيضاً كل $weekday المتبقية من ${monthName(booking.serviceDate)} (${mealCount(series.cancellable.length)})',
              value: _more,
              color: AppColors.danger,
              soft: AppColors.dangerSoft,
              onChanged: _busy
                  ? (_) {}
                  : (value) => setState(() {
                        _more = value;
                        _key = const Uuid().v4();
                      }),
            ),
          ],
          const SizedBox(height: 12),
          FactBox(lines: [('سيرجع إلى رصيدك فوراً:', dinars(refund))]),
          if (_more && series.locked > 0) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: AppColors.warningSoft, borderRadius: BorderRadius.circular(12)),
              child: Text(
                'لن يشمل الإلغاء ${mealCountObject(series.locked)} انتهى وقت إلغائها.',
                style: const TextStyle(fontSize: 17, color: AppColors.onWarningSoft),
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            ErrorBox(_error!),
          ],
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('cancel-confirm'),
            onPressed: _busy ? null : _confirm,
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: Text(_busy
                ? 'جارٍ الإلغاء...'
                : chosenCount > 1
                    ? 'نعم، ألغِ ${mealCountObject(chosenCount)}'
                    : 'نعم، ألغِ الحجز'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(minimumSize: const Size.fromHeight(56), foregroundColor: AppColors.ink),
            child: const Text('لا، أبقِ الحجز'),
          ),
        ],
      ),
    );
  }
}
