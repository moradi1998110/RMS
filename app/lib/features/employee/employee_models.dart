import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';

/// In the order of the day. Ramadan replaces the three usual periods with two.
enum MealPeriod {
  suhoor('السحور', AppColors.dinner, 0),
  breakfast('الفطور', AppColors.breakfast, 0),
  lunch('الغداء', AppColors.lunch, 1),
  iftar('الإفطار', AppColors.breakfast, 2),
  dinner('العشاء', AppColors.dinner, 2);

  const MealPeriod(this.label, this.color, this.calendarLine);

  final String label;
  final Color color;

  /// Which of a calendar day's three lines shows this period.
  final int calendarLine;
}

class Offering {
  const Offering({
    required this.id,
    required this.mealId,
    required this.name,
    this.description = '',
    this.imagePath,
    this.extras = const [],
    required this.serviceDate,
    required this.period,
    required this.price,
    required this.bookUntil,
    required this.cancelUntil,
    required this.pickupFrom,
    required this.pickupUntil,
    this.capacity,
    this.bookedCount = 0,
  });

  final String id;
  final String mealId;
  final String name;
  final String description;
  final String? imagePath;
  final List<String> extras;
  final DateTime serviceDate;
  final MealPeriod period;
  final int price;
  final DateTime bookUntil;
  final DateTime cancelUntil;
  final DateTime pickupFrom;
  final DateTime pickupUntil;
  final int? capacity;
  final int bookedCount;

  bool get soldOut => capacity != null && bookedCount >= capacity!;

  bool isOpenAt(DateTime now) => now.isBefore(bookUntil) && !soldOut;

  factory Offering.fromRow(Map<String, dynamic> row) {
    final meal = row['meals'] as Map<String, dynamic>;
    return Offering(
      id: row['id'] as String,
      mealId: row['meal_id'] as String,
      name: meal['name'] as String,
      description: meal['description'] as String? ?? '',
      imagePath: meal['image_path'] as String?,
      extras: [
        if (meal['has_salad'] == true) 'سلطة',
        if (meal['has_vegetables'] == true) 'خضراوات',
        if (meal['has_juice'] == true) 'عصير',
        if (meal['has_soft_drink'] == true) 'مشروب غازي',
      ],
      serviceDate: DateTime.parse(row['service_date'] as String),
      period: MealPeriod.values.byName(row['period'] as String),
      price: (row['price'] as num).toInt(),
      bookUntil: DateTime.parse(row['book_until'] as String).toLocal(),
      cancelUntil: DateTime.parse(row['cancel_until'] as String).toLocal(),
      pickupFrom: DateTime.parse(row['pickup_from'] as String).toLocal(),
      pickupUntil: DateTime.parse(row['pickup_until'] as String).toLocal(),
      capacity: row['capacity'] as int?,
      bookedCount: row['booked_count'] as int? ?? 0,
    );
  }
}

enum BookingStatus { booked, cancelled, cancelledByRestaurant, pickedUp, noShow }

BookingStatus parseBookingStatus(String value) => switch (value) {
      'booked' => BookingStatus.booked,
      'cancelled' => BookingStatus.cancelled,
      'cancelled_by_restaurant' => BookingStatus.cancelledByRestaurant,
      'picked_up' => BookingStatus.pickedUp,
      'no_show' => BookingStatus.noShow,
      _ => throw FormatException('Unknown booking status: $value'),
    };

class Booking {
  const Booking({
    required this.id,
    required this.offeringId,
    required this.mealId,
    required this.mealName,
    required this.serviceDate,
    required this.period,
    required this.amount,
    required this.status,
    required this.cancelUntil,
    required this.pickupFrom,
    required this.pickupUntil,
  });

  final String id;
  final String offeringId;
  final String mealId;
  final String mealName;
  final DateTime serviceDate;
  final MealPeriod period;
  final int amount;
  final BookingStatus status;
  final DateTime cancelUntil;
  final DateTime pickupFrom;
  final DateTime pickupUntil;

  bool get isLive => status == BookingStatus.booked;

  bool canCancelAt(DateTime now) => isLive && now.isBefore(cancelUntil);

  /// The server sends a code only inside this window.
  bool pickupOpenAt(DateTime now) => isLive && !now.isBefore(pickupFrom) && now.isBefore(pickupUntil);

