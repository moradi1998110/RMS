import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../admin/admin_models.dart';
import '../employee/employee_models.dart';

const usualPeriods = [MealPeriod.breakfast, MealPeriod.lunch, MealPeriod.dinner];
const ramadanPeriods = [MealPeriod.suhoor, MealPeriod.iftar];

class ManagerFailure implements Exception {
  const ManagerFailure(this.message);

  final String message;

  static const network = ManagerFailure('تعذّر الاتصال. تأكد من الإنترنت ثم حاول مرة أخرى.');
  static const unknown = ManagerFailure('حدث خطأ. حاول مرة أخرى.');

  factory ManagerFailure.fromCode(String code) => ManagerFailure(switch (code) {
        'invalid_times' => timesRule,
        'reason_required' => 'اكتب السبب.',
        'offering_finished' => 'انتهى وقت استلام هذه الوجبة، فلا يمكن إلغاؤها.',
        'offering_not_found' => 'هذه الوجبة غير موجودة في مطعمك.',
        'not_deliverable' => 'هذا الحجز مستلم أو ملغى.',
        'outside_manual_window' => 'لا يمكن تسجيل التسليم في هذا الوقت.',
        'booking_not_found' => 'هذا الحجز غير موجود في مطعمك.',
        'forbidden' => 'ليست لديك صلاحية لهذه العملية.',
        _ => unknown.message,
      });
}

const timesRule = 'يجب أن يكون آخر حجز وآخر إلغاء قبل بدء الاستلام، وأن يبدأ الاستلام قبل نهايته.';

class ManagerMeal {
  const ManagerMeal({
    required this.id,
    required this.name,
    this.description = '',
    this.imagePath,
    required this.price,
    this.hasSalad = false,
    this.hasSoftDrink = false,
    this.hasJuice = false,
    this.hasVegetables = false,
    this.isActive = true,
  });

  final String id;
  final String name;
  final String description;
  final String? imagePath;
  final int price;
  final bool hasSalad;
  final bool hasSoftDrink;
  final bool hasJuice;
  final bool hasVegetables;
  final bool isActive;

  List<String> get extras => [
        if (hasSalad) 'سلطة',
        if (hasVegetables) 'خضراوات',
        if (hasJuice) 'عصير',
        if (hasSoftDrink) 'مشروب غازي',
      ];

  factory ManagerMeal.fromRow(Map<String, dynamic> row) => ManagerMeal(
        id: row['id'] as String,
        name: row['name'] as String,
        description: row['description'] as String? ?? '',
        imagePath: row['image_path'] as String?,
        price: (row['price'] as num).toInt(),
        hasSalad: row['has_salad'] as bool,
        hasSoftDrink: row['has_soft_drink'] as bool,
        hasJuice: row['has_juice'] as bool,
        hasVegetables: row['has_vegetables'] as bool,
        isActive: row['is_active'] as bool,
      );
}

/// What the meal form saves. A null [id] means a new meal.
class MealDraft {
  const MealDraft({
    this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.hasSalad,
    required this.hasSoftDrink,
    required this.hasJuice,
    required this.hasVegetables,
    this.isActive = true,
    this.imagePath,
    this.newImage,
  });

  final String? id;
  final String name;
  final String description;
  final int price;
  final bool hasSalad;
  final bool hasSoftDrink;
  final bool hasJuice;
  final bool hasVegetables;
  final bool isActive;
  final String? imagePath;
  final Uint8List? newImage;
}

String? mealProblem(String name, String price) {
  if (name.trim().isEmpty || (int.tryParse(price) ?? 0) <= 0) return 'اكتب اسم الوجبة وسعرها أولاً.';
  return null;
}

class ScheduleRow {
  const ScheduleRow({
    required this.id,
    required this.mealId,
    required this.mealName,
    required this.period,
    required this.isRamadan,
    required this.weekdays,
    required this.weeklyRepeat,
    required this.start,
    this.end,
  });

  final String id;
  final String mealId;
  final String mealName;
  final MealPeriod period;
  final bool isRamadan;
  final List<int> weekdays;
  final bool weeklyRepeat;
  final DateTime start;
  final DateTime? end;

  factory ScheduleRow.fromRow(Map<String, dynamic> row) => ScheduleRow(
        id: row['id'] as String,
        mealId: row['meal_id'] as String,
        mealName: (row['meals'] as Map<String, dynamic>)['name'] as String,
        period: MealPeriod.values.byName(row['period'] as String),
        isRamadan: row['season'] == 'ramadan',
        weekdays: (row['weekdays'] as List).cast<int>(),
        weeklyRepeat: row['repeat_type'] == 'weekly',
        start: DateTime.parse(row['start_date'] as String),
        end: row['end_date'] == null ? null : DateTime.parse(row['end_date'] as String),
      );

