import '../../../core/api/api_exception.dart';
import '../data/profile_repository.dart';

/// Where the rider stands with authentication.
///
/// `profileIncomplete` is signed in but not usable: the auth user exists while
/// its profile row or date of birth does not. It is a distinct state because
/// signing the rider out would strand them with an account they cannot
/// recreate — the email is taken — and leaving them in the app would fail
/// every call with USER_NOT_FOUND.
enum AuthStatus { unknown, signedOut, signedIn, profileIncomplete }

class AuthSnapshot {
  final AuthStatus status;
  final RiderProfile? profile;
  final ApiException? error;
  final bool isBusy;

  const AuthSnapshot({
    this.status = AuthStatus.unknown,
    this.profile,
    this.error,
    this.isBusy = false,
  });

  AuthSnapshot copyWith({
    AuthStatus? status,
    RiderProfile? profile,
    ApiException? error,
    bool clearError = false,
    bool? isBusy,
  }) =>
      AuthSnapshot(
        status: status ?? this.status,
        profile: profile ?? this.profile,
        error: clearError ? null : (error ?? this.error),
        isBusy: isBusy ?? this.isBusy,
      );
}
