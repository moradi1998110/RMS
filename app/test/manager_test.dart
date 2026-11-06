import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:rms/core/format.dart';
import 'package:rms/core/theme.dart';
import 'package:rms/features/admin/admin_models.dart';
import 'package:rms/features/employee/codes_page.dart';
import 'package:rms/features/employee/employee_models.dart';
import 'package:rms/features/employee/employee_repository.dart';
import 'package:rms/features/manager/manager_models.dart';
import 'package:rms/features/manager/manager_providers.dart';
import 'package:rms/features/manager/manager_repository.dart';
import 'package:rms/features/manager/meals_tab.dart';
import 'package:rms/features/manager/program_tab.dart';
import 'package:rms/features/manager/reports_tab.dart';
import 'package:rms/features/manager/scan_page.dart';
import 'package:rms/features/manager/today_tab.dart';
import 'package:rms/shared/notice.dart';

import 'fake_employee_repository.dart';

const _rice = ManagerMeal(id: 'm1', name: 'رز ودجاج', price: 6000, hasSalad: true, hasJuice: true);
const _rule = TimeRule(
  period: MealPeriod.lunch,
  bookDay: 0,
  book: TimeOfDay(hour: 10, minute: 0),
  cancelDay: 0,
  cancel: TimeOfDay(hour: 10, minute: 0),
  fromDay: 0,
  from: TimeOfDay(hour: 12, minute: 0),
  untilDay: 0,
  until: TimeOfDay(hour: 14, minute: 30),
);

ScheduleRow _weekly({List<int> weekdays = const [1]}) => ScheduleRow(
      id: 's1',
      mealId: 'm1',
      mealName: 'رز ودجاج',
      period: MealPeriod.lunch,
      isRamadan: false,
      weekdays: weekdays,
      weeklyRepeat: true,
      start: DateTime(2026, 1, 1),
    );

TodayMeal _todayMeal() {
  final now = DateTime.now();
  return TodayMeal(
    offeringId: 'o1',
    name: 'رز ودجاج',
    period: MealPeriod.lunch,
    pickupFrom: now.subtract(const Duration(hours: 1)),
    pickupUntil: now.add(const Duration(hours: 1)),
    waiting: 3,
    collected: 2,
    notCollected: 1,
  );
}

class FakeManagerRepository implements ManagerRepository {
  FakeManagerRepository({
    this.mealsValue = const [_rice],
    this.schedulesValue = const [],
    this.rulesValue = const [_rule],
    this.todayValue = const [],
    this.bookings = const [],
  });

  List<ManagerMeal> mealsValue;
  List<ScheduleRow> schedulesValue;
  List<TimeRule> rulesValue;
  List<TodayMeal> todayValue;
  List<TodayBooking> bookings;
  ManagerWeek? weekValue;

  ManagerFailure? failNext;
  ScanResult scanResult = const ScanResult(ok: true, ownerName: 'أحمد', holderName: 'أحمد', mealName: 'رز');

  MealDraft? savedMeal;
  Map<String, Object?>? addedSchedule;
  (ScheduleRow, int)? removed;
  TimeRule? savedRule;
  (String, String)? cancelled;
  (String, String)? delivered;
  final tokenCalls = <(String, String)>[];
  final codeCalls = <(String, String)>[];

  void _maybeFail() {
    final failure = failNext;
    failNext = null;
    if (failure != null) throw failure;
  }

  @override
  Future<List<ManagerMeal>> meals() async => mealsValue;

  @override
  Future<void> saveMeal(MealDraft draft) async {
    _maybeFail();
    savedMeal = draft;
  }

  @override
  Future<List<ScheduleRow>> schedules() async => schedulesValue;

  @override
  Future<void> addSchedule({required String mealId, required MealPeriod period, required bool isRamadan, required List<int> weekdays, required bool weekly}) async {
    _maybeFail();
    addedSchedule = {'mealId': mealId, 'period': period, 'isRamadan': isRamadan, 'weekdays': weekdays, 'weekly': weekly};
  }

