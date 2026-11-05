import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'admin_models.dart';
import 'admin_repository.dart';

// All of these dispose with the admin screens, so nothing is left in memory for the
// next person who signs in on the same phone.

final usersProvider = FutureProvider.autoDispose<List<AdminUser>>(
  (ref) => ref.watch(adminRepositoryProvider).users(),
);

final placesProvider = FutureProvider.autoDispose<List<Place>>(
  (ref) => ref.watch(adminRepositoryProvider).places(),
);

final ramadanProvider = FutureProvider.autoDispose<List<RamadanPeriod>>(
  (ref) => ref.watch(adminRepositoryProvider).ramadanPeriods(),
);

final ledgerProvider = FutureProvider.autoDispose<List<LedgerLine>>(
  (ref) => ref.watch(adminRepositoryProvider).ledger(),
);

final weekSummaryProvider = FutureProvider.autoDispose<WeekSummary>((ref) async {
  final start = weekStartOf(DateTime.now());
  return WeekSummary.from(start, await ref.watch(adminRepositoryProvider).weekRows(start));
});

final adminTabProvider = StateProvider.autoDispose<int>((ref) => 0);

void refreshAdminData(WidgetRef ref) {
  ref.invalidate(usersProvider);
  ref.invalidate(placesProvider);
  ref.invalidate(ramadanProvider);
  ref.invalidate(ledgerProvider);
  ref.invalidate(weekSummaryProvider);
}
