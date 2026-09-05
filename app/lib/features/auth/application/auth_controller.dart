import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/device/device_checkin.dart';
import '../../../core/push/push_registrar.dart';
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

  /// Fired (and awaited by nobody) each time the rider lands on signedIn —
  /// carries the device fingerprint check-in. Injected so tests need no
  /// network.
  final Future<void> Function()? _onSignedIn;

  AuthController(this._auth, this._profiles, {Future<void> Function()? onSignedIn})
      : _onSignedIn = onSignedIn,
        super(const AuthSnapshot());

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
    await _loadProfile(silentAuthFailure: true);
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
    if (state.status == AuthStatus.signedIn) _onSignedIn?.call();
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
  ///
  /// [silentAuthFailure] is set on launch. A session that has simply expired is
  /// the ordinary end of a session, not something that went wrong: the rider
  /// should meet the login screen, not the login screen with "unauthorized"
  /// printed above it in red. Off a deliberate sign-in attempt the same failure
  /// IS worth reporting, so the flag is per-call rather than a mode.
  Future<void> _loadProfile({bool silentAuthFailure = false}) async {
    final profile = await _profiles.get();

    state = switch (profile) {
      // A missing date of birth does NOT hold the rider at the door.
      //
      // It used to: `needsDateOfBirth` parked them in profileIncomplete, and
      // the router forces that status to /signup. An existing rider with a
      // real profile — rating, avatar, history — was therefore locked out of
      // every screen in the app because one field was null, with a sign-up
      // form as the only way forward. That is a worse failure than the one it
      // was guarding against.
      //
      // The guard it replaces still matters: the backend's booking check
      // treats a null DOB as ALLOWED, so the age gate has to be enforced
      // here. It is enforced where it bites — at booking — via
      // [RiderProfile.needsDateOfBirth], not at sign-in.
      Ok(:final value) => AuthSnapshot(
          status: AuthStatus.signedIn,
          profile: value,
        ),
      // Only a profile that genuinely is not there means the account is
      // half-made. Anything else — a network failure, a 5xx, CORS on the web
      // build — is a transient error, and treating it as profileIncomplete
      // strands the rider on the sign-up screen with an account that is
      // actually fine. That is a far worse outcome than showing an error and
      // letting them retry.
      Err(:final error) => AuthSnapshot(
          status: error.code == 'USER_NOT_FOUND'
              ? AuthStatus.profileIncomplete
              : AuthStatus.signedOut,
          error: silentAuthFailure && _isDeadSession(error) ? null : error,
        ),
    };
    // Drop the dead session with it, or every launch repeats the same doomed
    // refresh before landing on the same login screen.
    if (state.status == AuthStatus.signedOut &&
        state.error == null &&
        _auth.currentSession != null) {
      await _auth.signOut();
    }
    if (state.status == AuthStatus.signedIn) _onSignedIn?.call();
  }

  /// True when the failure means "this session simply ran out" rather than
  /// "something went wrong".
  ///
  /// A network error on launch must NOT qualify — silently signing out a rider
  /// whose train went into a tunnel loses their session for a reason that has
  /// nothing to do with their session. Nor do the terminal-auth codes:
  /// suspended, banned, blacklisted, signed-in-elsewhere all carry an
  /// explanation the rider needs, and dropping it leaves them at a login screen
  /// that will keep refusing them without ever saying why.
  static bool _isDeadSession(ApiException e) =>
      !e.isTerminalAuth && (e.status == 401 || e.code == 'UNAUTHORIZED');
}

final authControllerProvider =
    StateNotifierProvider<AuthController, AuthSnapshot>(
  (ref) => AuthController(
    ref.watch(authRepositoryProvider),
    ref.watch(profileRepositoryProvider),
    // Lazy and swallowed: both reports need the live app bootstrap
    // (Supabase session behind the API client) and must never break
    // sign-in — or a test harness that has neither. The push registration
    // is what routes notifications to THIS device (it retires the
    // account's other tokens server-side).
    onSignedIn: () async {
      try {
        await ref.read(deviceCheckinProvider).report();
      } catch (_) {}
      try {
        await ref.read(pushRegistrarProvider).register();
      } catch (_) {}
    },
  ),
);
