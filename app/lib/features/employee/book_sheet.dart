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

Future<BookResult?> showBookSheet(BuildContext context, Offering offering) {
  return showAppSheet<BookResult>(context, builder: (_) => BookSheet(offering: offering));
}

class BookSheet extends ConsumerStatefulWidget {
  const BookSheet({super.key, required this.offering});

  final Offering offering;

  @override
  ConsumerState<BookSheet> createState() => _BookSheetState();
}

class _BookSheetState extends ConsumerState<BookSheet> {
  bool _repeat = false;
  bool _busy = false;
  String? _error;

  // Kept across retries of the same choice, so a lost reply can never charge twice.
  String _key = const Uuid().v4();

  Future<void> _confirm(List<Offering> chosen) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    try {
      final result = await ref.read(employeeRepositoryProvider).book([for (final offering in chosen) offering.id], _key);
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
    final pick = widget.offering;
    final now = DateTime.now();
    final series = bookableSeries(
      pick,
      ref.watch(offeringsProvider).valueOrNull ?? const [],
      ref.watch(activeBookingsProvider).valueOrNull ?? const [],
      now,
    );
    final chosen = _repeat && series.isNotEmpty ? series : [pick];
    final total = chosen.fold<int>(0, (sum, offering) => sum + offering.price);
    final available = ref.watch(walletProvider).valueOrNull?.available ?? 0;
    final shortfall = total - available;
    final textTheme = Theme.of(context).textTheme;

    return PopScope(
      canPop: !_busy,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('تأكيد الحجز', style: textTheme.titleLarge),
          const SizedBox(height: 12),
          Text(pick.name, style: textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('${pick.period.label} ${relativeDay(pick.serviceDate, dayOf(now))}', style: textTheme.bodyLarge),
          if (series.length > 1) ...[
            const SizedBox(height: 12),
            OptionSwitch(
              key: const Key('book-repeat'),
              label: 'كرر كل ${weekdayName(pick.serviceDate)} من ${monthName(pick.serviceDate)} (${mealCount(series.length)})',
              value: _repeat,
              onChanged: _busy
                  ? (_) {}
                  : (value) => setState(() {
                        _repeat = value;
                        _key = const Uuid().v4();
                      }),
            ),
          ],
          const SizedBox(height: 12),
          FactBox(lines: [
            ('المبلغ:', dinars(total)),
            ('رصيدك بعد الحجز:', dinars(shortfall > 0 ? 0 : available - total)),
            ('يمكنك الإلغاء حتى', deadlineText(pick.cancelUntil, pick.serviceDate)),
          ]),
          if (_error != null) ...[
            const SizedBox(height: 12),
            ErrorBox(_error!),
          ],
          if (shortfall > 0) ...[
            const SizedBox(height: 12),
            ErrorBox('ينقصك ${dinars(shortfall)}. راجع مسؤول النظام لشحن رصيدك.'),
          ] else ...[
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('book-confirm'),
              onPressed: _busy ? null : () => _confirm(chosen),
              child: Text(_busy ? 'جارٍ الحجز...' : 'تأكيد الحجز'),
            ),
          ],
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(minimumSize: const Size.fromHeight(56), foregroundColor: AppColors.ink),
            child: const Text('رجوع'),
          ),
        ],
      ),
    );
  }
}
