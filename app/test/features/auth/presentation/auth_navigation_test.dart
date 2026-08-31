import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/api/api_exception.dart';
import 'package:hoppin_rider/core/result.dart';
import 'package:hoppin_rider/features/auth/application/auth_controller.dart';
import 'package:hoppin_rider/features/auth/data/auth_repository.dart';
import 'package:hoppin_rider/features/auth/data/profile_repository.dart';
import 'package:hoppin_rider/features/auth/domain/auth_state.dart';
import 'package:hoppin_rider/features/auth/presentation/login_screen.dart';
import 'package:hoppin_rider/features/auth/presentation/signup_screen.dart';
import 'package:hoppin_rider/shared/nav/app_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Navigation between the auth screens, driven through the REAL router.
///
/// The per-screen tests mount each widget directly under `MaterialApp(home:)`,
/// which cannot see whether a screen is reachable. A whole-branch review found
/// that the sign-up screen had no route into it at all: every screen worked,
/// every test passed, and a new rider could only ever look at the login form.
/// These tests exist so that class of bug cannot come back.
class _MockAuthRepo extends Mock implements AuthRepository {}

class _MockProfileRepo extends Mock implements ProfileRepository {}

Session _session() => Session(
      accessToken: 'token',
      tokenType: 'bearer',
      user: User(
        id: 'uid',
        appMetadata: const {},
        userMetadata: const {},
        aud: 'authenticated',
        createdAt: DateTime.now().toIso8601String(),
      ),
    );

RiderProfile _profile({String? dob}) => RiderProfile(
      fullName: 'Ada',
      phoneNumber: null,
      email: 'a@b.com',
      avatarUrl: null,
      dateOfBirth: dob,
      rating: null,
      ratingCount: 0,
    );

void main() {
  late _MockAuthRepo auth;
  late _MockProfileRepo profiles;

  setUp(() {
    auth = _MockAuthRepo();
    profiles = _MockProfileRepo();
    when(() => auth.currentSession).thenReturn(null);
  });

  ProviderContainer container() {
    final c = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      profileRepositoryProvider.overrideWithValue(profiles),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  Future<void> pumpApp(WidgetTester tester, ProviderContainer c) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp.router(routerConfig: c.read(appRouterProvider)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a new rider can reach sign-up from login', (tester) async {
    // The bug this guards: with no link, the app opens on login and the
    // redirect keeps a signed-out rider on an auth route, so sign-up — and
    // with it the DOB picker and the entire age gate — was unreachable.
    final c = container();
    c.read(authControllerProvider.notifier).state =
        const AuthSnapshot(status: AuthStatus.signedOut);
    await pumpApp(tester, c);

    expect(find.byType(LoginScreen), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Sign up'));
    await tester.pumpAndSettle();

    expect(find.byType(SignupScreen), findsOneWidget);
  });

  testWidgets('and can get back to login from sign-up', (tester) async {
    final c = container();
    c.read(authControllerProvider.notifier).state =
        const AuthSnapshot(status: AuthStatus.signedOut);
    await pumpApp(tester, c);

    await tester.tap(find.widgetWithText(TextButton, 'Sign up'));
    await tester.pumpAndSettle();

    // The sign-up form scrolls past the test viewport, so the link at its foot
    // has to be brought into view first — the same thing a rider does.
    final loginLink = find.widgetWithText(TextButton, 'Login');
    await tester.ensureVisible(loginLink);
    await tester.pumpAndSettle();
    await tester.tap(loginLink);
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
  });

  group('bootstrap', () {
    testWidgets('a returning rider with a session lands past login',
        (tester) async {
      // Nothing else moves the app off AuthStatus.unknown, and redirectFor
      // declines to redirect while unknown — so without bootstrap a rider
      // with a valid persisted session sat on the login screen forever.
      when(() => auth.currentSession).thenReturn(_session());
      when(() => profiles.get())
          .thenAnswer((_) async => Ok(_profile(dob: '1990-12-10')));

      final c = container();
      await c.read(authControllerProvider.notifier).bootstrap();
      await pumpApp(tester, c);

      expect(c.read(authControllerProvider).status, AuthStatus.signedIn);
      expect(find.byType(LoginScreen), findsNothing);
    });

    testWidgets('no session resolves to signedOut rather than staying unknown',
        (tester) async {
      when(() => auth.currentSession).thenReturn(null);

      final c = container();
      await c.read(authControllerProvider.notifier).bootstrap();
      await pumpApp(tester, c);

      expect(c.read(authControllerProvider).status, AuthStatus.signedOut);
      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets(
        'a restored session with no date of birth signs in but cannot book',
        (tester) async {
      // This used to park the rider on the sign-up screen, which locked an
      // existing rider with a real profile out of the whole app over one
      // null field. The age gate the old behaviour protected still holds —
      // the backend treats a null DOB as allowed, so the app enforces it —
      // but at booking, via canBook, not at the door.
      when(() => auth.currentSession).thenReturn(_session());
      when(() => profiles.get())
          .thenAnswer((_) async => Ok(_profile(dob: null)));

      final c = container();
      await c.read(authControllerProvider.notifier).bootstrap();
      await pumpApp(tester, c);

      final snapshot = c.read(authControllerProvider);
      expect(snapshot.status, AuthStatus.signedIn);
      expect(find.byType(SignupScreen), findsNothing,
          reason: 'an existing rider must not be held at the sign-up door');
      expect(snapshot.canBook, isFalse,
          reason: 'the age gate moved to booking, it did not disappear');
      expect(snapshot.needsDateOfBirthToBook, isTrue);
    });
  });

  testWidgets('an unrecoverable profile failure offers a way out',
      (tester) async {
    // USER_NOT_FOUND means no profile row exists, so the PATCH has nothing to
    // write to and retrying can never succeed. Without a distinct branch the
    // rider is locked on sign-up: pinned there by the redirect, unable to
    // retry, unable to sign out.
    when(() => auth.currentSession).thenReturn(_session());
    when(() => profiles.get()).thenAnswer(
        (_) async => Err(ApiException('USER_NOT_FOUND', 'no profile', 404)));

    final c = container();
    await c.read(authControllerProvider.notifier).bootstrap();
    await pumpApp(tester, c);

    expect(find.byType(SignupScreen), findsOneWidget);
    expect(find.textContaining('contact support'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Finish setting up'), findsNothing);
  });
}
