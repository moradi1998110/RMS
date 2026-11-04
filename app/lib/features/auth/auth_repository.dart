import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_models.dart';

abstract class AuthRepository {
  bool get hasSession;
  Stream<void> get changes;
  Future<void> signIn(String username, String password);
  Future<void> changePassword(String password);
  Future<void> signOut();
  Future<Profile?> loadProfile();
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => SupabaseAuthRepository(Supabase.instance.client),
);

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._client);

  final SupabaseClient _client;

  @override
  bool get hasSession => _client.auth.currentSession != null;

  @override
  Stream<void> get changes => _client.auth.onAuthStateChange.map((_) {});

  @override
  Future<void> signIn(String username, String password) =>
      _guard(() => _client.auth.signInWithPassword(email: loginEmail(username), password: password));

  @override
  Future<void> changePassword(String password) => _guard(() async {
        await _client.auth.updateUser(UserAttributes(password: password));
        await _client.rpc('mark_password_changed');
      });

  @override
  Future<void> signOut() => _guard(() => _client.auth.signOut());

  @override
  Future<Profile?> loadProfile() => _guard(() async {
        final userId = _client.auth.currentUser?.id;
        if (userId == null) return null;
        final row = await _client
            .from('profiles')
            .select('full_name, role, must_change_password, is_active')
            .eq('id', userId)
            .maybeSingle();
        return row == null ? null : Profile.fromRow(row);
      });

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on AuthException catch (error) {
      throw AuthFailure(_kindOf(error));
    } on PostgrestException {
      throw const AuthFailure(AuthFailureKind.unknown);
    } on Exception {
      // Connection errors arrive as several different types depending on the layer.
      throw const AuthFailure(AuthFailureKind.network);
    }
  }

  AuthFailureKind _kindOf(AuthException error) {
    if (error is AuthRetryableFetchException) return AuthFailureKind.network;
    return switch (error.code) {
      'invalid_credentials' => AuthFailureKind.invalidCredentials,
      'user_banned' => AuthFailureKind.accountDisabled,
      'same_password' => AuthFailureKind.samePassword,
      'weak_password' => AuthFailureKind.weakPassword,
      'over_request_rate_limit' => AuthFailureKind.tooManyAttempts,
      _ => AuthFailureKind.unknown,
    };
  }
}
