import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/features/auth/domain/auth_state.dart';
import 'package:hoppin_rider/shared/nav/app_router.dart';

/// Every route a signed-in rider can reach from the drawer must actually stay
/// where it was sent.
///
/// `redirectFor` bounces a signed-in rider off the auth screens. A route added
/// to the table but not considered here would compile, appear in the drawer,
/// and then silently redirect to /home when tapped — which looks like a broken
/// link rather than a routing rule.
void main() {
  const drawerDestinations = <String>[
    AppRoutes.personalInformation,
    AppRoutes.paymentMethods,
    AppRoutes.notifications,
    AppRoutes.promotional,
    AppRoutes.settings,
    AppRoutes.helpSupport,
    AppRoutes.rideHistory,
    AppRoutes.scheduleRide,
    AppRoutes.savedPlaces,
  ];

  /// The password-recovery flow. A rider here is signed out by definition, so
  /// these must NOT bounce to login — including the screen the emailed link
  /// lands on.
  const recoveryFlow = <String>[
    AppRoutes.forgotPassword,
    AppRoutes.linkSent,
    AppRoutes.expiredLink,
    AppRoutes.resetPassword,
  ];

  const bookingFlow = <String>[
    AppRoutes.home,
    AppRoutes.route,
    AppRoutes.selectVehicle,
    AppRoutes.rideComplete,
    AppRoutes.chat,
    AppRoutes.safety,
    AppRoutes.tripDetails,
    AppRoutes.liveTrip,
    AppRoutes.fareConfirm,
  ];

  group('a signed-in rider is left alone on', () {
    for (final path in [...drawerDestinations, ...bookingFlow]) {
      test(path, () {
        expect(
          redirectFor(AuthStatus.signedIn, path),
          isNull,
          reason: '$path is reachable from the running app, so a signed-in '
              'rider must not be redirected away from it',
        );
      });
    }
  });

  group('a signed-out rider is sent to login from', () {
    for (final path in drawerDestinations) {
      test(path, () {
        expect(redirectFor(AuthStatus.signedOut, path), AppRoutes.login);
      });
    }
  });

  group('a signed-out rider can complete recovery at', () {
    for (final path in recoveryFlow) {
      test(path, () {
        expect(
          redirectFor(AuthStatus.signedOut, path),
          isNull,
          reason: 'bouncing a signed-out rider off $path makes password '
              'recovery impossible to finish',
        );
      });
    }
  });
}
