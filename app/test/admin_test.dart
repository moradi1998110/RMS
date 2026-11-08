import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rms/core/theme.dart';
import 'package:rms/features/admin/admin_models.dart';
import 'package:rms/features/admin/admin_repository.dart';
import 'package:rms/features/admin/finance_page.dart';
import 'package:rms/features/admin/places_page.dart';
import 'package:rms/features/admin/summary_page.dart';
import 'package:rms/features/admin/users_page.dart';
import 'package:rms/features/auth/auth_models.dart';
import 'package:rms/features/employee/employee_models.dart';
import 'package:rms/shared/notice.dart';

const _place = Place(id: 'r1', siteId: 's1', name: 'مطعم الأول', siteName: 'الموقع الأول');
const _otherPlace = Place(id: 'r2', siteId: 's2', name: 'مطعم الثاني', siteName: 'الموقع الثاني');
const _admin = AdminUser(id: 'me', username: 'boss', fullName: 'مسؤول النظام', role: UserRole.admin);
const _ahmed = AdminUser(id: 'u1', username: 'ahmed', fullName: 'أحمد كريم', role: UserRole.employee, restaurantId: 'r1', restaurantName: 'مطعم الأول', available: 25000);
const _sara = AdminUser(id: 'u2', username: 'sara', fullName: 'سارة علي', role: UserRole.employee, restaurantId: 'r1', restaurantName: 'مطعم الأول', available: 12000);
const _left = AdminUser(id: 'u3', username: 'left', fullName: 'موظف معطل', role: UserRole.employee, restaurantId: 'r1', isActive: false);

class FakeAdminRepository implements AdminRepository {
  FakeAdminRepository({
    this.usersValue = const [_admin, _ahmed, _sara, _left],
    this.placesValue = const [_place, _otherPlace],
    this.rows = const [],
    this.liveBookings = 0,
  });

  List<AdminUser> usersValue;
  List<Place> placesValue;
  List<WeekRow> rows;
  int liveBookings;

  /// Thrown once by the next action, then cleared.
  AdminFailure? failNext;

  Map<String, Object?>? created;
  Map<String, Object?>? updated;
  String? resetId;
  (String, bool)? activeCall;
  (String, String)? addedPlace;
  final topUps = <(List<String>, int, String)>[];
  (int, DateTime, DateTime)? previewCall;
  (int, DateTime, DateTime, String)? savedRamadan;

  void _maybeFail() {
    final failure = failNext;
    failNext = null;
    if (failure != null) throw failure;
  }

  @override
  String? get currentUserId => 'me';

  @override
  Future<List<AdminUser>> users() async => usersValue;

  @override
  Future<List<Place>> places() async => placesValue;

  @override
  Future<List<RamadanPeriod>> ramadanPeriods() async => const [];

  @override
  Future<List<LedgerLine>> ledger() async => const [];

  @override
  Future<List<WeekRow>> weekRows(DateTime start) async => rows;

  @override
  Future<NewCredentials> createUser({required String fullName, required String username, String? department, required UserRole role, String? restaurantId}) async {
    _maybeFail();
    created = {'fullName': fullName, 'username': username, 'role': role, 'restaurantId': restaurantId};
    return NewCredentials(username: username, password: 'k7m3p9qa2d');
  }

  @override
  Future<void> updateUser(String id, {required String fullName, String? department, required UserRole role, Place? place}) async {
    _maybeFail();
    updated = {'id': id, 'fullName': fullName, 'role': role, 'placeId': place?.id};
  }

  @override
  Future<int> liveBookingCount(String id) async => liveBookings;

  @override
  Future<String> resetPassword(String id) async {
    _maybeFail();
    resetId = id;
    return 'n3w7pa55wd';
  }

  @override
  Future<void> setActive(String id, bool isActive) async {
    _maybeFail();
    activeCall = (id, isActive);
  }

  @override
  Future<void> addPlace({required String siteName, required String restaurantName}) async {
    _maybeFail();
    addedPlace = (siteName, restaurantName);
  }

  @override
  Future<void> topUp(List<String> employeeIds, int amount, String key) async {
    topUps.add((employeeIds, amount, key));
    _maybeFail();
  }

  @override
  Future<RamadanImpact> previewRamadan(int hijriYear, DateTime start, DateTime end) async {
    previewCall = (hijriYear, start, end);
    return const RamadanImpact(offerings: 3, bookings: 2);
  }

  @override
  Future<void> saveRamadan(int hijriYear, DateTime start, DateTime end, String key) async {
    savedRamadan = (hijriYear, start, end, key);
  }
}

