import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import 'employee_models.dart';
import 'employee_repository.dart';

// All of these dispose with the employee screens, so nothing is left in memory for
// the next person who signs in on the same phone.

final walletProvider = FutureProvider.autoDispose<Wallet>(
  (ref) => ref.watch(employeeRepositoryProvider).wallet(),
);

// Each page asks only for the days it shows: the meals page today, the calendar the
// month on screen. A month of one restaurant is a few hundred rows at most.
final todayOfferingsProvider = FutureProvider.autoDispose<List<Offering>>((ref) {
  final today = dayOf(DateTime.now());
  return ref.watch(employeeRepositoryProvider).offerings(today, today);
});

/// The month's meals from today on; a month already over has nothing to book.
final monthOfferingsProvider = FutureProvider.autoDispose.family<List<Offering>, DateTime>((ref, month) async {
  final today = dayOf(DateTime.now());
  final last = DateTime(month.year, month.month + 1, 0);
  if (last.isBefore(today)) return const [];
  final first = DateTime(month.year, month.month);
  return ref.watch(employeeRepositoryProvider).offerings(first.isBefore(today) ? today : first, last);
});

final activeBookingsProvider = FutureProvider.autoDispose<List<Booking>>(
  (ref) => ref.watch(employeeRepositoryProvider).activeBookings(dayOf(DateTime.now())),
);

final monthBookingsProvider = FutureProvider.autoDispose.family<List<Booking>, DateTime>(
  (ref, month) => ref.watch(employeeRepositoryProvider).monthBookings(month),
);

/// How many movements the account page shows; "show more" adds a page.
final transactionsLimitProvider = StateProvider.autoDispose<int>((ref) => transactionsPage);

/// One more than shown is asked for, to know whether a "show more" button is needed.
final transactionsProvider = FutureProvider.autoDispose<List<WalletTx>>(
  (ref) => ref.watch(employeeRepositoryProvider).transactions(limit: ref.watch(transactionsLimitProvider) + 1),
);

final ratableMealsProvider = FutureProvider.autoDispose<List<RatableMeal>>(
  (ref) => ref.watch(employeeRepositoryProvider).ratableMeals(),
);

final delegatesProvider = FutureProvider.autoDispose<List<Delegate>>(
  (ref) => ref.watch(employeeRepositoryProvider).delegates(),
);

final employeeTabProvider = StateProvider.autoDispose<int>((ref) => 0);

final calendarMonthProvider = StateProvider.autoDispose<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month);
});

void refreshEmployeeData(WidgetRef ref) {
  ref.invalidate(walletProvider);
  ref.invalidate(todayOfferingsProvider);
  ref.invalidate(monthOfferingsProvider);
  ref.invalidate(activeBookingsProvider);
  ref.invalidate(monthBookingsProvider);
  ref.invalidate(transactionsProvider);
  ref.invalidate(ratableMealsProvider);
  ref.invalidate(delegatesProvider);
}