  /// Whether this schedule still serves the given day of the week from today on.
  bool serves(int dayOfWeek, DateTime today) {
    if (!weekdays.contains(dayOfWeek)) return false;
    if (end == null) return true;
    final from = start.isAfter(today) ? start : today;
    for (var day = from; !day.isAfter(end!) && day.difference(from).inDays < 7; day = addDays(day, 1)) {
      if (day.weekday % 7 == dayOfWeek) return true;
    }
    return false;
  }
}

/// "This week only" schedules from last week that have no copy yet, moved one week on.
/// Schedules repeating every week need no copy.
List<ScheduleRow> copiesFromLastWeek(List<ScheduleRow> schedules, DateTime today) {
  final thisWeek = weekStartOf(today);
  final lastWeek = addDays(thisWeek, -7);
  final copies = <ScheduleRow>[];
  for (final row in schedules) {
    if (row.weeklyRepeat || row.start.isBefore(lastWeek) || !row.start.isBefore(thisWeek)) continue;
    final moved = addDays(row.start, 7);
    final exists = schedules.any((other) =>
        !other.weeklyRepeat && other.mealId == row.mealId && other.period == row.period && other.start == moved);
    if (exists) continue;
    copies.add(ScheduleRow(
      id: '',
      mealId: row.mealId,
      mealName: row.mealName,
      period: row.period,
      isRamadan: row.isRamadan,
      weekdays: row.weekdays,
      weeklyRepeat: false,
      start: moved,
      end: row.end == null ? null : addDays(row.end!, 7),
    ));
  }
  return copies;
}

class TimeRule {
  const TimeRule({
    required this.period,
    required this.bookDay,
    required this.book,
    required this.cancelDay,
    required this.cancel,
    required this.fromDay,
    required this.from,
    required this.untilDay,
    required this.until,
  });

  final MealPeriod period;
  final int bookDay;
  final TimeOfDay book;
  final int cancelDay;
  final TimeOfDay cancel;
  final int fromDay;
  final TimeOfDay from;
  final int untilDay;
  final TimeOfDay until;

  static TimeOfDay _time(Object? value) {
    final parts = (value as String).split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  factory TimeRule.fromRow(Map<String, dynamic> row) => TimeRule(
        period: MealPeriod.values.byName(row['period'] as String),
        bookDay: row['book_day_offset'] as int,
        book: _time(row['book_time']),
        cancelDay: row['cancel_day_offset'] as int,
        cancel: _time(row['cancel_time']),
        fromDay: row['pickup_from_day_offset'] as int,
        from: _time(row['pickup_from_time']),
        untilDay: row['pickup_until_day_offset'] as int,
        until: _time(row['pickup_until_time']),
      );

  static int _minutes(int day, TimeOfDay time) => day * 1440 + time.hour * 60 + time.minute;

  /// Same rule as the server and the table constraints.
  bool get isValid =>
      _minutes(bookDay, book) <= _minutes(fromDay, from) &&
      _minutes(cancelDay, cancel) <= _minutes(fromDay, from) &&
      _minutes(fromDay, from) < _minutes(untilDay, until);
}

/// A day offset and a time as a sentence, told from the day of the meal.
String ruleText(int day, TimeOfDay time) {
  final base = DateTime(2000, 6, 15);
  return deadlineText(DateTime(base.year, base.month, base.day + day, time.hour, time.minute), base);
}

class TodayMeal {
  const TodayMeal({
    required this.offeringId,
    required this.name,
    required this.period,
    required this.pickupFrom,
    required this.pickupUntil,
    this.waiting = 0,
    this.collected = 0,
    this.notCollected = 0,
  });

  final String offeringId;
  final String name;
  final MealPeriod period;
  final DateTime pickupFrom;
  final DateTime pickupUntil;
  final int waiting;
  final int collected;
  final int notCollected;

  int get booked => waiting + collected + notCollected;

  String whenText(DateTime now) {
    final label = period.label;
    if (now.isBefore(pickupFrom)) return '$label · يبدأ الاستلام ${clock(pickupFrom)}';
    if (now.isBefore(pickupUntil)) return '$label · الاستلام حتى ${clock(pickupUntil)}';
    return '$label · انتهى الاستلام ${clock(pickupUntil)}';
  }
}

class TodayBooking {
  const TodayBooking({required this.id, required this.employeeName, required this.status});

  final String id;
  final String employeeName;
  final BookingStatus status;

