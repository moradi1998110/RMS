import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/admin/admin_shell.dart';
import '../features/auth/auth_controller.dart';
import '../features/auth/auth_models.dart';
import '../features/auth/change_password_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/splash_screen.dart';
import '../features/employee/employee_shell.dart';
import '../features/manager/manager_shell.dart';

class Routes {
  const Routes._();

  static const splash = '/';
  static const login = '/login';
  static const changePassword = '/change-password';
  static const employee = '/employee';
  static const manager = '/manager';
  static const admin = '/admin';
}

/// Each account state has exactly one screen it may be on.
String routeForStatus(AuthStatus status) => switch (status) {
      AuthLoading() || AuthUnavailable() => Routes.splash,
      SignedOut() => Routes.login,
      MustChangePassword() => Routes.changePassword,
      SignedIn(profile: final profile) => switch (profile.role) {
          UserRole.employee => Routes.employee,
          UserRole.manager => Routes.manager,
          UserRole.admin => Routes.admin,
        },
    };

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.onDispose(refresh.dispose);
  ref.listen(authControllerProvider, (_, __) => refresh.value++);

  final router = GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: (context, state) {
      final target = routeForStatus(ref.read(authControllerProvider));
      return state.matchedLocation == target ? null : target;
    },
    routes: [
      GoRoute(path: Routes.splash, builder: (_, __) => const SplashScreen()),
      GoRoute(path: Routes.login, builder: (_, __) => const LoginScreen()),
      GoRoute(path: Routes.changePassword, builder: (_, __) => const ChangePasswordScreen()),
      GoRoute(path: Routes.employee, builder: (_, __) => const EmployeeShell()),
      GoRoute(path: Routes.manager, builder: (_, __) => const ManagerShell()),
      GoRoute(path: Routes.admin, builder: (_, __) => const AdminShell()),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
