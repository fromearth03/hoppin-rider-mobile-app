import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/result.dart';
import '../data/auth_repository.dart';
import '../data/profile_repository.dart';
import '../domain/auth_state.dart';
import '../domain/dob_validator.dart';

/// Owns sign-in, sign-up and the two-step profile completion.
///
/// Sign-up is two writes: Supabase creates the auth user, then
/// `PATCH /me/profile` stores the date of birth, because `signUp` has no DOB
/// field. If the second fails the account still exists with a null DOB — which
/// the booking guard treats as ALLOWED — so the app must not simply continue.
/// It parks in [AuthStatus.profileIncomplete] and retries.
class AuthController extends StateNotifier<AuthSnapshot> {
  final AuthRepository _auth;
  final ProfileRepository _profiles;

  AuthController(this._auth, this._profiles) : super(const AuthSnapshot());

  /// Resolves the startup state, moving the app off [AuthStatus.unknown].
  ///
  /// Without this a returning rider with a valid persisted Supabase session
  /// cold-starts onto the login screen and stays there: `redirectFor` returns
  /// null for `unknown` by design, waiting for someone to say what the state
  /// actually is. Nothing was saying.
  ///
  /// It also closes the null-DOB hole. The spec requires the app to retry the
  /// date-of-birth write on launch whenever the profile has none — a rider who
  /// dismissed recovery once would otherwise be silently booking-eligible
  /// forever, because the backend's booking guard treats a null DOB as
  /// allowed. `_loadProfile` parks them in `profileIncomplete` instead.
  Future<void> bootstrap() async {
    if (_auth.currentSession == null) {
      state = const AuthSnapshot(status: AuthStatus.signedOut);
      return;
    }
    await _loadProfile();
  }

  Future<void> signIn(String email, String password) async {
    state = state.copyWith(isBusy: true, clearError: true);

    final result = await _auth.signIn(email, password);
    if (result case Err(:final error)) {
      state = AuthSnapshot(status: AuthStatus.signedOut, error: error);
      return;
    }
    await _loadProfile();
  }

  Future<void> signUp({
    required String email,
    required String password,
    required String fullName,
    required DateTime? dateOfBirth,
    String? phone,
  }) async {
    final invalid = DobValidator.validate(dateOfBirth);
    if (invalid != null) {
      state = state.copyWith(
        isBusy: false,
        error: ApiException('VALIDATION_FAILED', invalid, 0),
      );
      return;
    }

    state = state.copyWith(isBusy: true, clearError: true);

    final created = await _auth.signUp(
      email: email,
      password: password,
      fullName: fullName,
      phone: phone,
    );
    if (created case Err(:final error)) {
      state = AuthSnapshot(status: AuthStatus.signedOut, error: error);
      return;
    }

    await completeProfile(dateOfBirth!);
  }

  /// Writes the date of birth. Also the recovery path: the sign-up screen
  /// calls it again after a failure, and the launch sequence calls it when a
  /// restored session has no DOB stored.
  ///
  /// A `USER_NOT_FOUND` here means the auth user exists without a profile row
  /// — the failure migration 124 describes, where the signup trigger swallowed
  /// its own error into a warning. Surfaced, never retried silently.
  Future<void> completeProfile(DateTime dateOfBirth) async {
    state = state.copyWith(isBusy: true, clearError: true);

    final patched = await _profiles.patch(
      dateOfBirth: DobValidator.format(dateOfBirth),
    );

    state = switch (patched) {
      Ok(:final value) => AuthSnapshot(
          status: AuthStatus.signedIn,
          profile: value,
        ),
      Err(:final error) => state.copyWith(
          status: AuthStatus.profileIncomplete,
          error: error,
          isBusy: false,
        ),
    };
  }

  Future<void> signOut() async {
    await _auth.signOut();
    state = const AuthSnapshot(status: AuthStatus.signedOut);
  }

  /// Sends a password-reset email.
  ///
  /// Returns whether the request was accepted so the screen can swap to its
  /// "check your inbox" state. This deliberately does NOT touch [AuthStatus]:
  /// the rider is signed out before and after, and moving the status would
  /// bounce them through the router mid-flow.
  Future<bool> requestPasswordReset(String email) async {
    state = state.copyWith(isBusy: true, clearError: true);

    final result = await _auth.requestPasswordReset(email);
    return switch (result) {
      Ok() => () {
          state = state.copyWith(isBusy: false, clearError: true);
          return true;
        }(),
      Err(:final error) => () {
          state = state.copyWith(isBusy: false, error: error);
          return false;
        }(),
    };
  }

  /// Reads the profile and decides whether the rider can actually use the app.
  Future<void> _loadProfile() async {
    final profile = await _profiles.get();

    state = switch (profile) {
      Ok(:final value) => AuthSnapshot(
          status: value.needsDateOfBirth
              ? AuthStatus.profileIncomplete
              : AuthStatus.signedIn,
          profile: value,
        ),
      Err(:final error) => AuthSnapshot(
          status: AuthStatus.profileIncomplete,
          error: error,
        ),
    };
  }
}

final authControllerProvider =
    StateNotifierProvider<AuthController, AuthSnapshot>(
  (ref) => AuthController(
    ref.watch(authRepositoryProvider),
    ref.watch(profileRepositoryProvider),
  ),
);
