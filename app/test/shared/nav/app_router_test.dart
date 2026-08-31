import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/features/auth/application/auth_controller.dart';
import 'package:hoppin_rider/features/auth/data/auth_repository.dart';
import 'package:hoppin_rider/features/auth/data/profile_repository.dart';
import 'package:hoppin_rider/features/auth/domain/auth_state.dart';
import 'package:hoppin_rider/shared/nav/app_router.dart';
import 'package:mocktail/mocktail.dart';

class _MockAuthRepo extends Mock implements AuthRepository {}

class _MockProfileRepo extends Mock implements ProfileRepository {}

void main() {
  group('redirectFor', () {
    test('sends a signed-out rider to login', () {
      expect(redirectFor(AuthStatus.signedOut, '/home'), AppRoutes.login);
    });

    test('leaves a signed-out rider alone on signup', () {
      expect(redirectFor(AuthStatus.signedOut, AppRoutes.signup), isNull,
          reason: 'bouncing them off signup would make signing up impossible');
    });

    test('sends a signed-in rider away from login', () {
      expect(redirectFor(AuthStatus.signedIn, AppRoutes.login), AppRoutes.home);
    });

    test('holds an incomplete profile on signup to finish it', () {
      expect(redirectFor(AuthStatus.profileIncomplete, '/home'),
          AppRoutes.signup);
    });

    test('does not redirect while auth state is still unknown', () {
      expect(redirectFor(AuthStatus.unknown, '/home'), isNull,
          reason: 'redirecting before the session is restored would flash '
              'the login screen at an already signed-in rider');
    });
  });

  group('router reacts to auth changes', () {
    testWidgets('a rider who signs in is moved off the login screen',
        (tester) async {
      // The pure redirectFor tests cannot catch this: the rules can all be
      // right while the router never re-evaluates them. Without a
      // refreshListenable a successful sign-in leaves the rider sitting on
      // the login screen, which is the entire point of this batch.
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(_MockAuthRepo()),
          profileRepositoryProvider.overrideWithValue(_MockProfileRepo()),
        ],
      );
      addTearDown(container.dispose);

      final router = container.read(appRouterProvider);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      // Starts signed out, so the redirect holds the rider on login.
      expect(find.byType(MaterialApp), findsOneWidget);
      expect(router.state.matchedLocation, AppRoutes.login);

      // Sign-in succeeds elsewhere in the app; only the status changes.
      container.read(authControllerProvider.notifier).state =
          const AuthSnapshot(status: AuthStatus.signedIn);
      await tester.pumpAndSettle();

      expect(router.state.matchedLocation, AppRoutes.home,
          reason: 'the router must re-evaluate when auth status changes');
    });
  });
}
