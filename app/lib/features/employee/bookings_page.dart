import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../shared/app_sheet.dart';
import 'codes_page.dart';
import 'employee_models.dart';
import 'employee_providers.dart';
import 'meal_card.dart';

const _usualPeriods = [MealPeriod.breakfast, MealPeriod.lunch, MealPeriod.dinner];
const _ramadanPeriods = [MealPeriod.suhoor, MealPeriod.iftar];

bool _countsOnCalendar(Booking booking) => booking.status != BookingStatus.cancelledByRestaurant;

class BookingsPage extends ConsumerWidget {
  const BookingsPage({super.key});

  void _openDay(BuildContext context, DateTime day) {
    showAppSheet<void>(context, background: AppColors.ground, builder: (_) => _DaySheet(day: day));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(calendarMonthProvider);
    final bookings = ref.watch(monthBookingsProvider(month));
    // Loaded with the month on screen, so a day opens with its meals already there.
    ref.watch(monthOfferingsProvider(month));
    final textTheme = Theme.of(context).textTheme;

    void moveMonth(int by) {
      ref.read(calendarMonthProvider.notifier).state = DateTime(month.year, month.month + by);
    }

    final value = bookings.valueOrNull;
    final today = dayOf(DateTime.now());
    final live = (value ?? const <Booking>[]).where((booking) => booking.isLive && !booking.serviceDate.isBefore(today)).toList();
    final amount = live.fold<int>(0, (sum, booking) => sum + booking.amount);

    return RefreshIndicator(
      onRefresh: () async {
        refreshEmployeeData(ref);
        await ref.read(monthBookingsProvider(month).future);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          Text('حجوزاتي', style: textTheme.headlineMedium?.copyWith(fontSize: 28)),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.fromLTRB(10, 14, 10, 16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.line),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    _MonthButton(icon: Icons.chevron_left, label: 'الشهر السابق', onTap: () => moveMonth(-1)),
                    Expanded(
                      child: Text(
                        '${monthName(month)} ${month.year}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
                      ),
                    ),
                    _MonthButton(icon: Icons.chevron_right, label: 'الشهر التالي', onTap: () => moveMonth(1)),
                  ],
                ),
                const SizedBox(height: 10),
                if (value == null)
                  SizedBox(
                    height: 200,
                    child: LoadingOrError(error: bookings.error, onRetry: () => ref.invalidate(monthBookingsProvider(month))),
                  )
                else
                  _MonthGrid(month: month, bookings: value, today: today, onOpen: (day) => _openDay(context, day)),
                const SizedBox(height: 10),
                _Legend(bookings: value ?? const []),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.line),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              live.isEmpty ? 'لا توجد حجوزات قادمة في هذا الشهر.' : 'حجوزاتك القادمة هذا الشهر: ${mealCount(live.length)} بمبلغ ${dinars(amount)}.',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(height: 14),
          Text('اضغط على أي يوم لترى تفاصيله.', textAlign: TextAlign.center, style: textTheme.bodyMedium?.copyWith(color: AppColors.inkMuted)),
        ],
      ),
    );
  }
}

