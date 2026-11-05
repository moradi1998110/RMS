import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import 'employee_models.dart';
import 'employee_providers.dart';
import 'employee_repository.dart';

/// Pickup codes whose pickup is open now, one card at a time: the user's own meal
/// and those delegated to them.
class CodesPage extends ConsumerStatefulWidget {
  const CodesPage({super.key, this.startBookingId});

  final String? startBookingId;

  @override
  ConsumerState<CodesPage> createState() => _CodesPageState();
}

class _CodesPageState extends ConsumerState<CodesPage> {
  List<Pickup>? _pickups;
  final _collected = <String>{};
  final _expired = <String>{};
  int _index = 0;
  bool _failed = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    // A scanned meal drops off the server's list, which is how this page learns of it.
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final latest = await ref.read(employeeRepositoryProvider).pickups();
      if (!mounted) return;
      setState(() {
        _failed = false;
        final known = _pickups;
        if (known == null) {
          _pickups = latest;
          final start = latest.indexWhere((pickup) => pickup.bookingId == widget.startBookingId);
          _index = start < 0 ? 0 : start;
        } else {
          // A code that left the list was scanned, unless its pickup time ran out.
          final live = {for (final pickup in latest) pickup.bookingId};
          final now = DateTime.now();
          for (final pickup in known.where((pickup) => !live.contains(pickup.bookingId))) {
            if (_collected.contains(pickup.bookingId) || _expired.contains(pickup.bookingId)) continue;
            (now.isBefore(pickup.pickupUntil) ? _collected : _expired).add(pickup.bookingId);
          }
          // A delegated meal can open while this page is up.
          final shown = {for (final pickup in known) pickup.bookingId};
          final added = latest.where((pickup) => !shown.contains(pickup.bookingId)).toList();
          if (added.isNotEmpty) _pickups = [...known, ...added];
        }
      });
    } on EmployeeFailure {
      // A weak connection must not hide codes already on screen.
      if (mounted && _pickups == null) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pickups = _pickups;
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      pickups == null || pickups.isEmpty ? 'باركود الاستلام' : '${_index + 1} من ${pickups.length}',
                      key: const Key('code-counter'),
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                    ),
                  ),
                  TextButton(
                    key: const Key('codes-close'),
                    onPressed: () {
                      refreshEmployeeData(ref);
                      Navigator.of(context).pop();
                    },
                    style: TextButton.styleFrom(backgroundColor: AppColors.closed),
                    child: const Text('إغلاق'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(child: _body(pickups)),
              if (pickups != null && pickups.length > 1) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        key: const Key('code-previous'),
                        onPressed: () => setState(() => _index = (_index - 1 + pickups.length) % pickups.length),
                        child: const Text('السابق'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        key: const Key('code-next'),
                        onPressed: () => setState(() => _index = (_index + 1) % pickups.length),
                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56), textStyle: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
                        child: const Text('التالي'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(List<Pickup>? pickups) {
    if (pickups == null) {
      if (!_failed) return const Center(child: CircularProgressIndicator());
      return const Center(
        child: Text('تعذّر عرض الباركود. تأكد من الإنترنت.', textAlign: TextAlign.center, style: TextStyle(fontSize: 18)),
      );
    }
    if (pickups.isEmpty) {
      final now = DateTime.now();
      final next = nextBooking(ref.watch(activeBookingsProvider).valueOrNull ?? const [], now);
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('لا توجد وجبات للاستلام الآن.', textAlign: TextAlign.center, style: TextStyle(fontSize: 18)),
            if (next != null && now.isBefore(next.pickupFrom)) ...[
              const SizedBox(height: 8),
              Text(
                'يظهر باركود ${next.mealName} ${relativeDay(dayOf(next.pickupFrom), dayOf(now))} الساعة ${clock(next.pickupFrom)}.',
                key: const Key('code-next-time'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, color: AppColors.inkMuted),
              ),
            ],
          ],
        ),
      );
    }
    final pickup = pickups[_index];
    final collected = _collected.contains(pickup.bookingId);
    final expired = _expired.contains(pickup.bookingId);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(pickup.isMine ? 'وجبتك أنت' : 'وجبة ${pickup.ownerName}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(pickup.mealName, style: const TextStyle(fontSize: 18)),
          Text(
            '${relativeDay(dayOf(pickup.pickupFrom), dayOf(DateTime.now()))} ${clockRange(pickup.pickupFrom, pickup.pickupUntil)}',
            style: const TextStyle(fontSize: 17, color: AppColors.inkMuted),
          ),
          const SizedBox(height: 16),
          if (collected)
            Container(
              key: const Key('code-done'),
              height: 280,
              decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(20)),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_rounded, size: 72, color: AppColors.onPrimarySoft),
                  Text('تم الاستلام', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.onPrimarySoft)),
                ],
              ),
            )
          else if (expired)
            Container(
              key: const Key('code-expired'),
              height: 280,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: AppColors.closed, borderRadius: BorderRadius.circular(20)),
              child: const Text('انتهى وقت الاستلام', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.inkMuted)),
            )
          else ...[
            Center(
              child: QrImageView(
                key: const Key('code-qr'),
                data: pickup.token,
                size: 280,
                backgroundColor: AppColors.surface,
              ),
            ),
            const SizedBox(height: 12),
            Text.rich(
              TextSpan(children: [
                const TextSpan(text: 'الرمز الاحتياطي: '),
                TextSpan(text: pickup.shortCode, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: 2)),
              ]),
              key: const Key('code-short'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18),
            ),
          ],
        ],
      ),
    );
  }
}