  factory TodayBooking.fromRow(Map<String, dynamic> row) => TodayBooking(
        id: row['id'] as String,
        employeeName: (row['profiles'] as Map<String, dynamic>?)?['full_name'] as String? ?? 'موظف',
        status: parseBookingStatus(row['status'] as String),
      );
}

enum ScanTone { deliver, refuse, wait }

class ScanResult {
  const ScanResult({
    required this.ok,
    this.reason,
    this.ownerName,
    this.holderName,
    this.mealName,
    this.pickedUpAt,
    this.pickedUpBy,
    this.pickupFrom,
  });

  final bool ok;
  final String? reason;
  final String? ownerName;
  final String? holderName;
  final String? mealName;
  final DateTime? pickedUpAt;
  final String? pickedUpBy;
  final DateTime? pickupFrom;

  factory ScanResult.fromJson(Map<String, dynamic> json) {
    DateTime? time(String key) => json[key] == null ? null : DateTime.parse(json[key] as String).toLocal();
    return ScanResult(
      ok: json['ok'] as bool,
      reason: json['reason'] as String?,
      ownerName: json['owner_name'] as String?,
      holderName: json['holder_name'] as String?,
      mealName: json['meal_name'] as String?,
      pickedUpAt: time('picked_up_at'),
      pickedUpBy: json['picked_up_by_name'] as String?,
      pickupFrom: time('pickup_from'),
    );
  }

  ScanTone get tone {
    if (ok) return ScanTone.deliver;
    return reason == 'not_started' ? ScanTone.wait : ScanTone.refuse;
  }

  String get title => switch (tone) {
        ScanTone.deliver => 'سلّم الوجبة',
        ScanTone.refuse => 'لا تسلّم',
        ScanTone.wait => 'لم يبدأ الوقت',
      };

  String get line1 {
    if (ok) return ownerName ?? '';
    return switch (reason) {
      'already_picked_up' => 'استُلمت سابقاً',
      'cancelled' => 'هذا الحجز ملغى',
      'wrong_restaurant' => 'الوجبة من مطعم آخر',
      'expired' => 'انتهى وقت الاستلام',
      'not_started' => pickupFrom == null ? 'الاستلام لم يبدأ' : 'الاستلام يبدأ ${clock(pickupFrom!)}',
      _ => 'رمز غير صالح',
    };
  }

  String get line2 {
    if (ok) {
      final meal = mealName ?? '';
      return holderName != null && holderName != ownerName ? '$meal\nيستلمها بالنيابة: $holderName' : meal;
    }
    return switch (reason) {
      'already_picked_up' => [
          if (pickedUpAt != null) 'الساعة ${clock(pickedUpAt!)}',
          if (pickedUpBy != null) 'بواسطة $pickedUpBy',
        ].join(' '),
      'cancelled' => 'لا يوجد مبلغ مخصوم عليه',
      'wrong_restaurant' => 'وجّه الموظف إلى مطعمه',
      'expired' => 'لا يمكن تسليمها الآن',
      'not_started' => 'اطلب منه العودة في الموعد',
      _ => 'تأكد من الرمز واطلب رمزاً آخر',
    };
  }
}

/// A week's rows with what only the restaurant report needs.
class ManagerWeek {
  const ManagerWeek({required this.summary, required this.topMeals, required this.due});

  final WeekSummary summary;
  final List<(String, int)> topMeals;

  /// What collected and uncollected meals bring in: both are deducted the same.
  final int due;

  factory ManagerWeek.from(DateTime start, List<ManagerWeekRow> rows) {
    final counts = <String, int>{};
    var due = 0;
    for (final row in rows) {
      final status = row.row.status;
      if (status == BookingStatus.cancelled || status == BookingStatus.cancelledByRestaurant) continue;
      counts[row.mealName] = (counts[row.mealName] ?? 0) + 1;
      if (status != BookingStatus.booked) due += row.amount;
    }
    final top = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return ManagerWeek(
      summary: WeekSummary.from(start, [for (final row in rows) row.row]),
      topMeals: [for (final entry in top.take(5)) (entry.key, entry.value)],
      due: due,
    );
  }
}

class ManagerWeekRow {
  const ManagerWeekRow({required this.row, required this.mealName, required this.amount});

  final WeekRow row;
  final String mealName;
  final int amount;

  factory ManagerWeekRow.fromRow(Map<String, dynamic> json) {
    final offering = json['meal_offerings'] as Map<String, dynamic>;
    return ManagerWeekRow(
      row: WeekRow.fromRow(json),
      mealName: (offering['meals'] as Map<String, dynamic>)['name'] as String,
      amount: (json['amount'] as num).toInt(),
    );
  }
}