  @override
  Future<void> removeDay(ScheduleRow schedule, int dayOfWeek) async {
    removed = (schedule, dayOfWeek);
  }

  @override
  Future<int> copyLastWeek() async => 0;

  @override
  Future<List<TimeRule>> timeRules() async => rulesValue;

  @override
  Future<(int, int)> saveTimeRule(TimeRule rule) async {
    savedRule = rule;
    return (4, 2);
  }

  @override
  Future<List<TodayMeal>> today() async => todayValue;

  @override
  Future<List<TodayBooking>> bookingsOf(String offeringId) async => bookings;

  @override
  Future<int> cancelMeal(String offeringId, String reason, String key) async {
    cancelled = (offeringId, reason);
    return 3;
  }

  @override
  Future<void> recordDelivery(String bookingId, String reason, String key) async {
    delivered = (bookingId, reason);
  }

  @override
  Future<ScanResult> redeemToken(String token, String key) async {
    tokenCalls.add((token, key));
    _maybeFail();
    return scanResult;
  }

  @override
  Future<ScanResult> redeemCode(String code, String key) async {
    codeCalls.add((code, key));
    _maybeFail();
    return scanResult;
  }

  @override
  Future<ManagerWeek> week(DateTime start) async => weekValue ?? ManagerWeek.from(start, const []);

  List<MealRating> ratingsValue = const [];

  @override
  Future<List<MealRating>> ratings(DateTime start) async => ratingsValue;

  @override
  String imageUrl(String path) => 'https://example.invalid/$path';
}

ValueChanged<String>? _camera;

