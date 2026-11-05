import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../shared/app_sheet.dart';
import '../../shared/notice.dart';
import 'book_sheet.dart';
import 'employee_models.dart';
import 'employee_providers.dart';
import 'employee_repository.dart';

class MealsPage extends ConsumerWidget {
  const MealsPage({super.key});

  Future<void> _book(BuildContext context, Offering offering) async {
    final result = await showBookSheet(context, offering);
    if (result == null || !context.mounted) return;
    await showNotice(
      context,
      kind: NoticeKind.done,
      title: result.count > 1 ? 'تم حجز ${mealCountObject(result.count)}' : 'تم الحجز',
      text: offering.name,
    );
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
    final last = offeringsValue.isEmpty || offeringsValue.last.serviceDate.isBefore(today) ? today : offeringsValue.last.serviceDate;
    final days = [for (var day = today; !day.isAfter(last); day = addDays(day, 1)) day];

    // Opens on the first day that still has something to book.
    final firstOpen = offeringsValue.where((offering) => offering.isOpenAt(now)).firstOrNull?.serviceDate ?? today;
    final picked = ref.watch(mealsDayProvider);
    final selected = picked != null && days.contains(picked) ? picked : firstOpen;

    final dayMeals = offeringsValue.where((offering) => offering.serviceDate == selected).toList();
    final heldOfferings = {for (final booking in activeValue) booking.offeringId};
    final next = nextBooking(activeValue, now);

    return RefreshIndicator(
      onRefresh: () async {
        refreshEmployeeData(ref);
        await ref.read(walletProvider.future);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          _BalanceCard(wallet: walletValue),
          if (next != null) ...[
            const SizedBox(height: 16),
            _NextMealCard(booking: next, today: today),
          ],
          const SizedBox(height: 16),
          _DayStrip(
            days: days,
            selected: selected,
            today: today,
            onPick: (day) => ref.read(mealsDayProvider.notifier).state = day,
          ),
          const SizedBox(height: 16),
          if (dayMeals.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Text(
                offeringsValue.isEmpty ? 'لم يُنشر برنامج الوجبات بعد.' : 'لا توجد وجبات في هذا اليوم.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppColors.inkMuted),
              ),
            ),
          for (final period in MealPeriod.values)
            if (dayMeals.any((offering) => offering.period == period)) ...[
              _PeriodHeading(period: period),
              const SizedBox(height: 10),
              for (final offering in dayMeals.where((offering) => offering.period == period)) ...[
                _MealCard(
                  offering: offering,
                  booked: heldOfferings.contains(offering.id),
                  now: now,
                  imageUrl: offering.imagePath == null ? null : ref.read(employeeRepositoryProvider).imageUrl(offering.imagePath!),
                  onBook: () => _book(context, offering),
                ),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 4),
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
        ],
      ),
    );
  }
}

class _DayStrip extends StatefulWidget {
  const _DayStrip({required this.days, required this.selected, required this.today, required this.onPick});

  final List<DateTime> days;
  final DateTime selected;
  final DateTime today;
  final ValueChanged<DateTime> onPick;

  @override
  State<_DayStrip> createState() => _DayStripState();
}

class _DayStripState extends State<_DayStrip> {
  final _selectedKey = GlobalKey();

  void _reveal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _selectedKey.currentContext;
      if (target != null) Scrollable.ensureVisible(target, alignment: 0.5);
    });
  }

  @override
  void initState() {
    super.initState();
    _reveal();
  }

  @override
  void didUpdateWidget(_DayStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) _reveal();
  }

  String _label(DateTime day) {
    if (day == widget.today) return 'اليوم';
    if (day == addDays(widget.today, 1)) return 'غداً';
    return weekdayName(day);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final day in widget.days)
            Padding(
              key: day == widget.selected ? _selectedKey : null,
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: _DayChip(label: _label(day), number: day.day, selected: day == widget.selected, onTap: () => widget.onPick(day)),
            ),
        ],
      ),
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({required this.label, required this.number, required this.selected, required this.onTap});

  final String label;
  final int number;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? AppColors.surface : AppColors.ink;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? AppColors.primary : AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: selected ? AppColors.primary : AppColors.unselected, width: 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 72, minHeight: 68),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, height: 1.25, color: foreground)),
                  Text('$number', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, height: 1.25, color: foreground)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PeriodHeading extends StatelessWidget {
  const _PeriodHeading({required this.period});

  final MealPeriod period;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 28, height: 6, decoration: BoxDecoration(color: period.color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 10),
        Text(period.label, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _MealCard extends StatelessWidget {
  const _MealCard({required this.offering, required this.booked, required this.now, required this.imageUrl, required this.onBook});

  final Offering offering;
  final bool booked;
  final DateTime now;
  final String? imageUrl;
  final VoidCallback onBook;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 120,
            child: imageUrl == null
                ? const _ImagePlaceholder()
                : Image.network(
                    imageUrl!,
                    fit: BoxFit.cover,
                    cacheWidth: 800,
                    errorBuilder: (_, __, ___) => const _ImagePlaceholder(),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: Text(offering.name, style: textTheme.titleMedium)),
                    const SizedBox(width: 12),
                    Text(dinars(offering.price), style: textTheme.titleMedium),
                  ],
                ),
                if (offering.description.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(offering.description, style: textTheme.bodyMedium?.copyWith(color: AppColors.inkMuted)),
                ],
                if (offering.extras.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('معها: ${offering.extras.join(' و')}', style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
                ],
                const SizedBox(height: 10),
                _action(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _action() {
    if (booked) {
      return const _StateBox(
        background: AppColors.primarySoft,
        foreground: AppColors.onPrimarySoft,
        icon: Icons.check_rounded,
        text: 'محجوزة',
      );
    }
    if (!now.isBefore(offering.bookUntil)) {
      return const _StateBox(background: AppColors.closed, foreground: AppColors.inkMuted, text: 'انتهى وقت الحجز');
    }
    if (offering.soldOut) {
      return const _StateBox(background: AppColors.closed, foreground: AppColors.inkMuted, text: 'نفدت الكمية');
    }
    return FilledButton(
      key: Key('book-${offering.id}'),
      onPressed: onBook,
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56), textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
      child: const Text('احجز'),
    );
  }
}

class _StateBox extends StatelessWidget {
  const _StateBox({required this.background, required this.foreground, this.icon, required this.text});

  final Color background;
  final Color foreground;
  final IconData? icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(14)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, color: foreground),
            const SizedBox(width: 8),
          ],
          Text(text, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: foreground)),
        ],
      ),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppColors.imagePlaceholder,
      child: Center(child: Icon(Icons.restaurant, size: 40, color: AppColors.inkMuted)),
    );
  }
}
