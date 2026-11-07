import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rms/core/router.dart';
import 'package:rms/core/theme.dart';
import 'package:rms/features/auth/auth_controller.dart';
import 'package:rms/features/auth/auth_models.dart';
import 'package:rms/features/auth/auth_repository.dart';
import 'package:rms/features/auth/change_password_screen.dart';
import 'package:rms/features/auth/login_screen.dart';
import 'package:rms/features/employee/account_page.dart';
import 'package:rms/features/employee/employee_repository.dart';
import 'package:rms/features/employee/employee_shell.dart';
import 'package:rms/shared/notice.dart';

import 'fake_employee_repository.dart';

const _employee = Profile(fullName: 'Test Employee', role: UserRole.employee, mustChangePassword: false, isActive: true);

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({this.session = false, this.profile, this.signInFailure, this.changeFailure});

  bool session;
  Profile? profile;
  AuthFailure? signInFailure;
  AuthFailure? changeFailure;
  bool profileFails = false;
  bool signedOut = false;
  String? usedUsername;
  String? usedPassword;
  String? newPassword;
  final _changes = StreamController<void>.broadcast();

  @override
  bool get hasSession => session;

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<void> signIn(String username, String password) async {
    usedUsername = username;
    usedPassword = password;
    if (signInFailure != null) throw signInFailure!;
    session = true;
  }

  @override
  Future<void> changePassword(String password) async {
    if (changeFailure != null) throw changeFailure!;
    newPassword = password;
    profile = _employee;
  }

  @override
  Future<void> signOut() async {
    signedOut = true;
    session = false;
  }

  @override
  Future<Profile?> loadProfile() async {
    if (profileFails) throw const AuthFailure(AuthFailureKind.network);
    return profile;
  }
}

Widget _app(Widget home, FakeAuthRepository repository) {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(repository),
      employeeRepositoryProvider.overrideWithValue(FakeEmployeeRepository()),
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
      home: home,
    ),
  );
}

Future<AuthStatus> _settled(FakeAuthRepository repository) async {
  final container = ProviderContainer(overrides: [authRepositoryProvider.overrideWithValue(repository)]);
  addTearDown(container.dispose);
  container.read(authControllerProvider);
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  return container.read(authControllerProvider);
}

