import '../../../core/api/api_exception.dart';
import '../data/profile_repository.dart';

/// Where the rider stands with authentication.
///
/// `profileIncomplete` is signed in but not usable: the auth user exists while
/// its profile ROW does not, so every authenticated call fails with
/// USER_NOT_FOUND. It is a distinct state because signing the rider out would
/// strand them with an account they cannot recreate — the email is taken.
///
/// A missing date of birth is NOT this state. That is an ordinary signed-in
/// rider who cannot book yet; see [AuthSnapshot.canBook].
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

  /// Whether this rider may actually book a ride.
  ///
  /// The age gate lives HERE rather than at sign-in. The backend's booking
  /// check treats a null date of birth as ALLOWED, so if the app does not
  /// enforce it nobody does — but enforcing it at the door locked riders with
  /// a real profile out of the whole app over one empty field.
  ///
  /// Every path that starts a booking must consult this and send a rider with
  /// no date of birth to collect one first.
  bool get canBook =>
      status == AuthStatus.signedIn && profile?.needsDateOfBirth == false;

  /// True when the only thing standing between this rider and booking is a
  /// missing date of birth — the case worth prompting for, as opposed to a
  /// rider who is simply signed out.
  bool get needsDateOfBirthToBook =>
      status == AuthStatus.signedIn && profile?.needsDateOfBirth == true;

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
