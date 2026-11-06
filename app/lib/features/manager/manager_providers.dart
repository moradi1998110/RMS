import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../admin/admin_models.dart';
import 'manager_models.dart';
import 'manager_repository.dart';

// All of these dispose with the manager screens, so nothing is left in memory for the
// next person who signs in on the same phone.

final mealsProvider = FutureProvider.autoDispose<List<ManagerMeal>>(
  (ref) => ref.watch(managerRepositoryProvider).meals(),
);

final schedulesProvider = FutureProvider.autoDispose<List<ScheduleRow>>(
  (ref) => ref.watch(managerRepositoryProvider).schedules(),
);

final timeRulesProvider = FutureProvider.autoDispose<List<TimeRule>>(
  (ref) => ref.watch(managerRepositoryProvider).timeRules(),
);

final todayProvider = FutureProvider.autoDispose<List<TodayMeal>>(
  (ref) => ref.watch(managerRepositoryProvider).today(),
);

final managerWeekProvider = FutureProvider.autoDispose<ManagerWeek>(
  (ref) => ref.watch(managerRepositoryProvider).week(weekStartOf(DateTime.now())),
);

final managerRatingsProvider = FutureProvider.autoDispose<RatingSummary>((ref) async {
  final ratings = await ref.watch(managerRepositoryProvider).ratings(weekStartOf(DateTime.now()));
  return RatingSummary.from(ratings);
});

final offeringBookingsProvider = FutureProvider.autoDispose.family<List<TodayBooking>, String>(
  (ref, offeringId) => ref.watch(managerRepositoryProvider).bookingsOf(offeringId),
);

final photoPickerProvider = Provider<PhotoPicker>((ref) => (fromCamera) async {
      // Small enough to upload quickly over a weak connection.
      final file = await ImagePicker().pickImage(
        source: fromCamera ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 1024,
        imageQuality: 70,
      );
      return file?.readAsBytes();
    });

void refreshManagerData(WidgetRef ref) {
  ref.invalidate(mealsProvider);
  ref.invalidate(schedulesProvider);
  ref.invalidate(timeRulesProvider);
  ref.invalidate(todayProvider);
  ref.invalidate(managerWeekProvider);
  ref.invalidate(managerRatingsProvider);
  ref.invalidate(offeringBookingsProvider);
}
