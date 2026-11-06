import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../shared/notice.dart';
import 'book_sheet.dart';
import 'cancel_sheet.dart';
import 'employee_models.dart';
import 'employee_repository.dart';

/// Books a meal and says so. Shared by the meals page and the day in my bookings.
Future<void> bookAndTell(BuildContext context, Offering offering) async {
  final result = await showBookSheet(context, offering);
  if (result == null || !context.mounted) return;
  await showNotice(
    context,
    kind: NoticeKind.done,
    title: result.count > 1 ? 'تم حجز ${mealCountObject(result.count)}' : 'تم الحجز',
    text: offering.name,
  );
}

/// Asks before cancelling, then says how much came back.
Future<void> cancelAndTell(BuildContext context, Booking booking) async {
  final result = await showCancelSheet(context, booking);
  if (result == null || !context.mounted) return;
  await showNotice(
    context,
    kind: NoticeKind.refund,
    title: result.count > 1 ? 'أُلغيت ${mealCount(result.count)}' : 'أُلغي الحجز',
    text: 'رجع ${dinars(result.refunded)} إلى رصيدك',
  );
}

/// The user's live or settled booking of [offering], if any.
Booking? bookingOf(Offering offering, List<Booking> bookings) => bookings
    .where((booking) =>
        booking.offeringId == offering.id && booking.status != BookingStatus.cancelled && booking.status != BookingStatus.cancelledByRestaurant)
    .firstOrNull;

class PeriodHeading extends StatelessWidget {
  const PeriodHeading({super.key, required this.period});

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

/// A meal on offer. One button follows its state: book, cancel, or why neither.
class MealCard extends ConsumerWidget {
  const MealCard({super.key, required this.offering, required this.booking, required this.now, this.showImage = true});

  final Offering offering;
  final Booking? booking;
  final DateTime now;
  final bool showImage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final imagePath = offering.imagePath;
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
          if (showImage)
            SizedBox(
              height: 120,
              child: imagePath == null
                  ? const _ImagePlaceholder()
                  : Image.network(
                      ref.read(employeeRepositoryProvider).imageUrl(imagePath),
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
                const SizedBox(height: 8),
                Text(
                  "${now.isBefore(offering.bookUntil) ? 'آخر حجز وإلغاء' : 'كان آخر حجز'}: ${deadlineText(offering.bookUntil, offering.serviceDate)}",
                  style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 10),
                _action(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _action(BuildContext context) {
    final booking = this.booking;
    if (booking != null) {
      switch (booking.status) {
        case BookingStatus.pickedUp:
          return const _StateBox(background: AppColors.primarySoft, foreground: AppColors.onPrimarySoft, icon: Icons.check_rounded, text: 'تم الاستلام');
        case BookingStatus.noShow:
          return const _StateBox(background: AppColors.dangerSoft, foreground: AppColors.onDangerSoft, text: 'لم تُستلم');
        case _ when booking.canCancelAt(now):
          return OutlinedButton.icon(
            key: Key('unbook-${offering.id}'),
            onPressed: () => cancelAndTell(context, booking),
            icon: const Icon(Icons.check_rounded),
            label: const Text('محجوزة · إلغاء الحجز'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              foregroundColor: AppColors.danger,
              side: const BorderSide(color: AppColors.danger, width: 2),
              textStyle: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
            ),
          );
        case _:
          return const _StateBox(
            background: AppColors.primarySoft,
            foreground: AppColors.onPrimarySoft,
            icon: Icons.check_rounded,
            text: 'محجوزة · انتهى وقت الإلغاء',
          );
      }
    }
    if (!now.isBefore(offering.bookUntil)) {
      return const _StateBox(background: AppColors.closed, foreground: AppColors.inkMuted, text: 'انتهى وقت الحجز');
    }
    if (offering.soldOut) {
      return const _StateBox(background: AppColors.closed, foreground: AppColors.inkMuted, text: 'نفدت الكمية');
    }
    return FilledButton(
      key: Key('book-${offering.id}'),
      onPressed: () => bookAndTell(context, offering),
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
          Flexible(child: Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: foreground))),
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