void main() {
  group('usernames and passwords', () {
    test('a login ignores spaces and case', () {
      expect(normalizeUsername('  Ahmed.K '), 'ahmed.k');
      expect(loginEmail(' Ahmed '), 'ahmed@meals.invalid');
    });

    test('a new password needs 8 characters and a matching confirmation', () {
      expect(newPasswordProblem('short', 'short'), isNotNull);
      expect(newPasswordProblem('long-enough', 'different'), isNotNull);
      expect(newPasswordProblem('long-enough', 'long-enough'), isNull);
    });

    test('profile rows are read', () {
      final profile = Profile.fromRow({'full_name': 'A', 'role': 'manager', 'must_change_password': true, 'is_active': true});
      expect(profile.role, UserRole.manager);
      expect(profile.mustChangePassword, isTrue);
    });
  });

  group('routing', () {
    test('every account state has its own screen', () {
      Profile as(UserRole role) => Profile(fullName: 'A', role: role, mustChangePassword: false, isActive: true);
      expect(routeForStatus(const AuthLoading()), Routes.splash);
      expect(routeForStatus(const AuthUnavailable()), Routes.splash);
      expect(routeForStatus(const SignedOut()), Routes.login);
      expect(routeForStatus(MustChangePassword(as(UserRole.employee))), Routes.changePassword);
      expect(routeForStatus(SignedIn(as(UserRole.employee))), Routes.employee);
      expect(routeForStatus(SignedIn(as(UserRole.manager))), Routes.manager);
      expect(routeForStatus(SignedIn(as(UserRole.admin))), Routes.admin);
    });
  });

  group('account state', () {
    test('no session means signed out', () async {
      expect(await _settled(FakeAuthRepository()), isA<SignedOut>());
    });

    test('a working session signs in', () async {
      expect(await _settled(FakeAuthRepository(session: true, profile: _employee)), isA<SignedIn>());
    });

    test('a temporary password must be changed first', () async {
      const profile = Profile(fullName: 'A', role: UserRole.employee, mustChangePassword: true, isActive: true);
      expect(await _settled(FakeAuthRepository(session: true, profile: profile)), isA<MustChangePassword>());
    });

    test('a disabled account is signed out', () async {
      const profile = Profile(fullName: 'A', role: UserRole.employee, mustChangePassword: false, isActive: false);
      final repository = FakeAuthRepository(session: true, profile: profile);
      expect(await _settled(repository), isA<SignedOut>());
      expect(repository.signedOut, isTrue);
    });

    test('a login without a profile is signed out', () async {
      final repository = FakeAuthRepository(session: true);
      expect(await _settled(repository), isA<SignedOut>());
      expect(repository.signedOut, isTrue);
    });

    test('no network at startup offers a retry and keeps the session', () async {
      final repository = FakeAuthRepository(session: true, profile: _employee)..profileFails = true;
      expect(await _settled(repository), isA<AuthUnavailable>());
      expect(repository.signedOut, isFalse);
    });
  });

  group('login screen', () {
    testWidgets('asks for both fields', (tester) async {
      final repository = FakeAuthRepository();
      await tester.pumpWidget(_app(const LoginScreen(), repository));
      await tester.tap(find.byKey(const Key('login-submit')));
      await tester.pump();
      expect(find.text('اكتب اسم المستخدم وكلمة المرور.'), findsOneWidget);
      expect(repository.usedUsername, isNull);
    });

    testWidgets('explains a wrong password in Arabic', (tester) async {
      final repository = FakeAuthRepository(signInFailure: const AuthFailure(AuthFailureKind.invalidCredentials));
      await tester.pumpWidget(_app(const LoginScreen(), repository));
      await tester.enterText(find.byKey(const Key('login-username')), 'ahmed');
      await tester.enterText(find.byKey(const Key('login-password')), 'wrong-password');
      await tester.tap(find.byKey(const Key('login-submit')));
      await tester.pumpAndSettle();
      expect(find.text('اسم المستخدم أو كلمة المرور غير صحيحة.'), findsOneWidget);
    });

    testWidgets('sends what was typed', (tester) async {
      final repository = FakeAuthRepository(profile: _employee);
      await tester.pumpWidget(_app(const LoginScreen(), repository));
      await tester.enterText(find.byKey(const Key('login-username')), 'ahmed');
      await tester.enterText(find.byKey(const Key('login-password')), 'secret-word');
      await tester.tap(find.byKey(const Key('login-submit')));
      await tester.pumpAndSettle();
      expect(repository.usedUsername, 'ahmed');
      expect(repository.usedPassword, 'secret-word');
    });
  });

  group('change password screen', () {
    testWidgets('refuses a mismatch without calling the server', (tester) async {
      final repository = FakeAuthRepository(session: true);
      await tester.pumpWidget(_app(const ChangePasswordScreen(), repository));
      await tester.enterText(find.byKey(const Key('password-new')), 'long-enough');
      await tester.enterText(find.byKey(const Key('password-confirm')), 'different-one');
      await tester.tap(find.byKey(const Key('password-submit')));
      await tester.pump();
      expect(find.text('الكلمتان غير متطابقتين.'), findsOneWidget);
      expect(repository.newPassword, isNull);
    });

    testWidgets('saves a valid password and shows the notice', (tester) async {
      final repository = FakeAuthRepository(session: true);
      await tester.pumpWidget(_app(const ChangePasswordScreen(), repository));
      await tester.enterText(find.byKey(const Key('password-new')), 'long-enough');
      await tester.enterText(find.byKey(const Key('password-confirm')), 'long-enough');
      await tester.tap(find.byKey(const Key('password-submit')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(repository.newPassword, 'long-enough');
      expect(find.text('تم تغيير كلمة المرور'), findsOneWidget);
      await tester.pump(noticeDuration);
      await tester.pumpAndSettle();
    });
  });

  group('notice', () {
    Widget host(void Function(BuildContext) open) => MaterialApp(
          theme: appTheme(),
          home: Builder(
            builder: (context) => Scaffold(body: TextButton(onPressed: () => open(context), child: const Text('open'))),
          ),
        );

    testWidgets('closes by itself', (tester) async {
      await tester.pumpWidget(host((context) => showNotice(context, kind: NoticeKind.done, title: 'تم الحجز')));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('تم الحجز'), findsOneWidget);
      await tester.pump(noticeDuration);
      await tester.pumpAndSettle();
      expect(find.text('تم الحجز'), findsNothing);
    });

    testWidgets('closes when tapped', (tester) async {
      await tester.pumpWidget(host((context) => showNotice(context, kind: NoticeKind.refund, title: 'أُلغي الحجز', text: 'رجع المبلغ')));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('أُلغي الحجز'));
      await tester.pumpAndSettle();
      expect(find.text('أُلغي الحجز'), findsNothing);
    });

    testWidgets('vibrates', (tester) async {
      final calls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'HapticFeedback.vibrate') calls.add(call.method);
        return null;
      });
      await tester.pumpWidget(host((context) => showNotice(context, kind: NoticeKind.done, title: 'تم')));
      await tester.tap(find.text('open'));
      await tester.pump();
      expect(calls, isNotEmpty);
      await tester.pump(noticeDuration);
      await tester.pumpAndSettle();
    });
  });

  group('role frame', () {
    testWidgets('the dock switches pages and keeps every label', (tester) async {
      final repository = FakeAuthRepository(session: true, profile: _employee);
      await tester.pumpWidget(_app(const EmployeeShell(), repository));
      await tester.pumpAndSettle();
      expect(find.text('الوجبات'), findsWidgets);
      expect(find.text('حجوزاتي'), findsWidgets);
      expect(find.text('حسابي'), findsWidgets);
      expect(find.byType(IndexedStack), findsOneWidget);
      await tester.tap(find.text('حسابي').first);
      await tester.pumpAndSettle();
      expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 2);
    });

    testWidgets('a page is built only once opened, then kept', (tester) async {
      final repository = FakeAuthRepository(session: true, profile: _employee);
      await tester.pumpWidget(_app(const EmployeeShell(), repository));
      await tester.pumpAndSettle();
      expect(find.byType(AccountPage, skipOffstage: false), findsNothing);
      await tester.tap(find.text('حسابي').first);
      await tester.pumpAndSettle();
      expect(find.byType(AccountPage, skipOffstage: false), findsOneWidget);
      await tester.tap(find.text('الوجبات').first);
      await tester.pumpAndSettle();
      expect(find.byType(AccountPage, skipOffstage: false), findsOneWidget);
    });

    testWidgets('signing out asks first', (tester) async {
      final repository = FakeAuthRepository(session: true, profile: _employee);
      await tester.pumpWidget(_app(const EmployeeShell(), repository));
      await tester.pumpAndSettle();
      await tester.tap(find.text('خروج'));
      await tester.pumpAndSettle();
      expect(repository.signedOut, isFalse);
      await tester.tap(find.text('نعم، اخرج'));
      await tester.pumpAndSettle();
      expect(repository.signedOut, isTrue);
    });
  });
}
