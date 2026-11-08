import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rms/core/format.dart';
import 'package:rms/core/theme.dart';
import 'package:rms/features/employee/account_page.dart';
import 'package:rms/features/employee/bookings_page.dart';
import 'package:rms/features/employee/employee_models.dart';
import 'package:rms/features/employee/employee_repository.dart';
import 'package:rms/features/employee/meals_page.dart';
import 'package:rms/features/employee/rate_sheet.dart';
import 'package:rms/shared/notice.dart';

import 'fake_employee_repository.dart';

final _soon = DateTime.now().add(const Duration(hours: 1));
final _past = DateTime.now().subtract(const Duration(hours: 1));

/// The first Monday of next month, so weekly repeats always stay inside one month.
DateTime _firstMondayNextMonth() {
  final now = DateTime.now();
  var day = DateTime(now.year, now.month + 1);
  while (day.weekday != DateTime.monday) {
    day = addDays(day, 1);
  }
  return day;
}

Offering _offering(
  String id,
  DateTime day, {
  String mealId = 'lunch-meal',
  String name = 'رز ودجاج',
  MealPeriod period = MealPeriod.lunch,
  int price = 6000,
  DateTime? bookUntil,
  int? capacity,
  int bookedCount = 0,
}) {
  return Offering(
    id: id,
    mealId: mealId,
    name: name,
    description: 'رز بسمتي',
    extras: const ['سلطة', 'عصير'],
    serviceDate: day,
    period: period,
    price: price,
    bookUntil: bookUntil ?? _soon,
    cancelUntil: day.add(const Duration(hours: 8)),
    pickupFrom: day.add(const Duration(hours: 12)),
    pickupUntil: day.add(const Duration(hours: 14, minutes: 30)),
    capacity: capacity,
    bookedCount: bookedCount,
  );
}

Booking _booking(
  String id,
  DateTime day, {
  String offeringId = 'other',
  String mealId = 'lunch-meal',
  BookingStatus status = BookingStatus.booked,
  DateTime? cancelUntil,
  MealPeriod period = MealPeriod.lunch,
}) {
  return Booking(
    id: id,
    offeringId: offeringId,
    mealId: mealId,
    mealName: 'رز ودجاج',
    serviceDate: day,
    period: period,
    amount: 6000,
    status: status,
    cancelUntil: cancelUntil ?? _soon,
    pickupFrom: day.add(const Duration(hours: 12)),
    pickupUntil: day.add(const Duration(hours: 14, minutes: 30)),
  );
}

