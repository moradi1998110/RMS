import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../shared/app_sheet.dart';
import '../../shared/notice.dart';
import 'codes_page.dart';
import 'employee_models.dart';
import 'employee_providers.dart';
import 'meal_card.dart';
import 'rate_sheet.dart';

/// The day the meals page shows: today while something can still be booked today,
/// otherwise the next day that has meals open, so the evening shows tomorrow.
DateTime? shownDay(List<Offering> offerings, DateTime now) {
  final today = dayOf(now);
  if (offerings.any((offering) => offering.serviceDate == today && offering.isOpenAt(now))) return today;
  return offerings.where((offering) => offering.serviceDate.isAfter(today) && offering.isOpenAt(now)).firstOrNull?.serviceDate;
}

class MealsPage extends ConsumerWidget {
  const MealsPage({super.key});

  Future<void> _rate(BuildContext context, RatableMeal meal, int stars) async {
    final saved = await showRateSheet(context, meal, stars: stars);
    if (saved != true || !context.mounted) return;
    await showNotice(context, kind: NoticeKind.done, title: 'شكراً لك', text: 'وصل تقييمك إلى المطعم.');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallet = ref.watch(walletProvider);
    final offerings = ref.watch(offeringsProvider);
    final active = ref.watch(activeBookingsProvider);
    final walletValue = wallet.valueOrNull;
    final offeringsValue = offerings.valueOrNull;
    final activeValue = active.valueOrNull;

    if (walletValue == null || offeringsValue == null || activeValue == null) {
      return LoadingOrError(
        error: wallet.error ?? offerings.error ?? active.error,
        onRetry: () => refreshEmployeeData(ref),
      );
    }

    final now = DateTime.now();
    final today = dayOf(now);
    final day = shownDay(offeringsValue, now);
    final dayMeals = day == null ? const <Offering>[] : offeringsValue.where((offering) => offering.serviceDate == day).toList();
    final next = nextBooking(activeValue, now);
    final textTheme = Theme.of(context).textTheme;
    // Ratings never hold up the page; they appear once they load.
    final toRate = ref.watch(ratableMealsProvider).valueOrNull ?? const <RatableMeal>[];

    return RefreshIndicator(
      onRefresh: () async {
        refreshEmployeeData(ref);
        await ref.read(walletProvider.future);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          _BalanceCard(wallet: walletValue),
          for (final meal in toRate) ...[
            const SizedBox(height: 16),
            _RateCard(meal: meal, now: now, onPick: (stars) => _rate(context, meal, stars)),
          ],
          if (next != null) ...[
            const SizedBox(height: 16),
            _NextMealCard(booking: next, today: today),
          ],
          const SizedBox(height: 20),
          if (day == null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                offeringsValue.isEmpty ? 'لم يُنشر برنامج الوجبات بعد.' : 'لا توجد وجبات يمكن حجزها الآن.',
                key: const Key('meals-none'),
                textAlign: TextAlign.center,
                style: textTheme.bodyLarge?.copyWith(color: AppColors.inkMuted),
              ),
            ),
            OutlinedButton(
              key: const Key('go-bookings'),
              onPressed: () => ref.read(employeeTabProvider.notifier).state = 1,
              child: const Text('اعرض حجوزاتي'),
            ),
          ] else ...[
            Text(
              day == today ? 'وجبات اليوم' : day == addDays(today, 1) ? 'وجبات الغد' : 'وجبات ${longDate(day)}',
              key: const Key('meals-day'),
              style: textTheme.headlineMedium?.copyWith(fontSize: 26),
            ),
            if (day != today)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'انتهى حجز وجبات اليوم. لأيام أخرى افتح حجوزاتي.',
                  style: textTheme.bodyMedium?.copyWith(color: AppColors.inkMuted),
                ),
              ),
            const SizedBox(height: 14),
            for (final period in MealPeriod.values)
              if (dayMeals.any((offering) => offering.period == period)) ...[
                PeriodHeading(period: period),
                const SizedBox(height: 10),
                for (final offering in dayMeals.where((offering) => offering.period == period)) ...[
                  MealCard(offering: offering, booking: bookingOf(offering, activeValue), now: now),
                  const SizedBox(height: 12),
                ],
                const SizedBox(height: 4),
              ],
          ],
        ],
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.wallet});

  final Wallet wallet;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(20)),
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: AppColors.surface, fontSize: 17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('رصيدك المتاح'),
            Text.rich(
              TextSpan(children: [
                TextSpan(text: money(wallet.available), style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w700, height: 1.2)),
                const TextSpan(text: ' دينار', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500)),
              ]),
            ),
            const SizedBox(height: 4),
            Text('محجوز لوجباتك: ${dinars(wallet.held)}'),
          ],
        ),
      ),
    );
  }
}

class _RateCard extends StatelessWidget {
  const _RateCard({required this.meal, required this.now, required this.onPick});

  final RatableMeal meal;
  final DateTime now;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      key: Key('rate-${meal.bookingId}'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.warningSoft,
        border: Border.all(color: AppColors.star, width: 2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('كيف كانت وجبتك؟', style: textTheme.titleMedium?.copyWith(fontSize: 22)),
          const SizedBox(height: 4),
          Text('${meal.mealName} · ${meal.period.label} ${relativeDay(dayOf(meal.pickedUpAt), dayOf(now))}', style: textTheme.bodyMedium),
          const SizedBox(height: 8),
          StarRow(stars: 0, onPick: onPick, keyPrefix: 'rate-star-${meal.bookingId}'),
          const SizedBox(height: 4),
          Text(
            'يمكنك التقييم حتى ${relativeDay(dayOf(meal.rateUntil), dayOf(now))} ${clock(meal.rateUntil)}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, color: AppColors.onWarningSoft),
          ),
        ],
      ),
    );
  }
}

class _NextMealCard extends StatelessWidget {
  const _NextMealCard({required this.booking, required this.today});

  final Booking booking;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final pickupDay = relativeDay(dayOf(booking.pickupFrom), today);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.primary, width: 2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('وجبتك القادمة', style: textTheme.bodyMedium?.copyWith(color: AppColors.inkMuted, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text(booking.mealName, style: textTheme.titleMedium?.copyWith(fontSize: 22)),
          const SizedBox(height: 4),
          Text('استلمها $pickupDay ${clockRange(booking.pickupFrom, booking.pickupUntil)}', style: textTheme.bodyMedium),
          if (!booking.pickupOpenAt(DateTime.now()))
            Text('يظهر الباركود عند بدء الاستلام', style: textTheme.bodyMedium?.copyWith(color: AppColors.inkMuted)),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: const Key('next-codes'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => CodesPage(startBookingId: booking.id)),
              ),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(60), textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              child: const Text('اعرض الباركود'),
            ),
          ),
        ],
      ),
    );
  }
}