  factory Booking.fromRow(Map<String, dynamic> row) {
    final offering = row['meal_offerings'] as Map<String, dynamic>;
    final meal = offering['meals'] as Map<String, dynamic>;
    return Booking(
      id: row['id'] as String,
      offeringId: row['offering_id'] as String,
      mealId: offering['meal_id'] as String,
      mealName: meal['name'] as String,
      serviceDate: DateTime.parse(offering['service_date'] as String),
      period: MealPeriod.values.byName(offering['period'] as String),
      amount: (row['amount'] as num).toInt(),
      status: parseBookingStatus(row['status'] as String),
      cancelUntil: DateTime.parse(offering['cancel_until'] as String).toLocal(),
      pickupFrom: DateTime.parse(offering['pickup_from'] as String).toLocal(),
      pickupUntil: DateTime.parse(offering['pickup_until'] as String).toLocal(),
    );
  }
}

class Wallet {
  const Wallet({required this.available, required this.held});

  final int available;
  final int held;

  factory Wallet.fromRow(Map<String, dynamic> row) => Wallet(
        available: (row['available'] as num).toInt(),
        held: (row['held'] as num).toInt(),
      );
}

enum WalletTxType { topup, hold, release, settlePickup, settleNoShow, adjustment }

WalletTxType _walletTxType(String value) => switch (value) {
      'topup' => WalletTxType.topup,
      'hold' => WalletTxType.hold,
      'release' => WalletTxType.release,
      'settle_pickup' => WalletTxType.settlePickup,
      'settle_no_show' => WalletTxType.settleNoShow,
      'adjustment' => WalletTxType.adjustment,
      _ => throw FormatException('Unknown transaction type: $value'),
    };

class WalletTx {
  const WalletTx({
    required this.type,
    required this.availableDelta,
    required this.heldDelta,
    this.note,
    this.mealName,
    required this.createdAt,
  });

  final WalletTxType type;
  final int availableDelta;
  final int heldDelta;
  final String? note;
  final String? mealName;
  final DateTime createdAt;

  factory WalletTx.fromRow(Map<String, dynamic> row) {
    final booking = row['bookings'] as Map<String, dynamic>?;
    final offering = booking?['meal_offerings'] as Map<String, dynamic>?;
    final meal = offering?['meals'] as Map<String, dynamic>?;
    return WalletTx(
      type: _walletTxType(row['type'] as String),
      availableDelta: (row['available_delta'] as num).toInt(),
      heldDelta: (row['held_delta'] as num).toInt(),
      note: row['note'] as String?,
      mealName: meal?['name'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
    );
  }

  String get text {
    final meal = mealName ?? 'وجبة';
    return switch (type) {
      WalletTxType.topup => 'شحن من مسؤول النظام',
      WalletTxType.hold => 'حجز $meal',
      WalletTxType.release => 'إرجاع إلغاء $meal',
      WalletTxType.settlePickup => 'استلمت $meal، من المبلغ المحجوز',
      WalletTxType.settleNoShow => 'لم تُستلم $meal، واستُقطع من المبلغ المحجوز',
      WalletTxType.adjustment => 'تصحيح من مسؤول النظام: ${note ?? ''}',
    };
  }

  /// A settlement only closes money already held, so it gets no sign: it does not
  /// reduce the balance a second time.
  String get amountText {
    if (availableDelta == 0) return money(heldDelta.abs());
    return availableDelta > 0 ? '+${money(availableDelta)}' : money(availableDelta);
  }

  bool get isGain => availableDelta > 0;
}

class BookResult {
  const BookResult({required this.count, required this.total});

  final int count;
  final int total;
}

class CancelResult {
  const CancelResult({required this.count, required this.refunded});

  final int count;
  final int refunded;
}

class EmployeeFailure implements Exception {
  const EmployeeFailure(this.message);

  final String message;

  static const network = EmployeeFailure('تعذّر الاتصال. تأكد من الإنترنت ثم حاول مرة أخرى.');
  static const unknown = EmployeeFailure('حدث خطأ. حاول مرة أخرى.');

