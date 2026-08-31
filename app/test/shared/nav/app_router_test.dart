import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/features/auth/domain/auth_state.dart';
import 'package:hoppin_rider/shared/nav/app_router.dart';

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
}