Future<void> _pumpPage(WidgetTester tester, Widget page, FakeAdminRepository repository) async {
  tester.view.physicalSize = const Size(1170, 4800);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [adminRepositoryProvider.overrideWithValue(repository)],
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

void main() {
  group('rules', () {
    test('Ramadan dates map to their Hijri year, even when moved by the moon sighting', () {
      expect(hijriYearOf(DateTime(2027, 2, 8)), 1448);
      expect(hijriYearOf(DateTime(2027, 2, 6)), 1448);
      expect(hijriYearOf(DateTime(2027, 2, 10)), 1448);
      // 2030 holds two Ramadans.
      expect(hijriYearOf(DateTime(2030, 1, 5)), 1451);
      expect(hijriYearOf(DateTime(2030, 12, 26)), 1452);
    });

    test('a week starts on Saturday', () {
      expect(weekStartOf(DateTime(2026, 11, 5, 15)), DateTime(2026, 10, 31));
      expect(weekStartOf(DateTime(2026, 10, 31)), DateTime(2026, 10, 31));
      expect(weekStartOf(DateTime(2026, 11, 6)), DateTime(2026, 10, 31));
    });

    test('a new user needs a name, a valid login and a restaurant unless admin', () {
      String? problem(String name, String username, UserRole role, String? place) =>
          newUserProblem(fullName: name, username: username, role: role, restaurantId: place);
      expect(problem(' ', 'ahmed', UserRole.employee, 'r1'), isNotNull);
      expect(problem('أحمد', 'أحمد', UserRole.employee, 'r1'), usernameRule);
      expect(problem('أحمد', 'a b', UserRole.employee, 'r1'), usernameRule);
      expect(problem('أحمد', 'ab', UserRole.employee, 'r1'), usernameRule);
      expect(problem('أحمد', 'ahmed', UserRole.employee, null), isNotNull);
      expect(problem('أحمد', 'ahmed', UserRole.manager, null), isNotNull);
      expect(problem('أحمد', ' Ahmed.K ', UserRole.employee, 'r1'), isNull);
      expect(problem('أحمد', 'ahmed', UserRole.admin, null), isNull);
    });

    test('server codes become sentences', () {
      expect(AdminFailure.fromCode('username_taken').message, contains('مأخوذ'));
      expect(AdminFailure.fromCode('something_new').message, AdminFailure.unknown.message);
    });

    test('a user row is read, with the wallet as an object or a list', () {
      Map<String, dynamic> row(Object? wallets) => {
            'id': 'u1',
            'username': 'ahmed',
            'full_name': 'Ahmed Kareem',
            'department': null,
            'role': 'employee',
            'restaurant_id': 'r1',
            'is_active': true,
            'restaurants': {'name': 'مطعم'},
            'wallets': wallets,
          };
      expect(AdminUser.fromRow(row({'available': 500, 'held': 100})).available, 500);
      expect(AdminUser.fromRow(row([{'available': 700, 'held': 0}])).available, 700);
      final user = AdminUser.fromRow(row(null));
      expect(user.available, 0);
      expect(user.restaurantName, 'مطعم');
      expect(user.matches('AHMED'), isTrue);
      expect(user.matches(' kareem '), isTrue);
      expect(user.matches('sara'), isFalse);
    });

    test('the week counts served meals by day and every booking by outcome', () {
      final start = DateTime(2026, 10, 31);
      WeekRow row(DateTime date, MealPeriod period, BookingStatus status, [String place = 'r1']) =>
          WeekRow(date: date, period: period, status: status, restaurantId: place);
      final summary = WeekSummary.from(start, [
        row(start, MealPeriod.breakfast, BookingStatus.pickedUp),
        row(start, MealPeriod.lunch, BookingStatus.noShow),
        row(start, MealPeriod.lunch, BookingStatus.cancelled),
        row(DateTime(2026, 11, 1), MealPeriod.dinner, BookingStatus.booked, 'r2'),
        row(DateTime(2026, 11, 1), MealPeriod.dinner, BookingStatus.cancelledByRestaurant, 'r2'),
      ]);
      expect(summary.days.length, 7);
      expect(summary.days[0].lines, [1, 1, 0]);
      expect(summary.days[1].lines, [0, 0, 1]);
      expect(summary.collected, 1);
      expect(summary.notCollected, 1);
      expect(summary.waiting, 1);
      expect(summary.cancelled, 2);
      expect(summary.byRestaurant, {'r1': 2, 'r2': 1});
    });
  });

  group('users', () {
    testWidgets('creates an employee and shows the temporary password once', (tester) async {
      final repository = FakeAdminRepository();
      await _pumpPage(tester, const UsersPage(), repository);
      await _tapKey(tester, 'add-user');

      await tester.enterText(find.byKey(const Key('user-name')), 'حسن جواد');
      await tester.enterText(find.byKey(const Key('user-username')), 'Hassan');
      await tester.pumpAndSettle();
      await _tapKey(tester, 'place-r2');
      await _tapKey(tester, 'user-save');

      expect(repository.created?['fullName'], 'حسن جواد');
      expect(repository.created?['role'], UserRole.employee);
      expect(repository.created?['restaurantId'], 'r2');
      expect(tester.widget<SelectableText>(find.byKey(const Key('temporary-password'))).data, 'k7m3p9qa2d');

      await _tapKey(tester, 'password-done');
      expect(find.byKey(const Key('temporary-password')), findsNothing);
    });

    testWidgets('explains a bad form without calling the server', (tester) async {
      final repository = FakeAdminRepository();
      await _pumpPage(tester, const UsersPage(), repository);
      await _tapKey(tester, 'add-user');
      await tester.enterText(find.byKey(const Key('user-name')), 'حسن');
      await tester.enterText(find.byKey(const Key('user-username')), 'حسن');
      await tester.pumpAndSettle();
      await _tapKey(tester, 'user-save');
      expect(find.text(usernameRule), findsOneWidget);
      expect(repository.created, isNull);
    });

    testWidgets('an admin takes no restaurant', (tester) async {
      final repository = FakeAdminRepository();
      await _pumpPage(tester, const UsersPage(), repository);
      await _tapKey(tester, 'add-user');
      expect(find.byKey(const Key('place-r1')), findsOneWidget);
      await _tapKey(tester, 'role-admin');
      expect(find.byKey(const Key('place-r1')), findsNothing);
      await tester.enterText(find.byKey(const Key('user-name')), 'مسؤول');
      await tester.enterText(find.byKey(const Key('user-username')), 'admin2');
      await tester.pumpAndSettle();
      await _tapKey(tester, 'user-save');
      expect(repository.created?['role'], UserRole.admin);
      expect(repository.created?['restaurantId'], isNull);
      await _tapKey(tester, 'password-done');
    });

    testWidgets('shows why a taken username was refused', (tester) async {
      final repository = FakeAdminRepository()..failNext = AdminFailure.fromCode('username_taken');
      await _pumpPage(tester, const UsersPage(), repository);
      await _tapKey(tester, 'add-user');
      await tester.enterText(find.byKey(const Key('user-name')), 'أحمد');
      await tester.enterText(find.byKey(const Key('user-username')), 'ahmed');
      await tester.pumpAndSettle();
      await _tapKey(tester, 'place-r1');
      await _tapKey(tester, 'user-save');
      expect(find.text(AdminFailure.fromCode('username_taken').message), findsOneWidget);
      expect(find.byKey(const Key('temporary-password')), findsNothing);
    });

    testWidgets('search narrows the list', (tester) async {
      await _pumpPage(tester, const UsersPage(), FakeAdminRepository());
      expect(find.text('سارة علي'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('user-search')), 'ahmed');
      await tester.pumpAndSettle();
      expect(find.text('أحمد كريم'), findsOneWidget);
      expect(find.text('سارة علي'), findsNothing);
      await tester.enterText(find.byKey(const Key('user-search')), 'nobody');
      await tester.pumpAndSettle();
      expect(find.text('لا يوجد مستخدم بهذا الاسم.'), findsOneWidget);
    });

    testWidgets('edits role and restaurant', (tester) async {
      final repository = FakeAdminRepository();
      await _pumpPage(tester, const UsersPage(), repository);
      await _tapKey(tester, 'edit-ahmed');
      await _tapKey(tester, 'role-manager');
      await _tapKey(tester, 'place-r2');
      await _tapKey(tester, 'user-save');
      expect(repository.updated, {'id': 'u1', 'fullName': 'أحمد كريم', 'role': UserRole.manager, 'placeId': 'r2'});
      expect(find.text('حُفظت التعديلات'), findsOneWidget);
      await _closeNotice(tester);
    });

    testWidgets('refuses to move someone with open bookings, but allows other edits', (tester) async {
      final repository = FakeAdminRepository(liveBookings: 2);
      await _pumpPage(tester, const UsersPage(), repository);
      await _tapKey(tester, 'edit-ahmed');
      await _tapKey(tester, 'place-r2');
      await _tapKey(tester, 'user-save');
      expect(repository.updated, isNull);
      expect(find.textContaining('حجوزات قائمة (2)'), findsOneWidget);

      await _tapKey(tester, 'place-r1');
      await tester.enterText(find.byKey(const Key('user-name')), 'أحمد كريم علي');
      await tester.pumpAndSettle();
      await _tapKey(tester, 'user-save');
      expect(repository.updated?['fullName'], 'أحمد كريم علي');
      await _closeNotice(tester);
    });

    testWidgets('your own account cannot be reset, disabled or given another role', (tester) async {
      await _pumpPage(tester, const UsersPage(), FakeAdminRepository());
      expect(find.byKey(const Key('toggle-boss')), findsNothing);
      expect(find.byKey(const Key('reset-boss')), findsNothing);
      expect(find.text('هذا حسابك.'), findsOneWidget);
      await _tapKey(tester, 'edit-boss');
      expect(find.byKey(const Key('role-employee')), findsNothing);
    });

    testWidgets('resets a password after asking', (tester) async {
      final repository = FakeAdminRepository();
      await _pumpPage(tester, const UsersPage(), repository);
      await _tapKey(tester, 'reset-ahmed');
      expect(repository.resetId, isNull);
      await tester.tap(find.text('نعم، صفّرها'));
      await tester.pumpAndSettle();
      expect(repository.resetId, 'u1');
      expect(tester.widget<SelectableText>(find.byKey(const Key('temporary-password'))).data, 'n3w7pa55wd');
      await _tapKey(tester, 'password-done');
    });

    testWidgets('disabling asks first, enabling does not', (tester) async {
      final repository = FakeAdminRepository();
      await _pumpPage(tester, const UsersPage(), repository);
      await _tapKey(tester, 'toggle-ahmed');
      expect(repository.activeCall, isNull);
      await tester.tap(find.text('نعم، عطّله'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(repository.activeCall, ('u1', false));
      await _closeNotice(tester);

      await tester.tap(find.byKey(const Key('toggle-left')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(repository.activeCall, ('u3', true));
      await _closeNotice(tester);
    });

    testWidgets('a failed action says what happened', (tester) async {
      final repository = FakeAdminRepository()..failNext = AdminFailure.network;
      await _pumpPage(tester, const UsersPage(), repository);
      await _tapKey(tester, 'reset-ahmed');
      await tester.tap(find.text('نعم، صفّرها'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('لم تتم العملية'), findsOneWidget);
      expect(find.byKey(const Key('temporary-password')), findsNothing);
      await _closeNotice(tester);
    });
  });

  group('places', () {
    testWidgets('lists a restaurant with its manager and active employees', (tester) async {
      const manager = AdminUser(id: 'm1', username: 'mariam', fullName: 'مريم ناصر', role: UserRole.manager, restaurantId: 'r1');
      await _pumpPage(tester, const PlacesPage(), FakeAdminRepository(usersValue: const [_ahmed, _sara, _left, manager]));
      expect(find.text('المدير: مريم ناصر'), findsOneWidget);
      expect(find.text('الموظفون: 2'), findsOneWidget);
      expect(find.text('المدير: لم يُحدَّد بعد'), findsOneWidget);
    });

    testWidgets('adds a site and restaurant, and asks for both names', (tester) async {
      final repository = FakeAdminRepository();
      await _pumpPage(tester, const PlacesPage(), repository);
      await _tapKey(tester, 'add-place');
      await tester.enterText(find.byKey(const Key('place-site')), 'الموقع الثالث');
      await tester.pumpAndSettle();
      await _tapKey(tester, 'place-save');
      expect(find.text('اكتب اسم الموقع واسم المطعم.'), findsOneWidget);
      expect(repository.addedPlace, isNull);

      await tester.enterText(find.byKey(const Key('place-name')), 'مطعم الثالث');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('place-save')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(repository.addedPlace, ('الموقع الثالث', 'مطعم الثالث'));
      expect(find.text('أُضيف الموقع والمطعم'), findsOneWidget);
      await _closeNotice(tester);
    });

    testWidgets('Ramadan needs dates, shows the impact, then saves', (tester) async {
      final repository = FakeAdminRepository();
      await _pumpPage(tester, const PlacesPage(), repository);

      await tester.tap(find.byKey(const Key('ramadan-review')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text(datesRule), findsOneWidget);
      expect(repository.previewCall, isNull);
      await _closeNotice(tester);

      for (final field in ['ramadan-start', 'ramadan-end']) {
        await _tapKey(tester, field);
        await tester.tap(find.byType(TextButton).last); // the date picker's OK
        await tester.pumpAndSettle();
      }
      await _tapKey(tester, 'ramadan-review');
      expect(repository.previewCall, isNotNull);
      expect(find.textContaining('وترجع نقاط 2 حجز'), findsOneWidget);

      await tester.tap(find.byKey(const Key('ramadan-save')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(repository.savedRamadan, isNotNull);
      expect(repository.savedRamadan!.$1, hijriYearOf(repository.savedRamadan!.$2));
      expect(find.text('حُفظت تواريخ رمضان'), findsOneWidget);
      await _closeNotice(tester);
    });
  });

  group('finance', () {
    testWidgets('tops up the chosen employees with a suggested amount', (tester) async {
      final repository = FakeAdminRepository();
      await _pumpPage(tester, const FinancePage(), repository);
      expect(find.byKey(const Key('wallet-boss')), findsNothing);
      expect(find.byKey(const Key('wallet-left')), findsNothing);
      expect(find.byKey(const Key('topup-confirm')), findsNothing);

      await _tapKey(tester, 'wallet-ahmed');
      await _tapKey(tester, 'wallet-sara');
      await _tapKey(tester, 'amount-25000');
      expect(find.text('سيُشحن 2 موظف بـ 25,000 نقطة لكل واحد. المجموع 50,000 نقطة.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('topup-confirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(repository.topUps.single.$1, ['u1', 'u2']);
      expect(repository.topUps.single.$2, 25000);
      expect(find.text('تم الشحن'), findsOneWidget);
      await _closeNotice(tester);
      expect(find.byKey(const Key('topup-confirm')), findsNothing);
    });

    testWidgets('search then select all takes only the results', (tester) async {
      final repository = FakeAdminRepository();
      await _pumpPage(tester, const FinancePage(), repository);
      await tester.enterText(find.byKey(const Key('wallet-search')), 'sara');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('wallet-ahmed')), findsNothing);
      await _tapKey(tester, 'select-all');
      expect(find.textContaining('سيُشحن 1 موظف'), findsOneWidget);
    });

    testWidgets('a typed amount works and a retry reuses the key, but a new choice does not', (tester) async {
      final repository = FakeAdminRepository()..failNext = AdminFailure.network;
      await _pumpPage(tester, const FinancePage(), repository);
      await _tapKey(tester, 'wallet-ahmed');
      await tester.enterText(find.byKey(const Key('amount-field')), '1000');
      await tester.pumpAndSettle();

      await _tapKey(tester, 'topup-confirm');
      expect(find.text(AdminFailure.network.message), findsOneWidget);
      repository.failNext = AdminFailure.network;
      await _tapKey(tester, 'topup-confirm');
      expect(repository.topUps[0].$2, 1000);
      expect(repository.topUps[1].$3, repository.topUps[0].$3);

      await _tapKey(tester, 'amount-75000');
      await tester.tap(find.byKey(const Key('topup-confirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(repository.topUps[2].$2, 75000);
      expect(repository.topUps[2].$3, isNot(repository.topUps[0].$3));
      await _closeNotice(tester);
    });
  });

  group('summary', () {
    testWidgets('shows real counts, and a message when the week is empty', (tester) async {
      await _pumpPage(tester, const SummaryPage(), FakeAdminRepository());
      expect(find.text('37,000'), findsOneWidget); // 25,000 + 12,000 + 0
      expect(find.text('لا توجد حجوزات لهذا الأسبوع بعد.'), findsOneWidget);
      expect(find.text('نتيجة حجوزات هذا الأسبوع'), findsNothing);
    });

    testWidgets('the week chart shows a day when tapped, and as a table', (tester) async {
      final start = weekStartOf(DateTime.now());
      final repository = FakeAdminRepository(rows: [
        WeekRow(date: start, period: MealPeriod.lunch, status: BookingStatus.pickedUp, restaurantId: 'r1'),
        WeekRow(date: start, period: MealPeriod.lunch, status: BookingStatus.booked, restaurantId: 'r2'),
        WeekRow(date: start, period: MealPeriod.dinner, status: BookingStatus.noShow, restaurantId: 'r1'),
      ]);
      await _pumpPage(tester, const SummaryPage(), repository);
      expect(find.text('نتيجة حجوزات هذا الأسبوع'), findsOneWidget);
      expect(find.text('مطعم الأول'), findsOneWidget);

      await _tapKey(tester, 'chart-day-0');
      expect(find.text('السبت: 3 وجبة (فطور 0، غداء 2، عشاء 1)'), findsOneWidget);

      await _tapKey(tester, 'chart-toggle');
      expect(find.byType(Table), findsOneWidget);
      expect(find.text('الجمعة'), findsOneWidget);
    });
  });
}