  /// Turns a server rejection (a stable code plus JSON details) into a plain sentence.
  factory EmployeeFailure.fromServer(String code, Map<String, dynamic> details) {
    String day() {
      final date = details['service_date'] as String?;
      return date == null ? '' : ' ${longDate(DateTime.parse(date))}';
    }

    return EmployeeFailure(switch (code) {
      'insufficient_balance' => 'ينقصك ${dinars((details['shortfall'] as num? ?? 0).toInt())}. راجع مسؤول النظام لشحن رصيدك.',
      'booking_closed' => 'انتهى وقت حجز وجبة${day()}. لم يُخصم شيء.',
      'sold_out' => 'نفدت كمية وجبة${day()}. لم يُخصم شيء.',
      'already_booked' => 'لديك حجز لوجبة${day()}. لم يُخصم شيء.',
      'offering_cancelled' => 'ألغى المطعم وجبة${day()}. لم يُخصم شيء.',
      'cancel_deadline_passed' => 'انتهى وقت إلغاء هذه الوجبة.',
      'not_cancellable' => 'لا يمكن إلغاء هذا الحجز الآن.',
      'rating_closed' => 'انتهى وقت تقييم هذه الوجبة.',
      'rating_not_open' => 'يبدأ تقييم الوجبة بعد ساعة من استلامها.',
      'already_rated' => 'قيّمت هذه الوجبة سابقاً.',
      'not_ratable' => 'لا يمكن تقييم هذه الوجبة.',
      'invalid_stars' => 'اختر عدد النجوم.',
      'comment_too_long' => 'التعليق طويل. اختصره إلى 500 حرف.',
      'colleague_not_found' => 'لم نجد زميلاً بهذا الاسم في مطعمك. تأكد من اسم المستخدم.',
      'cannot_delegate_to_self' => 'هذا اسم المستخدم الخاص بك. اكتب اسم زميلك.',
      'too_many_delegates' => 'يمكنك اختيار $maxDelegates زملاء كحد أقصى. ألغِ أحدهم أولاً.',
      'too_many_attempts' => 'محاولات كثيرة. انتظر 10 دقائق ثم حاول مرة أخرى.',
      'delegation_not_found' => 'هذا الزميل لم يعد في قائمتك.',
      _ => unknown.message,
    });
  }
}

/// Quick reasons an employee can tap instead of typing. Names match the server.
enum RatingTag {
  tasty('tasty', 'لذيذة'),
  goodPortion('good_portion', 'الكمية مناسبة'),
  smallPortion('small_portion', 'الكمية قليلة'),
  cold('cold', 'باردة'),
  delayed('late', 'تأخر التسليم'),
  clean('clean', 'نظافة ممتازة');

  const RatingTag(this.code, this.label);

  final String code;
  final String label;

  static RatingTag? fromCode(String code) => values.where((tag) => tag.code == code).firstOrNull;
}

/// What each number of stars means, so a choice is never a guess.
String starsWord(int stars) => const ['', 'سيئة جداً', 'سيئة', 'مقبولة', 'جيدة', 'ممتازة'][stars];

/// A collected meal that can be rated right now.
class RatableMeal {
  const RatableMeal({
    required this.bookingId,
    required this.mealName,
    required this.period,
    required this.serviceDate,
    required this.pickedUpAt,
    required this.rateUntil,
  });

  final String bookingId;
  final String mealName;
  final MealPeriod period;
  final DateTime serviceDate;
  final DateTime pickedUpAt;
  final DateTime rateUntil;

  factory RatableMeal.fromRow(Map<String, dynamic> row) => RatableMeal(
        bookingId: row['booking_id'] as String,
        mealName: row['meal_name'] as String,
        period: MealPeriod.values.byName(row['period'] as String),
        serviceDate: DateTime.parse(row['service_date'] as String),
        pickedUpAt: DateTime.parse(row['picked_up_at'] as String).toLocal(),
        rateUntil: DateTime.parse(row['rate_until'] as String).toLocal(),
      );
}

/// Later days of the same meal in the same month that can still be booked, starting
/// with the chosen day. Mirrors what the cancel option below offers in reverse.
List<Offering> bookableSeries(Offering pick, List<Offering> offerings, List<Booking> active, DateTime now) {
  final held = {for (final booking in active) booking.offeringId};
  return offerings
      .where((offering) =>
          offering.mealId == pick.mealId &&
          offering.period == pick.period &&
          !offering.serviceDate.isBefore(pick.serviceDate) &&
          sameMonth(offering.serviceDate, pick.serviceDate) &&
          offering.serviceDate.weekday == pick.serviceDate.weekday &&
          offering.isOpenAt(now) &&
          !held.contains(offering.id))
      .toList()
    ..sort((a, b) => a.serviceDate.compareTo(b.serviceDate));
}

class CancelSeries {
  const CancelSeries({required this.cancellable, required this.locked});