Future<void> _pumpPage(WidgetTester tester, Widget page, FakeManagerRepository repository, {PhotoPicker? picker, EmployeeRepository? employee}) async {
  tester.view.physicalSize = const Size(1170, 12000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        managerRepositoryProvider.overrideWithValue(repository),
        if (employee != null) employeeRepositoryProvider.overrideWithValue(employee),
        if (picker != null) photoPickerProvider.overrideWithValue(picker),
        scanCameraProvider.overrideWithValue((context, onCode) {
          _camera = onCode;
          return const ColoredBox(color: Colors.black);
        }),
      ],
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

Future<void> _tapKey(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

Future<void> _closeNotice(WidgetTester tester) async {
  await tester.pump(noticeDuration);
  await tester.pumpAndSettle();
}

String _keyText(WidgetTester tester, String key) => tester.widget<Text>(find.byKey(Key(key))).data!;

void main() {
  group('rules', () {
    test('a meal needs a name and a price', () {
      expect(mealProblem(' ', '6000'), isNotNull);
      expect(mealProblem('رز', ''), isNotNull);
      expect(mealProblem('رز', '0'), isNotNull);
      expect(mealProblem('رز', '6000'), isNull);
    });

    test('times must fall in order', () {
      expect(_rule.isValid, isTrue);
      TimeRule withFrom(int day, int hour) => TimeRule(
            period: MealPeriod.lunch,
            bookDay: _rule.bookDay,
            book: _rule.book,
            cancelDay: _rule.cancelDay,
            cancel: _rule.cancel,
            fromDay: day,
            from: TimeOfDay(hour: hour, minute: 0),
            untilDay: _rule.untilDay,
            until: _rule.until,
          );
      expect(withFrom(0, 7).isValid, isFalse); // before booking stops
      expect(withFrom(0, 15).isValid, isFalse); // after pickup ends
      expect(withFrom(0, 10).isValid, isFalse); // leaves no time to prepare
      expect(withFrom(0, 11).isValid, isTrue);
    });

    test('rule times read from the day of the meal', () {
      expect(ruleText(0, const TimeOfDay(hour: 8, minute: 0)), '8:00 صباحاً يوم الوجبة');
      expect(ruleText(-1, const TimeOfDay(hour: 22, minute: 0)), 'الليلة السابقة 10:00 مساءً');
    });

    test('a week-only schedule serves only its own remaining days', () {
      final today = DateTime(2026, 11, 5); // Thursday
      final row = ScheduleRow(
        id: 's',
        mealId: 'm',
        mealName: 'رز',
        period: MealPeriod.lunch,
        isRamadan: false,
        weekdays: const [0, 4, 3],
        weeklyRepeat: false,
        start: DateTime(2026, 11, 1),
        end: DateTime(2026, 11, 7),
      );
      expect(row.serves(4, today), isTrue); // today
      expect(row.serves(3, today), isFalse); // Wednesday has passed
      expect(row.serves(0, today), isFalse); // Sunday has passed
      expect(row.serves(1, today), isFalse); // not chosen
      expect(_weekly(weekdays: const [3]).serves(3, today), isTrue);
    });

    test('copying moves last week-only schedules one week, once', () {
      final today = DateTime(2026, 11, 5); // the week starting Saturday 31 October
      ScheduleRow once(DateTime start) => ScheduleRow(
            id: 'x',
            mealId: 'm1',
            mealName: 'رز',
            period: MealPeriod.lunch,
            isRamadan: false,
            weekdays: const [1],
            weeklyRepeat: false,
            start: start,
            end: start.add(const Duration(days: 6)),
          );
      final last = once(DateTime(2026, 10, 26));
      expect(copiesFromLastWeek([last, _weekly()], today).single.start, DateTime(2026, 11, 2));
      expect(copiesFromLastWeek([last, once(DateTime(2026, 11, 2))], today), isEmpty);
      expect(copiesFromLastWeek([once(DateTime(2026, 10, 10))], today), isEmpty);
    });

    test('scan results tell the manager what to do', () {
      const ok = ScanResult(ok: true, ownerName: 'سارة', holderName: 'أحمد', mealName: 'رز');
      expect(ok.tone, ScanTone.deliver);
      expect(ok.line1, 'سارة');
      expect(ok.line2, 'رز\nيستلمها بالنيابة: أحمد');
      expect(const ScanResult(ok: true, ownerName: 'سارة', holderName: 'سارة', mealName: 'رز').line2, 'رز');

      final twice = ScanResult.fromJson({'ok': false, 'reason': 'already_picked_up', 'picked_up_at': '2026-11-05T09:40:00Z', 'picked_up_by_name': 'أحمد'});
      expect(twice.tone, ScanTone.refuse);
      expect(twice.line1, 'استُلمت سابقاً');
      expect(twice.line2, contains('بواسطة أحمد'));

      final early = ScanResult.fromJson({'ok': false, 'reason': 'not_started', 'pickup_from': '2026-11-05T09:00:00Z'});
      expect(early.tone, ScanTone.wait);
      expect(early.title, 'لم يبدأ الوقت');
      expect(const ScanResult(ok: false, reason: 'invalid_token').line1, 'رمز غير صالح');
    });

    test('the report counts what is due and ranks meals', () {
      final start = DateTime(2026, 10, 31);
      ManagerWeekRow row(String meal, BookingStatus status) => ManagerWeekRow(
            row: WeekRow(date: start, period: MealPeriod.lunch, status: status, restaurantId: 'r1'),
            mealName: meal,
            amount: 1000,
          );
      final week = ManagerWeek.from(start, [
        row('سمك', BookingStatus.pickedUp),
        row('رز', BookingStatus.pickedUp),
        row('رز', BookingStatus.noShow),
        row('رز', BookingStatus.booked),
        row('سمك', BookingStatus.cancelled),
      ]);
      expect(week.due, 3000); // collected and uncollected, not waiting or cancelled
      expect(week.topMeals, [('رز', 3), ('سمك', 1)]);
    });
  });

  group('meals', () {
    testWidgets('adds a meal with extras and a photo', (tester) async {
      final repository = FakeManagerRepository(mealsValue: const []);
      final photo = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');
      await _pumpPage(tester, const MealsTab(), repository, picker: (fromCamera) async => null);
      expect(find.text('لا توجد وجبات بعد. ابدأ بإضافة أول وجبة.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());

      await _pumpPage(tester, const MealsTab(), repository, picker: (fromCamera) async => fromCamera ? photo : null);
      await _tapKey(tester, 'add-meal');
      await _tapKey(tester, 'meal-save');
      expect(find.text('اكتب اسم الوجبة وسعرها أولاً.'), findsOneWidget);
      expect(repository.savedMeal, isNull);

      await tester.enterText(find.byKey(const Key('meal-name')), 'سمك');
      await tester.enterText(find.byKey(const Key('meal-price')), '7500');
      await tester.pumpAndSettle();
      await _tapKey(tester, 'extra-salad');
      await tester.tap(find.byKey(const Key('photo-camera')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('meal-save')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(repository.savedMeal?.name, 'سمك');
      expect(repository.savedMeal?.price, 7500);
      expect(repository.savedMeal?.hasSalad, isTrue);
      expect(repository.savedMeal?.hasJuice, isFalse);
      expect(repository.savedMeal?.newImage, photo);
      expect(find.text('أُضيفت الوجبة'), findsOneWidget);
      await _closeNotice(tester);
    });

    testWidgets('refuses a photo over the size limit', (tester) async {
      final repository = FakeManagerRepository();
      final big = Uint8List(maxImageBytes + 1);
      await _pumpPage(tester, const MealsTab(), repository, picker: (_) async => big);
      await _tapKey(tester, 'add-meal');
      await _tapKey(tester, 'photo-gallery');
      expect(find.text('هذه الصورة كبيرة. اختر صورة أخرى.'), findsOneWidget);
    });

    testWidgets('edits a meal and can stop showing it', (tester) async {
      final repository = FakeManagerRepository();
      await _pumpPage(tester, const MealsTab(), repository);
      expect(find.text('معها: سلطة، عصير'), findsOneWidget);
      await _tapKey(tester, 'edit-meal-m1');
      await _tapKey(tester, 'meal-active');
      await tester.tap(find.byKey(const Key('meal-save')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(repository.savedMeal?.id, 'm1');
      expect(repository.savedMeal?.isActive, isFalse);
      await _closeNotice(tester);
    });
  });

  group('program', () {
    testWidgets('schedules a meal on the chosen days', (tester) async {
      final repository = FakeManagerRepository();
      await _pumpPage(tester, const ProgramTab(), repository);
      await _tapKey(tester, 'add-1-lunch');
      await _tapKey(tester, 'schedule-save');
      expect(find.text('اختر الوجبة ويوماً واحداً على الأقل.'), findsOneWidget);
      expect(find.textContaining('الأوقات تلقائية'), findsOneWidget);

      await _tapKey(tester, 'pick-m1');
      await _tapKey(tester, 'day-3');
      await tester.tap(find.byKey(const Key('schedule-save')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(repository.addedSchedule, {'mealId': 'm1', 'period': MealPeriod.lunch, 'isRamadan': false, 'weekdays': [1, 3], 'weekly': true});
      await _closeNotice(tester);
    });

    testWidgets('Ramadan has its own two periods and a week-only choice', (tester) async {
      final repository = FakeManagerRepository();
      await _pumpPage(tester, const ProgramTab(), repository);
      expect(find.byKey(const Key('add-1-breakfast')), findsOneWidget);
      await _tapKey(tester, 'season-ramadan');
      expect(find.byKey(const Key('add-1-breakfast')), findsNothing);
      await _tapKey(tester, 'add-1-iftar');
      await _tapKey(tester, 'pick-m1');
      await _tapKey(tester, 'repeat-once');
      await tester.tap(find.byKey(const Key('schedule-save')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(repository.addedSchedule?['isRamadan'], isTrue);
      expect(repository.addedSchedule?['period'], MealPeriod.iftar);
      expect(repository.addedSchedule?['weekly'], isFalse);
      await _closeNotice(tester);
    });

    testWidgets('removes a meal from one day after asking', (tester) async {
      final repository = FakeManagerRepository(schedulesValue: [_weekly(weekdays: const [1, 3])]);
      await _pumpPage(tester, const ProgramTab(), repository);
      expect(find.text('رز ودجاج'), findsNWidgets(2));
      await _tapKey(tester, 'remove-s1-1');
      expect(repository.removed, isNull);
      await tester.tap(find.text('نعم، أزلها'));
      await tester.pumpAndSettle();
      expect(repository.removed?.$2, 1);
    });

    testWidgets('one hour stops booking and cancelling together', (tester) async {
      final repository = FakeManagerRepository();
      await _pumpPage(tester, const ProgramTab(), repository);
      expect(find.text('آخر حجز وإلغاء: 10:00 صباحاً يوم الوجبة'), findsOneWidget);
      await _tapKey(tester, 'edit-times-lunch');
      expect(find.byKey(const Key('book-previous')), findsNothing);
      expect(find.byKey(const Key('cancel-time')), findsNothing);
      await tester.tap(find.byKey(const Key('times-save')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(repository.savedRule?.book, const TimeOfDay(hour: 10, minute: 0));
      expect(repository.savedRule?.cancel, repository.savedRule?.book);
      expect(repository.savedRule?.bookDay, 0);
      expect(repository.savedRule?.cancelDay, 0);
      expect(find.text('تغيّرت 4 وجبة، وبقيت 2 محجوزة على موعدها.'), findsOneWidget);
      await _closeNotice(tester);
    });

    testWidgets('an hour after pickup starts is refused by name', (tester) async {
      const late = TimeRule(
        period: MealPeriod.lunch,
        bookDay: 0,
        book: TimeOfDay(hour: 13, minute: 0),
        cancelDay: 0,
        cancel: TimeOfDay(hour: 13, minute: 0),
        fromDay: 0,
        from: TimeOfDay(hour: 12, minute: 0),
        untilDay: 0,
        until: TimeOfDay(hour: 14, minute: 30),
      );
      final repository = FakeManagerRepository(rulesValue: const [late]);
      await _pumpPage(tester, const ProgramTab(), repository);
      await _tapKey(tester, 'edit-times-lunch');
      await _tapKey(tester, 'times-save');
      expect(find.text('آخر حجز وإلغاء (1:00 ظهراً يوم الوجبة) يجب أن يكون قبل بدء الاستلام (12:00 ظهراً يوم الوجبة).'), findsOneWidget);
      expect(repository.savedRule, isNull);
    });

    testWidgets('suhoor keeps its hour on the night it is collected', (tester) async {
      const suhoor = TimeRule(
        period: MealPeriod.suhoor,
        bookDay: -1,
        book: TimeOfDay(hour: 19, minute: 0),
        cancelDay: -1,
        cancel: TimeOfDay(hour: 19, minute: 0),
        fromDay: -1,
        from: TimeOfDay(hour: 21, minute: 0),
        untilDay: -1,
        until: TimeOfDay(hour: 23, minute: 30),
      );
      final repository = FakeManagerRepository(rulesValue: const [suhoor]);
      await _pumpPage(tester, const ProgramTab(), repository);
      await _tapKey(tester, 'season-ramadan');
      await _tapKey(tester, 'edit-times-suhoor');
      await tester.tap(find.byKey(const Key('times-save')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(repository.savedRule?.bookDay, -1);
      expect(repository.savedRule?.cancelDay, -1);
      expect(repository.savedRule?.fromDay, -1);
      await _closeNotice(tester);
    });
  });

  group('today', () {
    testWidgets('shows counts and cancels a meal with a reason', (tester) async {
      final repository = FakeManagerRepository(todayValue: [_todayMeal()]);
      await _pumpPage(tester, const TodayTab(), repository);
      expect(find.text('6'), findsOneWidget); // booked
      expect(find.text('2'), findsOneWidget); // collected
      expect(find.text('3'), findsOneWidget); // waiting

      await _tapKey(tester, 'cancel-o1');
      await _tapKey(tester, 'cancel-meal-confirm');
      expect(find.text('اكتب السبب.'), findsOneWidget);
      expect(repository.cancelled, isNull);

      await tester.enterText(find.byKey(const Key('cancel-reason')), 'نفد الدجاج');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cancel-meal-confirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(repository.cancelled, ('o1', 'نفد الدجاج'));
      expect(find.text('رجع مبلغ 3 حجز إلى أصحابه.'), findsOneWidget);
      await _closeNotice(tester);
    });

    testWidgets('records a manual delivery with a reason', (tester) async {
      final repository = FakeManagerRepository(todayValue: [_todayMeal()], bookings: const [
        TodayBooking(id: 'b1', employeeName: 'أحمد', status: BookingStatus.booked),
        TodayBooking(id: 'b2', employeeName: 'سارة', status: BookingStatus.pickedUp),
      ]);
      await _pumpPage(tester, const TodayTab(), repository);
      await _tapKey(tester, 'people-o1');
      expect(find.text('استلم'), findsOneWidget);
      expect(find.byKey(const Key('deliver-b2')), findsNothing);

      await _tapKey(tester, 'deliver-b1');
      await _tapKey(tester, 'deliver-confirm');
      expect(find.textContaining('اكتب سبب التسليم'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('deliver-reason')), 'انقطع الإنترنت');
      await tester.pumpAndSettle();
      await _tapKey(tester, 'deliver-confirm');
      expect(repository.delivered, ('b1', 'انقطع الإنترنت'));
      await _tapKey(tester, 'people-close');
    });
  });

  group('scanning', () {
    testWidgets('a good scan says deliver and counts it', (tester) async {
      final repository = FakeManagerRepository();
      await _pumpPage(tester, const ScanPage(), repository);
      _camera!('token-1');
      await tester.pumpAndSettle();
      expect(_keyText(tester, 'scan-title'), 'سلّم الوجبة');
      expect(_keyText(tester, 'scan-line1'), 'أحمد');
      expect(_keyText(tester, 'scan-count'), 'سلّمت: 1');
    });

    testWidgets('while a result shows, the camera is ignored', (tester) async {
      final repository = FakeManagerRepository();
      await _pumpPage(tester, const ScanPage(), repository);
      _camera!('token-1');
      await tester.pumpAndSettle();
      _camera!('token-1');
      _camera!('token-2');
      await tester.pumpAndSettle();
      expect(repository.tokenCalls.length, 1);
    });

    testWidgets('scanning the same code again uses a new key, so it cannot repeat a stored result', (tester) async {
      final repository = FakeManagerRepository();
      await _pumpPage(tester, const ScanPage(), repository);
      _camera!('token-1');
      await tester.pumpAndSettle();
      await _tapKey(tester, 'scan-next');
      _camera!('token-1');
      await tester.pumpAndSettle();
      expect(repository.tokenCalls.length, 2);
      expect(repository.tokenCalls[1].$2, isNot(repository.tokenCalls[0].$2));
    });

    testWidgets('a lost connection never says deliver, and a retry keeps the key', (tester) async {
      final repository = FakeManagerRepository()..failNext = ManagerFailure.network;
      await _pumpPage(tester, const ScanPage(), repository);
      _camera!('token-1');
      await tester.pumpAndSettle();
      expect(_keyText(tester, 'scan-title'), 'لا تسلّم بعد');
      expect(_keyText(tester, 'scan-count'), 'سلّمت: 0');

      await _tapKey(tester, 'scan-next');
      expect(_keyText(tester, 'scan-title'), 'سلّم الوجبة');
      expect(repository.tokenCalls.length, 2);
      expect(repository.tokenCalls[1].$2, repository.tokenCalls[0].$2);
    });

    testWidgets('a refusal says do not deliver and is not counted', (tester) async {
      final repository = FakeManagerRepository()..scanResult = const ScanResult(ok: false, reason: 'wrong_restaurant');
      await _pumpPage(tester, const ScanPage(), repository);
      _camera!('token-1');
      await tester.pumpAndSettle();
      expect(_keyText(tester, 'scan-title'), 'لا تسلّم');
      expect(_keyText(tester, 'scan-line1'), 'الوجبة من مطعم آخر');
      expect(_keyText(tester, 'scan-count'), 'سلّمت: 0');
    });

    testWidgets('the backup code needs all six digits', (tester) async {
      final repository = FakeManagerRepository();
      await _pumpPage(tester, const ScanPage(), repository);
      await tester.enterText(find.byKey(const Key('scan-code')), '123');
      await tester.pumpAndSettle();
      await _tapKey(tester, 'scan-code-submit');
      expect(repository.codeCalls, isEmpty);
      await tester.enterText(find.byKey(const Key('scan-code')), '123456');
      await tester.pumpAndSettle();
      await _tapKey(tester, 'scan-code-submit');
      expect(repository.codeCalls.single.$1, '123456');
    });
  });

  group('reports', () {
    testWidgets('shows the amount due and the top meals', (tester) async {
      final start = weekStartOf(DateTime.now());
      final repository = FakeManagerRepository()
        ..weekValue = ManagerWeek.from(start, [
          ManagerWeekRow(row: WeekRow(date: start, period: MealPeriod.lunch, status: BookingStatus.pickedUp, restaurantId: 'r1'), mealName: 'رز', amount: 6000),
        ]);
      await _pumpPage(tester, const ReportsTab(), repository);
      expect(_keyText(tester, 'week-due'), '6,000 دينار');
      expect(find.text('أكثر الوجبات طلباً هذا الأسبوع'), findsOneWidget);
      expect(find.text('رز'), findsOneWidget);
      await tester.scrollUntilVisible(find.byKey(const Key('ratings-empty')), 300);
      expect(find.byKey(const Key('ratings-empty')), findsOneWidget);
    });

    testWidgets('shows ratings by meal with the low ones first and what people wrote', (tester) async {
      MealRating rating(String meal, String name, int stars, {String? comment, List<RatingTag> tags = const []}) => MealRating(
            mealId: meal,
            mealName: meal,
            period: MealPeriod.lunch,
            serviceDate: dayOf(DateTime.now()),
            employeeName: name,
            stars: stars,
            tags: tags,
            comment: comment,
            createdAt: DateTime.now(),
          );
      final repository = FakeManagerRepository()
        ..ratingsValue = [
          rating('كباب', 'سارة', 5),
          rating('كباب', 'علي', 4),
          rating('دجاج', 'أحمد', 2, comment: 'كان بارداً', tags: [RatingTag.cold]),
        ];
      await _pumpPage(tester, const ReportsTab(), repository);
      await tester.scrollUntilVisible(find.byKey(const Key('ratings-count')), 300);
      expect(_keyText(tester, 'ratings-average'), '3.7 من 5');
      expect(_keyText(tester, 'ratings-count'), '3');
      expect(tester.getTopLeft(find.text('دجاج')).dy, lessThan(tester.getTopLeft(find.text('كباب')).dy));
      await tester.scrollUntilVisible(find.text('"كان بارداً"'), 300);
      expect(find.text('2 من 5 · أحمد'), findsOneWidget);
      expect(find.text('باردة'), findsOneWidget);
      expect(find.text('5 من 5 · سارة'), findsNothing);
    });
  });

  group('employee codes', () {
    Pickup pickup(String id, {bool mine = true}) => Pickup(
          bookingId: id,
          token: 'token-$id',
          shortCode: '48291$id',
          isMine: mine,
          ownerName: 'سارة',
          mealName: 'رز',
          pickupFrom: DateTime.now().add(const Duration(hours: 1)),
          pickupUntil: DateTime.now().add(const Duration(hours: 2)),
        );

    testWidgets('moves between codes and shows who each belongs to', (tester) async {
      final employee = FakeEmployeeRepository()..pickupsValue = [pickup('1'), pickup('2', mine: false)];
      await _pumpPage(tester, const CodesPage(startBookingId: '2'), FakeManagerRepository(), employee: employee);
      expect(_keyText(tester, 'code-counter'), '2 من 2');
      expect(find.text('وجبة سارة'), findsOneWidget);
      expect(tester.widget<QrImageView>(find.byKey(const Key('code-qr'))), isNotNull);
      await _tapKey(tester, 'code-next');
      expect(_keyText(tester, 'code-counter'), '1 من 2');
      expect(find.text('وجبتك أنت'), findsOneWidget);
    });

    testWidgets('a scanned meal turns into collected on its own', (tester) async {
      final employee = FakeEmployeeRepository()..pickupsValue = [pickup('1')];
      await _pumpPage(tester, const CodesPage(), FakeManagerRepository(), employee: employee);
      expect(find.byKey(const Key('code-qr')), findsOneWidget);
      employee.pickupsValue = const [];
      await tester.pump(const Duration(seconds: 6));
      await tester.pump();
      expect(find.byKey(const Key('code-done')), findsOneWidget);
      expect(find.byKey(const Key('code-qr')), findsNothing);
    });

    testWidgets('says so when nothing is waiting', (tester) async {
      await _pumpPage(tester, const CodesPage(), FakeManagerRepository(), employee: FakeEmployeeRepository());
      expect(find.text('لا توجد وجبات للاستلام الآن.'), findsOneWidget);
      expect(find.byKey(const Key('code-next-time')), findsNothing);
    });

    testWidgets('a later meal says when its code will appear', (tester) async {
      final from = DateTime.now().add(const Duration(hours: 3));
      final employee = FakeEmployeeRepository(bookingsValue: [
        Booking(
          id: 'b1',
          offeringId: 'o1',
          mealId: 'm1',
          mealName: 'كباب',
          serviceDate: dayOf(from),
          period: MealPeriod.lunch,
          amount: 5000,
          status: BookingStatus.booked,
          cancelUntil: from.subtract(const Duration(hours: 2)),
          pickupFrom: from,
          pickupUntil: from.add(const Duration(hours: 2)),
        ),
      ]);
      await _pumpPage(tester, const CodesPage(), FakeManagerRepository(), employee: employee);
      expect(find.byKey(const Key('code-qr')), findsNothing);
      expect(_keyText(tester, 'code-next-time'), contains('كباب'));
      expect(_keyText(tester, 'code-next-time'), contains(clock(from)));
    });

    testWidgets('a code that runs out of time is not shown as collected', (tester) async {
      final ended = Pickup(
        bookingId: '1',
        token: 'token-1',
        shortCode: '482911',
        isMine: true,
        ownerName: 'سارة',
        mealName: 'رز',
        pickupFrom: DateTime.now().subtract(const Duration(hours: 2)),
        pickupUntil: DateTime.now().subtract(const Duration(minutes: 1)),
      );
      final employee = FakeEmployeeRepository()..pickupsValue = [ended];
      await _pumpPage(tester, const CodesPage(), FakeManagerRepository(), employee: employee);
      employee.pickupsValue = const [];
      await tester.pump(const Duration(seconds: 6));
      await tester.pump();
      expect(find.byKey(const Key('code-expired')), findsOneWidget);
      expect(find.byKey(const Key('code-done')), findsNothing);
    });

    testWidgets('a delegated meal that opens later joins the codes', (tester) async {
      final employee = FakeEmployeeRepository()..pickupsValue = [pickup('1')];
      await _pumpPage(tester, const CodesPage(), FakeManagerRepository(), employee: employee);
      expect(_keyText(tester, 'code-counter'), '1 من 1');
      employee.pickupsValue = [pickup('1'), pickup('2', mine: false)];
      await tester.pump(const Duration(seconds: 6));
      await tester.pump();
      expect(_keyText(tester, 'code-counter'), '1 من 2');
    });
  });
}
