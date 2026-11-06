import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import 'employee_models.dart';
import 'employee_repository.dart';

// All of these dispose with the employee screens, so nothing is left in memory for
// the next person who signs in on the same phone.

final walletProvider = FutureProvider.autoDispose<Wallet>(
  (ref) => ref.watch(employeeRepositoryProvider).wallet(),
);

final offeringsProvider = FutureProvider.autoDispose<List<Offering>>(
  (ref) => ref.watch(employeeRepositoryProvider).offerings(dayOf(DateTime.now())),
);

final activeBookingsProvider = FutureProvider.autoDispose<List<Booking>>(
  (ref) => ref.watch(employeeRepositoryProvider).activeBookings(dayOf(DateTime.now())),
);

final monthBookingsProvider = FutureProvider.autoDispose.family<List<Booking>, DateTime>(
  (ref, month) => ref.watch(employeeRepositoryProvider).monthBookings(month),
);

final transactionsProvider = FutureProvider.autoDispose<List<WalletTx>>(
  (ref) => ref.watch(employeeRepositoryProvider).transactions(),
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
  ref.invalidate(offeringsProvider);
  ref.invalidate(activeBookingsProvider);
  ref.invalidate(monthBookingsProvider);
  ref.invalidate(transactionsProvider);
  ref.invalidate(ratableMealsProvider);
  ref.invalidate(delegatesProvider);
}