  /// Later meals that a series cancel would include, without the chosen booking.
  final List<Booking> cancellable;

  /// Later meals past their own deadline, which it would leave in place.
  final int locked;
}

/// Must match what cancel_booking_series does on the server.
CancelSeries cancelSeriesFor(Booking target, List<Booking> active, DateTime now) {
  final later = active.where((booking) =>
      booking.id != target.id &&
      booking.isLive &&
      booking.mealId == target.mealId &&
      booking.period == target.period &&
      !booking.serviceDate.isBefore(target.serviceDate) &&
      sameMonth(booking.serviceDate, target.serviceDate) &&
      booking.serviceDate.weekday == target.serviceDate.weekday);
  final cancellable = later.where((booking) => booking.canCancelAt(now)).toList();
  return CancelSeries(cancellable: cancellable, locked: later.length - cancellable.length);
}

Booking? nextBooking(List<Booking> active, DateTime now) {
  final upcoming = active.where((booking) => booking.isLive && booking.pickupUntil.isAfter(now)).toList()
    ..sort((a, b) => a.pickupFrom.compareTo(b.pickupFrom));
  return upcoming.isEmpty ? null : upcoming.first;
}

/// The month grid: blanks up to the first day's column, then one entry per day.
List<DateTime?> calendarCells(DateTime month) {
  final first = DateTime(month.year, month.month);
  final blanks = (first.weekday % 7 + 1) % 7;
  final length = DateTime(month.year, month.month + 1, 0).day;
  return [
    for (var i = 0; i < blanks; i++) null,
    for (var day = 1; day <= length; day++) DateTime(month.year, month.month, day),
  ];
}

/// One pickup code the user can show: for their own meal or a colleague's.
class Pickup {
  const Pickup({
    required this.bookingId,
    required this.token,
    required this.shortCode,
    required this.isMine,
    required this.ownerName,
    required this.mealName,
    required this.pickupFrom,
    required this.pickupUntil,
    this.pickedUpAt,
    this.pickedUpByName,
  });

  final String bookingId;

  /// Null once the meal is collected: no code is sent for it any more.
  final String? token;
  final String? shortCode;
  final bool isMine;
  final String ownerName;
  final String mealName;
  final DateTime pickupFrom;
  final DateTime pickupUntil;
  final DateTime? pickedUpAt;
  final String? pickedUpByName;

  bool get collected => token == null;

  factory Pickup.fromRow(Map<String, dynamic> row) => Pickup(
        bookingId: row['booking_id'] as String,
        token: row['token'] as String?,
        shortCode: row['short_code'] as String?,
        isMine: row['is_mine'] as bool,
        ownerName: row['owner_name'] as String,
        mealName: row['meal_name'] as String,
        pickupFrom: DateTime.parse(row['pickup_from'] as String).toLocal(),
        pickupUntil: DateTime.parse(row['pickup_until'] as String).toLocal(),
        pickedUpAt: row['picked_up_at'] == null ? null : DateTime.parse(row['picked_up_at'] as String).toLocal(),
        pickedUpByName: row['picked_up_by_name'] as String?,
      );
}

/// A colleague who can collect any of my meals once its pickup starts.
class Delegate {
  const Delegate({required this.delegationId, required this.username, required this.fullName, this.department});

  final String delegationId;
  final String username;
  final String fullName;
  final String? department;

  /// Two letters for the small round picture: the first of each of the first two names.
  String get initials {
    final words = fullName.trim().split(RegExp(r'\s+')).where((word) => word.isNotEmpty).toList();
    if (words.isEmpty) return '؟';
    return words.take(2).map((word) => String.fromCharCode(word.runes.first)).join();
  }

  factory Delegate.fromRow(Map<String, dynamic> row) => Delegate(
        delegationId: row['delegation_id'] as String,
        username: row['username'] as String,
        fullName: row['full_name'] as String,
        department: row['department'] as String?,
      );
}

/// A colleague found by username, shown so the employee can check before choosing.
class Colleague {
  const Colleague({required this.username, required this.fullName, this.department});

  final String username;
  final String fullName;
  final String? department;

  factory Colleague.fromRow(Map<String, dynamic> row) => Colleague(
        username: row['username'] as String,
        fullName: row['full_name'] as String,
        department: row['department'] as String?,
      );
}

/// At most this many colleagues at once; the server holds the same limit.
const maxDelegates = 5;
