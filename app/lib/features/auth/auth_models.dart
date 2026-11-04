enum UserRole { admin, manager, employee }

class Profile {
  const Profile({
    required this.fullName,
    required this.role,
    required this.mustChangePassword,
    required this.isActive,
  });

  final String fullName;
  final UserRole role;
  final bool mustChangePassword;
  final bool isActive;

  factory Profile.fromRow(Map<String, dynamic> row) => Profile(
        fullName: row['full_name'] as String,
        role: UserRole.values.byName(row['role'] as String),
        mustChangePassword: row['must_change_password'] as bool,
        isActive: row['is_active'] as bool,
      );
}

sealed class AuthStatus {
  const AuthStatus();
}

class AuthLoading extends AuthStatus {
  const AuthLoading();
}

class SignedOut extends AuthStatus {
  const SignedOut();
}

/// Signed in, but the account could not be read, usually because of the network.
class AuthUnavailable extends AuthStatus {
  const AuthUnavailable();
}

class MustChangePassword extends AuthStatus {
  const MustChangePassword(this.profile);
  final Profile profile;
}

class SignedIn extends AuthStatus {
  const SignedIn(this.profile);
  final Profile profile;
}

enum AuthFailureKind { invalidCredentials, accountDisabled, samePassword, weakPassword, tooManyAttempts, network, unknown }

class AuthFailure implements Exception {
  const AuthFailure(this.kind);
  final AuthFailureKind kind;

  String get message => switch (kind) {
        AuthFailureKind.invalidCredentials => 'اسم المستخدم أو كلمة المرور غير صحيحة.',
        AuthFailureKind.accountDisabled => 'هذا الحساب معطّل. راجع مسؤول النظام.',
        AuthFailureKind.samePassword => 'اختر كلمة مرور مختلفة عن الحالية.',
        AuthFailureKind.weakPassword => 'كلمة المرور ضعيفة. اختر كلمة أقوى.',
        AuthFailureKind.tooManyAttempts => 'محاولات كثيرة. انتظر قليلاً ثم حاول مرة أخرى.',
        AuthFailureKind.network => 'تعذّر الاتصال. تأكد من الإنترنت ثم حاول مرة أخرى.',
        AuthFailureKind.unknown => 'حدث خطأ. حاول مرة أخرى.',
      };
}

/// The username is the login, stored in lower case on a domain that never receives mail.
String normalizeUsername(String input) => input.trim().toLowerCase();

String loginEmail(String username) => '${normalizeUsername(username)}@meals.invalid';

String? newPasswordProblem(String password, String confirmation) {
  if (password.length < 8) return 'اكتب 8 أحرف أو أرقام على الأقل.';
  if (password != confirmation) return 'الكلمتان غير متطابقتين.';
  return null;
}
