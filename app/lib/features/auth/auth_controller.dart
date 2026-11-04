import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_models.dart';
import 'auth_repository.dart';

final authControllerProvider = NotifierProvider<AuthController, AuthStatus>(AuthController.new);

class AuthController extends Notifier<AuthStatus> {
  AuthRepository get _repository => ref.read(authRepositoryProvider);

  @override
  AuthStatus build() {
    final subscription = ref.watch(authRepositoryProvider).changes.listen((_) => refresh());
    ref.onDispose(subscription.cancel);
    Future.microtask(refresh);
    return const AuthLoading();
  }

  /// Re-reads the account without showing a loading screen, so a background token
  /// refresh does not interrupt what the user is doing.
  Future<void> refresh() async {
    if (!_repository.hasSession) {
      state = const SignedOut();
      return;
    }
    try {
      final profile = await _repository.loadProfile();
      if (profile == null || !profile.isActive) {
        await _repository.signOut();
        state = const SignedOut();
      } else if (profile.mustChangePassword) {
        state = MustChangePassword(profile);
      } else {
        state = SignedIn(profile);
      }
    } on AuthFailure {
      // Keep a working screen open; only an app that has not started needs the retry page.
      if (state is AuthLoading) state = const AuthUnavailable();
    }
  }

  Future<void> retry() async {
    state = const AuthLoading();
    await refresh();
  }

  Future<void> signIn(String username, String password) async {
    await _repository.signIn(username, password);
    await refresh();
  }

  Future<void> changePassword(String password) async {
    await _repository.changePassword(password);
    await refresh();
  }

  Future<void> signOut() async {
    try {
      await _repository.signOut();
    } on AuthFailure {
      // Signing out must always work on this device, even offline.
    }
    state = const SignedOut();
  }
}