Future<void> _pumpPage(WidgetTester tester, Widget page, FakeEmployeeRepository repository, {double height = 1100}) async {
  tester.view.physicalSize = Size(1170, height * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [employeeRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp(
        theme: appTheme(),
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(body: page),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String _text(WidgetTester tester, String key) => tester.widget<Text>(find.byKey(Key(key))).data!;

Future<void> _closeNotice(WidgetTester tester) async {
  await tester.pump(noticeDuration);
  await tester.pumpAndSettle();
}

void main() {
  bookingScenarios();

  group('wording', () {
    test('money is grouped', () {
      expect(money(0), '0');
      expect(money(750), '750');
      expect(money(13500), '13,500');
      expect(money(1250000), '1,250,000');
      expect(money(-7500), '-7,500');
    });

    test('times read as a person says them', () {
      expect(clock(DateTime(2026, 11, 5, 8)), '8:00 صباحاً');
      expect(clock(DateTime(2026, 11, 5, 0, 30)), '12:30 صباحاً');
      expect(clock(DateTime(2026, 11, 5, 14)), '2:00 ظهراً');
      expect(clock(DateTime(2026, 11, 5, 18, 5)), '6:05 مساءً');
      expect(clockRange(DateTime(2026, 11, 5, 12), DateTime(2026, 11, 5, 14, 30)), 'من 12:00 إلى 2:30 ظهراً');
      expect(clockRange(DateTime(2026, 11, 5, 11), DateTime(2026, 11, 5, 14)), 'من 11:00 صباحاً إلى 2:00 ظهراً');
    });

    test('deadlines are told from the day of the meal', () {
      final meal = DateTime(2026, 11, 5);
      expect(deadlineText(DateTime(2026, 11, 5, 8), meal), '8:00 صباحاً يوم الوجبة');
      expect(deadlineText(DateTime(2026, 11, 4, 22), meal), 'الليلة السابقة 10:00 مساءً');
      expect(deadlineText(DateTime(2026, 11, 4, 9), meal), 'اليوم السابق 9:00 صباحاً');
    });

    test('days have names', () {
      final today = DateTime(2026, 11, 5);
      expect(relativeDay(today, today), 'اليوم');
      expect(relativeDay(DateTime(2026, 11, 6), today), 'غداً');
      expect(relativeDay(DateTime(2026, 11, 9), today), 'الاثنين 9 تشرين الثاني');
    });

    test('counts agree with the number', () {
      expect(mealCount(2), 'وجبتان');
      expect(mealCountObject(2), 'وجبتين');
      expect(mealCount(4), '4 وجبات');
    });
  });

  group('server data', () {
    test('an offering row is read in local time', () {
      final offering = Offering.fromRow({
        'id': 'o1',
        'meal_id': 'm1',
        'service_date': '2026-11-09',
        'period': 'lunch',
        'price': 6000,
        'book_until': '2026-11-08T17:00:00+00:00',
        'cancel_until': '2026-11-09T05:00:00+00:00',
        'pickup_from': '2026-11-09T09:00:00+00:00',
        'pickup_until': '2026-11-09T11:30:00+00:00',
        'capacity': 2,
        'booked_count': 2,
        'meals': {
          'name': 'رز',
          'description': 'وصف',
          'image_path': null,
          'has_salad': true,
          'has_soft_drink': false,
          'has_juice': true,
          'has_vegetables': false,
        },
      });
      expect(offering.serviceDate, DateTime(2026, 11, 9));
      expect(offering.bookUntil.toUtc(), DateTime.utc(2026, 11, 8, 17));
      expect(offering.bookUntil.isUtc, isFalse);
      expect(offering.extras, ['سلطة', 'عصير']);
      expect(offering.soldOut, isTrue);
    });

    test('a booking row is read', () {
      final booking = Booking.fromRow({
        'id': 'b1',
        'offering_id': 'o1',
        'amount': 6000,
        'status': 'cancelled_by_restaurant',
        'meal_offerings': {
          'meal_id': 'm1',
          'service_date': '2026-11-09',
          'period': 'iftar',
          'cancel_until': '2026-11-09T05:00:00+00:00',
          'pickup_from': '2026-11-09T09:00:00+00:00',
          'pickup_until': '2026-11-09T11:30:00+00:00',
          'meals': {'name': 'رز'},
        },
      });
      expect(booking.status, BookingStatus.cancelledByRestaurant);
      expect(booking.period, MealPeriod.iftar);
      expect(booking.mealName, 'رز');
      expect(booking.isLive, isFalse);
    });

    test('rejections become sentences', () {
      expect(
        EmployeeFailure.fromServer('insufficient_balance', {'shortfall': 2000}).message,
        'ينقصك 2,000 نقطة. راجع مسؤول النظام لشحن رصيدك.',
      );
      expect(
        EmployeeFailure.fromServer('booking_closed', {'service_date': '2026-11-09'}).message,
        'انتهى وقت حجز وجبة الاثنين 9 تشرين الثاني. لم يُخصم شيء.',
      );
      expect(EmployeeFailure.fromServer('something_new', {}).message, EmployeeFailure.unknown.message);
    });

    test('a settlement has no sign, because the balance moved at booking', () {
      WalletTx tx(WalletTxType type, int available, int held) =>
          WalletTx(type: type, availableDelta: available, heldDelta: held, mealName: 'رز', createdAt: DateTime(2026, 11, 5));
      expect(tx(WalletTxType.hold, -6000, 6000).amountText, '-6,000');
      expect(tx(WalletTxType.release, 6000, -6000).amountText, '+6,000');
      expect(tx(WalletTxType.settlePickup, 0, -6000).amountText, '6,000');
      expect(tx(WalletTxType.settleNoShow, 0, -6000).text, contains('لم تُستلم'));
    });
  });

  group('same meal on later days', () {
    final now = DateTime(2026, 11, 2, 9);
    final later = now.add(const Duration(days: 60));
    Offering weekly(String id, DateTime day, {DateTime? bookUntil, String mealId = 'lunch-meal'}) =>
        _offering(id, day, bookUntil: bookUntil ?? later, mealId: mealId);

    test('booking repeats on the same weekday, in the same month, only if still open', () {
      final pick = weekly('a', DateTime(2026, 11, 9));
      final series = bookableSeries(
        pick,
        [
          weekly('before', DateTime(2026, 11, 2)),
          pick,
          weekly('other-day', DateTime(2026, 11, 10)),
          weekly('held', DateTime(2026, 11, 16)),
          weekly('c', DateTime(2026, 11, 23)),
          weekly('other-meal', DateTime(2026, 11, 23), mealId: 'fish'),
          weekly('closed', DateTime(2026, 11, 30), bookUntil: DateTime(2026, 11, 1)),
          weekly('next-month', DateTime(2026, 12, 7)),
        ],
        [_booking('b', DateTime(2026, 11, 16), offeringId: 'held')],
        now,
      );
      expect(series.map((offering) => offering.id), ['a', 'c']);
    });

    test('cancelling counts later meals and reports those past their deadline', () {
      final target = _booking('t', DateTime(2026, 11, 9), cancelUntil: later);
      final result = cancelSeriesFor(
        target,
        [
          target,
          _booking('earlier', DateTime(2026, 11, 2), cancelUntil: later),
          _booking('open', DateTime(2026, 11, 16), cancelUntil: later),
          _booking('locked', DateTime(2026, 11, 23), cancelUntil: DateTime(2026, 11, 1)),
          _booking('collected', DateTime(2026, 11, 30), cancelUntil: later, status: BookingStatus.pickedUp),
          _booking('next-month', DateTime(2026, 12, 7), cancelUntil: later),
          _booking('other-meal', DateTime(2026, 11, 16), cancelUntil: later, mealId: 'fish'),
        ],
        now,
      );
      expect(result.cancellable.map((booking) => booking.id), ['open']);
      expect(result.locked, 1);
    });

    test('the next meal is the nearest one still to collect', () {
      final done = _booking('done', DateTime(2026, 11, 1));
      final soon = _booking('soon', DateTime(2026, 11, 3));
      final after = _booking('after', DateTime(2026, 11, 9));
      final collected = _booking('collected', DateTime(2026, 11, 2), status: BookingStatus.pickedUp);
      expect(nextBooking([after, done, collected, soon], now)?.id, 'soon');
      expect(nextBooking([done], now), isNull);
    });
  });

  group('calendar', () {
    test('the week starts on Saturday', () {
      final november = calendarCells(DateTime(2026, 11)); // starts on a Sunday
      expect(november.first, isNull);
      expect(november[1], DateTime(2026, 11, 1));
      expect(november.length, 31);
      expect(calendarCells(DateTime(2026, 8)).first, DateTime(2026, 8, 1)); // a Saturday
    });
  });

  group('meals page', () {
    testWidgets('books one meal and tells the user', (tester) async {
      final day = dayOf(DateTime.now());
      final repository = FakeEmployeeRepository(offeringsValue: [_offering('o1', day)]);
      await _pumpPage(tester, const MealsPage(), repository);

      expect(find.text('50,000 نقطة'), findsOneWidget);
      expect(find.text('معها: سلطة وعصير'), findsOneWidget);
      await tester.tap(find.byKey(const Key('book-o1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('book-repeat')), findsNothing);

      await tester.tap(find.byKey(const Key('book-confirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(repository.bookCalls.single.$1, ['o1']);
      expect(find.text('تم الحجز'), findsOneWidget);
      await _closeNotice(tester);
    });

    testWidgets('repeats a meal for the rest of the month from my bookings', (tester) async {
      final day = _firstMondayNextMonth();
      final repository = FakeEmployeeRepository(offeringsValue: [
        _offering('o1', day),
        _offering('o2', addDays(day, 7)),
        _offering('o3', addDays(day, 14)),
      ]);
      await _pumpPage(tester, const BookingsPage(), repository, height: 1200);
      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('day-${isoDate(day)}')));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('book-o1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('book-o1')));
      await tester.pumpAndSettle();
      expect(find.text('6,000 نقطة'), findsWidgets);
      await tester.tap(find.byKey(const Key('book-repeat')));
      await tester.pumpAndSettle();
      expect(find.text('النقاط المطلوبة: 18,000 نقطة'), findsOneWidget);

      await tester.tap(find.byKey(const Key('book-confirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(repository.bookCalls.single.$1, ['o1', 'o2', 'o3']);
      expect(find.text('تم حجز 3 وجبات'), findsOneWidget);
      await _closeNotice(tester);
    });

    testWidgets('without enough money it explains and offers no confirm', (tester) async {
      final day = dayOf(DateTime.now());
      final repository = FakeEmployeeRepository(
        walletValue: const Wallet(available: 1000, held: 0),
        offeringsValue: [_offering('o1', day)],
      );
      await _pumpPage(tester, const MealsPage(), repository);
      await tester.tap(find.byKey(const Key('book-o1')));
      await tester.pumpAndSettle();
      expect(find.text('ينقصك 5,000 نقطة. راجع مسؤول النظام لشحن رصيدك.'), findsOneWidget);
      expect(find.byKey(const Key('book-confirm')), findsNothing);
    });

    testWidgets('a retry after a lost connection reuses the same key', (tester) async {
      final day = dayOf(DateTime.now());
      final repository = FakeEmployeeRepository(offeringsValue: [_offering('o1', day)])..failNext = EmployeeFailure.network;
      await _pumpPage(tester, const MealsPage(), repository);
      await tester.tap(find.byKey(const Key('book-o1')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('book-confirm')));
      await tester.pumpAndSettle();
      expect(find.text(EmployeeFailure.network.message), findsOneWidget);

      await tester.tap(find.byKey(const Key('book-confirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(repository.bookCalls.length, 2);
      expect(repository.bookCalls[0].$2, repository.bookCalls[1].$2);
      await _closeNotice(tester);
    });

    testWidgets('booked, closed and sold-out meals offer no booking', (tester) async {
      final day = dayOf(DateTime.now());
      final repository = FakeEmployeeRepository(
        offeringsValue: [
          _offering('open', day, mealId: 'a', period: MealPeriod.breakfast),
          _offering('mine', day, mealId: 'b'),
          _offering('late', day, mealId: 'c', bookUntil: _past),
          _offering('full', day, mealId: 'd', capacity: 3, bookedCount: 3, period: MealPeriod.dinner),
        ],
        bookingsValue: [_booking('b1', day, offeringId: 'mine', mealId: 'b')],
      );
      await _pumpPage(tester, const MealsPage(), repository, height: 2400);
      expect(find.byKey(const Key('book-open')), findsOneWidget);
      expect(find.byKey(const Key('book-mine')), findsNothing);
      expect(find.byKey(const Key('book-late')), findsNothing);
      expect(find.byKey(const Key('book-full')), findsNothing);
      expect(find.byKey(const Key('unbook-mine')), findsOneWidget);
      expect(find.text('انتهى وقت الحجز'), findsOneWidget);
      expect(find.text('نفدت الكمية'), findsOneWidget);
    });

    testWidgets('a booked meal is cancelled from its card after a confirmation', (tester) async {
      final day = dayOf(DateTime.now());
      final repository = FakeEmployeeRepository(
        offeringsValue: [_offering('mine', day)],
        bookingsValue: [_booking('b1', day, offeringId: 'mine')],
      );
      await _pumpPage(tester, const MealsPage(), repository, height: 1200);
      expect(find.text('محجوزة · إلغاء الحجز'), findsOneWidget);

      await tester.tap(find.byKey(const Key('unbook-mine')));
      await tester.pumpAndSettle();
      expect(find.text('إلغاء هذا الحجز؟'), findsOneWidget);
      expect(repository.cancelCalls, isEmpty);

      await tester.tap(find.byKey(const Key('cancel-confirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(repository.cancelCalls.single.$1, 'b1');
      expect(find.text('رجع 6,000 نقطة إلى رصيدك'), findsOneWidget);
      await _closeNotice(tester);
      expect(find.byKey(const Key('book-mine')), findsOneWidget);
    });

    testWidgets('a booked meal past its cancel time says so instead', (tester) async {
      final day = dayOf(DateTime.now());
      final repository = FakeEmployeeRepository(
        offeringsValue: [_offering('mine', day)],
        bookingsValue: [_booking('b1', day, offeringId: 'mine', cancelUntil: _past)],
      );
      await _pumpPage(tester, const MealsPage(), repository, height: 1200);
      expect(find.byKey(const Key('unbook-mine')), findsNothing);
      expect(find.text('محجوزة · انتهى وقت الإلغاء'), findsOneWidget);
    });

    testWidgets('shows only today, even after booking closes and whatever order the meals arrive in', (tester) async {
      final today = dayOf(DateTime.now());
      // Later days first, as a descending query would return them.
      await _pumpPage(tester, const MealsPage(), FakeEmployeeRepository(offeringsValue: [
        _offering('far', addDays(today, 55), name: 'دولمة'),
        _offering('tomorrow', addDays(today, 1), name: 'كباب'),
        _offering('today', today, name: 'شوربة', bookUntil: _past),
      ]), height: 1600);
      expect(_text(tester, 'meals-day'), 'وجبات اليوم');
      expect(find.text('شوربة'), findsOneWidget);
      expect(find.text('انتهى وقت الحجز'), findsOneWidget);
      expect(find.text('كباب'), findsNothing);
      expect(find.text('دولمة'), findsNothing);
      expect(find.byKey(const Key('go-bookings')), findsOneWidget);
    });

    testWidgets('with no meal today it says so and points to my bookings', (tester) async {
      final today = dayOf(DateTime.now());
      final repository = FakeEmployeeRepository(offeringsValue: [_offering('tomorrow', addDays(today, 1), name: 'كباب')]);
      await _pumpPage(tester, const MealsPage(), repository);
      expect(find.text('لا توجد وجبات اليوم.'), findsOneWidget);
      expect(find.text('كباب'), findsNothing);
      await tester.tap(find.byKey(const Key('go-bookings')));
      await tester.pumpAndSettle();
    });
  });

  // Standing delegation only: a chosen colleague can collect any of my meals.
  group('delegation', () {
    const ahmed = Colleague(username: 'ahmed', fullName: 'أحمد علي', department: 'الصيدلية');
    Delegate delegate(String name, {String? fullName}) =>
        Delegate(delegationId: 'd-$name', username: name, fullName: fullName ?? 'زميل $name');

    Future<void> openSheet(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('delegates-open')).first);
      await tester.pumpAndSettle();
    }

    testWidgets('the next meal card shows who can collect, with their initials', (tester) async {
      final tomorrow = addDays(dayOf(DateTime.now()), 1);
      final repository = FakeEmployeeRepository(
        offeringsValue: [_offering('mine', tomorrow)],
        bookingsValue: [_booking('b1', tomorrow, offeringId: 'mine')],
      )..delegatesValue = [delegate('ahmed', fullName: 'أحمد علي'), delegate('saad', fullName: 'سعد كريم')];
      await _pumpPage(tester, const MealsPage(), repository, height: 1400);
      expect(find.byKey(const Key('delegates-open')), findsOneWidget);
      expect(find.text('أع'), findsOneWidget);
      expect(find.text('سك'), findsOneWidget);

      await openSheet(tester);
      expect(find.text('من يستلم وجباتي'), findsWidgets);
      expect(find.text('أحمد علي'), findsOneWidget);
      expect(find.text('سعد كريم'), findsOneWidget);
    });

    testWidgets('a colleague is found by username, checked by name, then added', (tester) async {
      final repository = FakeEmployeeRepository()..colleagues = {'ahmed': ahmed};
      await _pumpPage(tester, const AccountPage(), repository, height: 1400);
      await openSheet(tester);
      expect(find.byKey(const Key('delegates-empty')), findsOneWidget);

      await tester.enterText(find.byKey(const Key('delegate-username')), 'Ahmed ');
      await tester.tap(find.byKey(const Key('delegate-find')));
      await tester.pumpAndSettle();
      expect(find.textContaining('أحمد علي'), findsWidgets);
      expect(find.textContaining('الصيدلية'), findsOneWidget);
      expect(repository.addDelegateCalls, isEmpty);

      await tester.tap(find.byKey(const Key('delegate-add')));
      await tester.pumpAndSettle();
      expect(repository.addDelegateCalls.single.$1, 'ahmed');
      expect(find.text('تم التخويل'), findsOneWidget);
      expect(find.text('أحمد علي يستطيع استلام وجباتك.'), findsOneWidget);
      expect(find.byKey(const Key('notice-badge-person')), findsOneWidget);
      await _closeNotice(tester);
      expect(find.text('تم التخويل'), findsNothing);
      expect(find.byKey(const Key('delegate-remove-d-ahmed')), findsOneWidget);
      expect(find.byKey(const Key('delegate-username')), findsOneWidget);
    });

    testWidgets('a second colleague is added next to the first', (tester) async {
      final repository = FakeEmployeeRepository()
        ..delegatesValue = [delegate('saad')]
        ..colleagues = {'ahmed': ahmed};
      await _pumpPage(tester, const AccountPage(), repository, height: 1400);
      await openSheet(tester);
      await tester.enterText(find.byKey(const Key('delegate-username')), 'ahmed');
      await tester.tap(find.byKey(const Key('delegate-find')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('delegate-add')));
      await tester.pumpAndSettle();
      await _closeNotice(tester);
      expect(find.byKey(const Key('delegate-remove-d-saad')), findsOneWidget);
      expect(find.byKey(const Key('delegate-remove-d-ahmed')), findsOneWidget);
    });

    testWidgets('an unknown username explains and adds nobody', (tester) async {
      final repository = FakeEmployeeRepository();
      await _pumpPage(tester, const AccountPage(), repository, height: 1400);
      await openSheet(tester);
      await tester.enterText(find.byKey(const Key('delegate-username')), 'nobody');
      await tester.tap(find.byKey(const Key('delegate-find')));
      await tester.pumpAndSettle();
      expect(find.text('لم نجد زميلاً بهذا الاسم في مطعمك. تأكد من اسم المستخدم.'), findsOneWidget);
      expect(find.byKey(const Key('delegate-add')), findsNothing);
    });

    testWidgets('withdrawing asks first, then removes only that colleague', (tester) async {
      final repository = FakeEmployeeRepository()..delegatesValue = [delegate('saad'), delegate('ali')];
      await _pumpPage(tester, const AccountPage(), repository, height: 1400);
      await openSheet(tester);
      await tester.tap(find.byKey(const Key('delegate-remove-d-saad')));
      await tester.pumpAndSettle();
      expect(repository.removeDelegateCalls, isEmpty);
      expect(find.textContaining('إلغاء تخويل زميل saad؟'), findsOneWidget);

      await tester.tap(find.byKey(const Key('delegate-remove-confirm')));
      await tester.pumpAndSettle();
      expect(repository.removeDelegateCalls, ['d-saad']);
      expect(find.text('أُلغي التخويل'), findsOneWidget);
      await _closeNotice(tester);
      expect(find.byKey(const Key('delegate-remove-d-saad')), findsNothing);
      expect(find.byKey(const Key('delegate-remove-d-ali')), findsOneWidget);
    });

    testWidgets('with five chosen it asks to withdraw one before adding', (tester) async {
      final repository = FakeEmployeeRepository()..delegatesValue = [for (final name in ['a', 'b', 'c', 'd', 'e']) delegate(name)];
      await _pumpPage(tester, const AccountPage(), repository, height: 1600);
      expect(find.text('+2'), findsOneWidget);
      await openSheet(tester);
      expect(find.byKey(const Key('delegates-full')), findsOneWidget);
      expect(find.byKey(const Key('delegate-username')), findsNothing);
    });

    testWidgets('a list that fails to load says so and can be retried', (tester) async {
      final repository = FakeEmployeeRepository()
        ..delegatesValue = [delegate('saad', fullName: 'سعد كريم')]
        ..delegatesFailures = 1;
      await _pumpPage(tester, const AccountPage(), repository, height: 1400);
      expect(find.text('سك'), findsNothing);
      await openSheet(tester);
      expect(find.byKey(const Key('delegates-failed')), findsOneWidget);

      await tester.tap(find.byKey(const Key('delegates-retry')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('delegates-failed')), findsNothing);
      expect(find.text('سعد كريم'), findsOneWidget);
      expect(find.text('سك'), findsWidgets);
    });
  });

  group('rating', () {
    RatableMeal ratable() {
      final now = DateTime.now();
      return RatableMeal(
        bookingId: 'b1',
        mealName: 'كباب',
        period: MealPeriod.lunch,
        serviceDate: dayOf(now),
        pickedUpAt: now.subtract(const Duration(hours: 1)),
        rateUntil: now.add(const Duration(hours: 3)),
      );
    }

    Future<void> tapKey(WidgetTester tester, String key) async {
      await tester.ensureVisible(find.byKey(Key(key)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();
    }

    testWidgets('a collected meal asks for stars, tags and a comment', (tester) async {
      final repository = FakeEmployeeRepository()..ratableValue = [ratable()];
      await _pumpPage(tester, const MealsPage(), repository, height: 1200);
      expect(find.text('كيف كانت وجبتك؟'), findsOneWidget);

      await tapKey(tester, 'rate-star-b1-4');
      expect(find.text('قيّم وجبتك'), findsOneWidget);
      expect(find.text('جيدة'), findsOneWidget);
      await tapKey(tester, 'star-2');
      expect(find.text('سيئة'), findsOneWidget);
      await tapKey(tester, 'tag-cold');
      await tester.enterText(find.byKey(const Key('rate-comment')), 'الرز بارد');
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('rate-send')));
      await tester.tap(find.byKey(const Key('rate-send')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final call = repository.rateCalls.single;
      expect(call.bookingId, 'b1');
      expect(call.stars, 2);
      expect(call.tags, {RatingTag.cold});
      expect(call.comment, 'الرز بارد');
      expect(find.text('شكراً لك'), findsOneWidget);
      await _closeNotice(tester);
      expect(find.text('كيف كانت وجبتك؟'), findsNothing);
    });

    testWidgets('sending needs stars first', (tester) async {
      final repository = FakeEmployeeRepository();
      await _pumpPage(tester, SingleChildScrollView(child: RateSheet(meal: ratable())), repository, height: 1200);
      expect(find.text('اختر عدد النجوم'), findsOneWidget);
      await tapKey(tester, 'rate-send');
      expect(find.text('اختر عدد النجوم أولاً.'), findsOneWidget);
      expect(repository.rateCalls, isEmpty);
    });

    testWidgets('a retry reuses the key and a change starts a new one', (tester) async {
      final repository = FakeEmployeeRepository()
        ..ratableValue = [ratable()]
        ..failNext = EmployeeFailure.network;
      await _pumpPage(tester, const MealsPage(), repository, height: 1200);
      await tapKey(tester, 'rate-star-b1-3');
      await tapKey(tester, 'rate-send');
      expect(find.text(EmployeeFailure.network.message), findsOneWidget);

      repository.failNext = const EmployeeFailure('انتهى وقت تقييم هذه الوجبة.');
      await tapKey(tester, 'rate-send');
      expect(repository.rateCalls[0].key, repository.rateCalls[1].key);
      expect(find.text('انتهى وقت تقييم هذه الوجبة.'), findsOneWidget);

      await tapKey(tester, 'star-4');
      await tester.ensureVisible(find.byKey(const Key('rate-send')));
      await tester.tap(find.byKey(const Key('rate-send')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(repository.rateCalls[2].key, isNot(repository.rateCalls[1].key));
      await _closeNotice(tester);
    });

    test('server refusals read as sentences', () {
      expect(EmployeeFailure.fromServer('rating_closed', const {}).message, 'انتهى وقت تقييم هذه الوجبة.');
      expect(EmployeeFailure.fromServer('already_rated', const {}).message, 'قيّمت هذه الوجبة سابقاً.');
      expect(starsWord(1), 'سيئة جداً');
      expect(RatingTag.fromCode('late'), RatingTag.delayed);
    });
  });

  group('my bookings', () {
    Future<void> openDay(WidgetTester tester, DateTime day) async {
      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('day-${isoDate(day)}')));
      await tester.pumpAndSettle();
    }

    testWidgets('cancels one meal and returns the money', (tester) async {
      final day = _firstMondayNextMonth();
      final repository = FakeEmployeeRepository(bookingsValue: [_booking('b1', day)]);
      await _pumpPage(tester, const BookingsPage(), repository);
      await openDay(tester, day);

      await tester.tap(find.byKey(const Key('cancel-b1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cancel-more')), findsNothing);
      await tester.tap(find.byKey(const Key('cancel-confirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(repository.cancelCalls.single.$1, 'b1');
      expect(repository.seriesCalls, isEmpty);
      expect(find.text('أُلغي الحجز'), findsOneWidget);
      expect(find.text('رجع 6,000 نقطة إلى رصيدك'), findsOneWidget);
      await _closeNotice(tester);
      expect(find.byKey(const Key('cancel-b1')), findsNothing);
    });

    testWidgets('can cancel the same meal on later weeks too', (tester) async {
      final day = _firstMondayNextMonth();
      final repository = FakeEmployeeRepository(bookingsValue: [
        _booking('b1', day),
        _booking('b2', addDays(day, 7)),
        _booking('b3', addDays(day, 14)),
      ]);
      await _pumpPage(tester, const BookingsPage(), repository);
      await openDay(tester, day);

      await tester.tap(find.byKey(const Key('cancel-b1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cancel-more')));
      await tester.pumpAndSettle();
      expect(find.text('سيرجع إلى رصيدك فوراً: 18,000 نقطة'), findsOneWidget);
      expect(find.text('نعم، ألغِ 3 وجبات'), findsOneWidget);

      await tester.tap(find.byKey(const Key('cancel-confirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(repository.seriesCalls.single.$1, 'b1');
      expect(repository.cancelCalls, isEmpty);
      expect(find.text('أُلغيت 3 وجبات'), findsOneWidget);
      await _closeNotice(tester);
    });

    testWidgets('after the deadline there is no cancel button', (tester) async {
      final day = _firstMondayNextMonth();
      final repository = FakeEmployeeRepository(bookingsValue: [_booking('b1', day, cancelUntil: _past)]);
      await _pumpPage(tester, const BookingsPage(), repository);
      await openDay(tester, day);
      expect(find.byKey(const Key('cancel-b1')), findsNothing);
      expect(find.text('انتهى وقت الإلغاء'), findsOneWidget);
      expect(find.text('لا يمكن إلغاؤها الآن، وستُخصم إذا لم تستلمها'), findsOneWidget);
    });

    testWidgets('shows what happened to past meals', (tester) async {
      final day = _firstMondayNextMonth();
      final repository = FakeEmployeeRepository(bookingsValue: [
        _booking('b1', day, status: BookingStatus.pickedUp, period: MealPeriod.breakfast),
        _booking('b2', day, status: BookingStatus.noShow),
        _booking('b3', day, status: BookingStatus.cancelledByRestaurant, period: MealPeriod.dinner),
      ]);
      await _pumpPage(tester, const BookingsPage(), repository);
      await openDay(tester, day);
      expect(find.text('تم الاستلام'), findsOneWidget);
      expect(find.text('لم تُستلم، واستُقطعت النقاط'), findsOneWidget);
      expect(find.text('ألغاها المطعم، ورجعت النقاط إلى رصيدك'), findsOneWidget);
    });
  });

  group('account', () {
    testWidgets('shows both balances and the history', (tester) async {
      final repository = FakeEmployeeRepository(
        walletValue: const Wallet(available: 13500, held: 34000),
        transactionsValue: [
          WalletTx(type: WalletTxType.topup, availableDelta: 70000, heldDelta: 0, createdAt: DateTime(2026, 11, 1)),
          WalletTx(type: WalletTxType.hold, availableDelta: -6000, heldDelta: 6000, mealName: 'رز', createdAt: DateTime(2026, 11, 2)),
        ],
      );
      await _pumpPage(tester, const AccountPage(), repository);
      expect(find.text('13,500'), findsOneWidget);
      expect(find.text('34,000'), findsOneWidget);
      expect(find.text('شحن من مسؤول النظام'), findsOneWidget);
      expect(find.text('+70,000'), findsOneWidget);
      expect(find.text('حجز رز'), findsOneWidget);
      expect(find.text('-6,000'), findsOneWidget);
      expect(find.byKey(const Key('tx-more')), findsNothing);
    });

    testWidgets('shows the latest page of movements, then more on request', (tester) async {
      final repository = FakeEmployeeRepository(transactionsValue: [
        for (var day = 1; day <= transactionsPage + 5; day++)
          WalletTx(type: WalletTxType.topup, availableDelta: day * 1000, heldDelta: 0, createdAt: DateTime(2026, 10, 1).add(Duration(days: day))),
      ]);
      await _pumpPage(tester, const AccountPage(), repository, height: 6000);
      expect(find.text('+$transactionsPage,000'), findsOneWidget);
      expect(find.text('+${transactionsPage + 1},000'), findsNothing);

      await tester.tap(find.byKey(const Key('tx-more')));
      await tester.pumpAndSettle();
      expect(find.text('+${transactionsPage + 5},000'), findsOneWidget);
      expect(find.byKey(const Key('tx-more')), findsNothing);
    });
  });

  group('loading only what is shown', () {
    testWidgets('the meals page asks for today alone', (tester) async {
      final repository = FakeEmployeeRepository();
      await _pumpPage(tester, const MealsPage(), repository);
      final today = dayOf(DateTime.now());
      expect(repository.offeringsCalls, [(today, today)]);
    });

    testWidgets('my bookings asks for the month on screen, from today', (tester) async {
      final repository = FakeEmployeeRepository();
      await _pumpPage(tester, const BookingsPage(), repository);
      final today = dayOf(DateTime.now());
      expect(repository.offeringsCalls, [(today, DateTime(today.year, today.month + 1, 0))]);
    });
  });
}

/// The real restaurant's week: Saturday has all three meals, Thursday only dinner.
void bookingScenarios() {
  group('booking scenarios', () {
    DateTime nextWeekday(int weekday, {int weeksAhead = 0}) {
      var day = addDays(dayOf(DateTime.now()), 1);
      while (day.weekday != weekday) {
        day = addDays(day, 1);
      }
      return addDays(day, 7 * weeksAhead);
    }

    List<Offering> program() {
      final offerings = <Offering>[];
      for (var week = 0; week < 8; week++) {
        final thursday = nextWeekday(DateTime.thursday, weeksAhead: week);
        final saturday = nextWeekday(DateTime.saturday, weeksAhead: week);
        offerings.addAll([
          _offering('thu$week', thursday, mealId: 'burger', name: 'برغر', period: MealPeriod.dinner),
          _offering('satb$week', saturday, mealId: 'eggs', name: 'بيض', period: MealPeriod.breakfast),
          _offering('satl$week', saturday, mealId: 'rice', name: 'رز', period: MealPeriod.lunch),
          _offering('satd$week', saturday, mealId: 'burger', name: 'برغر', period: MealPeriod.dinner),
        ]);
      }
      return offerings..sort((a, b) => a.serviceDate.compareTo(b.serviceDate));
    }

    // Opens a day from the calendar in my bookings, moving forward month by month.
    Future<void> pickDay(WidgetTester tester, DateTime day) async {
      final now = DateTime.now();
      final months = (day.year * 12 + day.month) - (now.year * 12 + now.month);
      for (var i = 0; i < months; i++) {
        await tester.tap(find.byIcon(Icons.chevron_right));
        await tester.pumpAndSettle();
      }
      final cell = find.byKey(Key('day-${isoDate(day)}'));
      await tester.ensureVisible(cell);
      await tester.pumpAndSettle();
      await tester.tap(cell);
      await tester.pumpAndSettle();
    }

    Future<void> tapAfterScroll(WidgetTester tester, String key) async {
      final target = find.byKey(Key(key));
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tester.tap(target);
      await tester.pumpAndSettle();
    }

    testWidgets('every Thursday can be opened and booked from my bookings, not just the last', (tester) async {
      for (final week in [0, 1, 2, 7]) {
        final repository = FakeEmployeeRepository(offeringsValue: program());
        await _pumpPage(tester, const BookingsPage(), repository, height: 1200);
        await pickDay(tester, nextWeekday(DateTime.thursday, weeksAhead: week));
        expect(find.text('برغر'), findsOneWidget);
        expect(find.text('بيض'), findsNothing);

        await tapAfterScroll(tester, 'book-thu$week');
        await tester.tap(find.byKey(const Key('book-confirm')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(repository.bookCalls.single.$1, ['thu$week']);
        await _closeNotice(tester);
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('a Saturday shows all three periods, each ready to book', (tester) async {
      await _pumpPage(tester, const BookingsPage(), FakeEmployeeRepository(offeringsValue: program()), height: 1200);
      await pickDay(tester, nextWeekday(DateTime.saturday, weeksAhead: 1));
      expect(find.text('بيض'), findsOneWidget);
      expect(find.text('رز'), findsOneWidget);
      expect(find.byKey(const Key('book-satb1')), findsOneWidget);
      expect(find.byKey(const Key('book-satl1')), findsOneWidget);
    });

    testWidgets('a closed meal says when booking ended, an open one until when', (tester) async {
      final day = dayOf(DateTime.now());
      await _pumpPage(tester, const MealsPage(), FakeEmployeeRepository(offeringsValue: [
        _offering('late', day, mealId: 'a', bookUntil: DateTime(day.year, day.month, day.day, 12)),
      ]));
      expect(find.textContaining('آخر حجز'), findsOneWidget);
    });
  });
}