class _MonthButton extends StatelessWidget {
  const _MonthButton({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: AppColors.ground,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(width: 52, height: 52, child: Icon(icon, color: AppColors.ink)),
        ),
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({required this.month, required this.bookings, required this.today, required this.onOpen});

  final DateTime month;
  final List<Booking> bookings;
  final DateTime today;
  final ValueChanged<DateTime> onOpen;

  @override
  Widget build(BuildContext context) {
    final cells = calendarCells(month);
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    return Column(
      children: [
        Row(
          children: [
            for (final head in calendarHeads)
              Expanded(
                child: Text(
                  head,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.inkMuted),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        for (var week = 0; week < cells.length ~/ 7; week++)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Row(
              children: [
                for (final day in cells.sublist(week * 7, week * 7 + 7))
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1.5),
                      child: day == null
                          ? const SizedBox.shrink()
                          : _DayCell(
                              day: day,
                              today: today,
                              bookings: bookings.where((booking) => booking.serviceDate == day && _countsOnCalendar(booking)).toList(),
                              onTap: () => onOpen(day),
                            ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({required this.day, required this.today, required this.bookings, required this.onTap});

  final DateTime day;
  final DateTime today;
  final List<Booking> bookings;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isToday = day == today;
    final lines = List<Color>.filled(3, AppColors.emptyLine);
    for (final booking in bookings) {
      lines[booking.period.calendarLine] = booking.period.color;
    }
    final names = {for (final booking in bookings) booking.period.label}.join(' و');
    return Semantics(
      button: true,
      label: '${shortDate(day)}، ${names.isEmpty ? 'لا حجز' : 'محجوز: $names'}',
      excludeSemantics: true,
      child: Material(
        color: isToday ? AppColors.todayCell : AppColors.dayCell,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: isToday ? AppColors.ink : Colors.transparent, width: 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: Key('day-${isoDate(day)}'),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 5, 4, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${day.day}',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, height: 1.3, color: day.isBefore(today) ? AppColors.pastDay : AppColors.ink),
                ),
                const SizedBox(height: 4),
                for (final color in lines) ...[
                  Container(height: 5, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
                  const SizedBox(height: 3),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.bookings});

  final List<Booking> bookings;

  @override
  Widget build(BuildContext context) {
    final ramadan = bookings.any((booking) => _ramadanPeriods.contains(booking.period));
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 16,
      runSpacing: 4,
      children: [
        for (final period in [..._usualPeriods, if (ramadan) ..._ramadanPeriods])
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 22, height: 6, decoration: BoxDecoration(color: period.color, borderRadius: BorderRadius.circular(3))),
              const SizedBox(width: 6),
              Text(period.label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            ],
          ),
      ],
    );
  }
}

class _DaySheet extends ConsumerWidget {
  const _DaySheet({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final today = dayOf(now);
    final bookings = (ref.watch(monthBookingsProvider(DateTime(day.year, day.month))).valueOrNull ?? const <Booking>[])
        .where((booking) => booking.serviceDate == day)
        .toList();
    final offeringsAsync = ref.watch(monthOfferingsProvider(DateTime(day.year, day.month)));
    final offerings = offeringsAsync.valueOrNull ?? const <Offering>[];
    final dayOfferings = offerings.where((offering) => offering.serviceDate == day).toList();
    final published = !day.isBefore(today) && offerings.isNotEmpty && !day.isAfter(offerings.last.serviceDate);

    bool ofRamadan(MealPeriod period) => _ramadanPeriods.contains(period);
    final ramadan = bookings.any((booking) => ofRamadan(booking.period)) || dayOfferings.any((offering) => ofRamadan(offering.period));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(child: Text(longDate(day), style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w700))),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(backgroundColor: AppColors.line, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: const Text('إغلاق'),
            ),
          ],
        ),
        if (offeringsAsync.isLoading && !offeringsAsync.hasValue && !day.isBefore(today))
          const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
        else
        for (final period in ramadan ? _ramadanPeriods : _usualPeriods) ...[
          const SizedBox(height: 12),
          _PeriodGroup(
            period: period,
            bookings: bookings.where((booking) => booking.period == period).toList(),
            offerings: dayOfferings.where((offering) => offering.period == period).toList(),
            past: day.isBefore(today),
            published: published,
            now: now,
            onCancel: (booking) => cancelAndTell(context, booking),
          ),
        ],
      ],
    );
  }
}

class _PeriodGroup extends StatelessWidget {
  const _PeriodGroup({
    required this.period,
    required this.bookings,
    required this.offerings,
    required this.past,
    required this.published,
    required this.now,
    required this.onCancel,
  });

  final MealPeriod period;
  final List<Booking> bookings;
  final List<Offering> offerings;
  final bool past;
  final bool published;
  final DateTime now;
  final ValueChanged<Booking> onCancel;

  String get _emptyText {
    if (past) return 'لا يوجد حجز.';
    if (!published) return 'لم يُنشر برنامج هذا اليوم بعد.';
    if (offerings.isEmpty) return 'لا توجد وجبة في هذه الفترة.';
    if (offerings.any((offering) => offering.isOpenAt(now))) return 'لا يوجد حجز.';
    return 'لا يوجد حجز، وانتهى وقت الحجز.';
  }

  @override
  Widget build(BuildContext context) {
    final held = {for (final booking in bookings) if (booking.status != BookingStatus.cancelledByRestaurant) booking.offeringId};
    // Meals of this period not yet booked, each with its own book button right here.
    final toBook = past ? const <Offering>[] : offerings.where((offering) => !held.contains(offering.id)).toList();
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
            children: [
              Container(width: 28, height: 6, decoration: BoxDecoration(color: period.color, borderRadius: BorderRadius.circular(3))),
              const SizedBox(width: 10),
              Text(period.label, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 10),
          for (final booking in bookings) ...[
            _BookingDetails(booking: booking, now: now, onCancel: () => onCancel(booking)),
            const SizedBox(height: 10),
          ],
          if (bookings.isEmpty && toBook.isEmpty) Text(_emptyText, style: const TextStyle(fontSize: 17, color: AppColors.inkMuted)),
          for (final offering in toBook) ...[
            MealCard(offering: offering, booking: null, now: now, showImage: false),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _BookingDetails extends StatelessWidget {
  const _BookingDetails({required this.booking, required this.now, required this.onCancel});

  final Booking booking;
  final DateTime now;
  final VoidCallback onCancel;

  (String, Color) get _status => switch (booking.status) {
        BookingStatus.pickedUp => ('تم الاستلام', AppColors.onPrimarySoft),
        BookingStatus.noShow => ('لم تُستلم، واستُقطع المبلغ', AppColors.onDangerSoft),
        BookingStatus.cancelledByRestaurant => ('ألغاها المطعم، ورجع المبلغ إلى رصيدك', AppColors.onDangerSoft),
        BookingStatus.cancelled => ('أُلغي الحجز', AppColors.inkMuted),
        BookingStatus.booked when booking.canCancelAt(now) => (
            'يمكنك الإلغاء حتى ${deadlineText(booking.cancelUntil, booking.serviceDate)}',
            AppColors.onPrimarySoft,
          ),
        BookingStatus.booked => ('لا يمكن إلغاؤها الآن، وستُخصم إذا لم تستلمها', AppColors.onDangerSoft),
      };

  @override
  Widget build(BuildContext context) {
    final (statusText, statusColor) = _status;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(booking.mealName, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('${clockRange(booking.pickupFrom, booking.pickupUntil)} · ${dinars(booking.amount)}', style: const TextStyle(fontSize: 17)),
        const SizedBox(height: 4),
        Text(statusText, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w500, color: statusColor)),
        if (booking.isLive && !booking.pickupOpenAt(now) && now.isBefore(booking.pickupFrom)) ...[
          const SizedBox(height: 4),
          Text(
            'يظهر الباركود عند بدء الاستلام ${relativeDay(dayOf(booking.pickupFrom), dayOf(now))} ${clock(booking.pickupFrom)}',
            key: Key('code-later-${booking.id}'),
            style: const TextStyle(fontSize: 16, color: AppColors.inkMuted),
          ),
        ],
        if (booking.pickupOpenAt(now)) ...[
          const SizedBox(height: 8),
          FilledButton(
            key: Key('codes-${booking.id}'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => CodesPage(startBookingId: booking.id)),
            ),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56), textStyle: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
            child: const Text('اعرض الباركود'),
          ),
        ],
        if (booking.canCancelAt(now)) ...[
          const SizedBox(height: 8),
          OutlinedButton(
            key: Key('cancel-${booking.id}'),
            onPressed: onCancel,
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger, side: const BorderSide(color: AppColors.danger, width: 2)),
            child: const Text('إلغاء الحجز'),
          ),
        ] else if (booking.isLive) ...[
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(minHeight: 56),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppColors.closed, borderRadius: BorderRadius.circular(14)),
            child: const Text('انتهى وقت الإلغاء', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: AppColors.inkMuted)),
          ),
        ],
      ],
    );
  }
}
