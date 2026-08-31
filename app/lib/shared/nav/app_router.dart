import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/domain/auth_state.dart';
import '../../features/auth/presentation/forgot_password_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/signup_screen.dart';
import '../../features/booking/presentation/home_screen.dart';
import '../../features/booking/presentation/route_entry_screen.dart';
import '../../features/booking/presentation/select_vehicle_screen.dart';
import '../../features/history/presentation/ride_history_screen.dart';
import '../../features/history/presentation/trip_details_screen.dart';
import '../../features/notifications/presentation/notifications_screen.dart';
import '../../features/notifications/presentation/promotional_screen.dart';
import '../../features/payments/presentation/payment_methods_screen.dart';
import '../../features/payments/presentation/ride_complete_screen.dart';
import '../../features/profile/presentation/personal_information_screen.dart';
import '../../features/scheduling/presentation/schedule_ride_screen.dart';
import '../../features/settings/presentation/help_support_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/chat/presentation/chat_screen.dart';
import '../../features/safety/presentation/safety_screen.dart';

class AppRoutes {
  AppRoutes._();
  static const login = '/login';
  static const signup = '/signup';
  static const forgotPassword = '/forgot-password';
  static const personalInformation = '/personal-information';
  static const paymentMethods = '/payment-methods';
  static const selectVehicle = '/select-vehicle';
  static const rideComplete = '/ride-complete';
  static const notifications = '/notifications';
  static const promotional = '/promotional';
  static const settings = '/settings';
  static const helpSupport = '/help-support';
  static const rideHistory = '/ride-history';
  static const tripDetails = '/trip-details';
  static const scheduleRide = '/schedule-ride';
  static const home = '/home';
  static const route = '/route';
  static const safety = '/safety';
  static const chat = '/chat';
}

/// Where a rider in [status] currently at [location] should be sent, or null
/// to leave them where they are.
///
/// Pure so it can be tested without pumping a widget tree — routing bugs are
/// otherwise only reproducible by navigating.
String? redirectFor(AuthStatus status, String location) {
  // Session restore has not finished. Redirecting now would flash the login
  // screen at a rider who is already signed in.
  if (status == AuthStatus.unknown) return null;

  // Password recovery counts as an auth screen: a signed-out rider must be
  // able to reach it, and without it here the redirect would bounce them
  // straight back to login the moment they tapped "Forgot Password".
  final onAuthScreen = location == AppRoutes.login ||
      location == AppRoutes.signup ||
      location == AppRoutes.forgotPassword;

  switch (status) {
    case AuthStatus.signedOut:
      return onAuthScreen ? null : AppRoutes.login;
    case AuthStatus.profileIncomplete:
      // The account exists but is unusable. Signup carries the recovery UI.
      return location == AppRoutes.signup ? null : AppRoutes.signup;
    case AuthStatus.signedIn:
      return onAuthScreen ? AppRoutes.home : null;
    case AuthStatus.unknown:
      return null;
  }
}

/// Notifies `GoRouter` whenever the rider's auth status changes.
///
/// Without this the router evaluates `redirect` only when something else
/// triggers navigation, so a successful sign-in would leave the rider sitting
/// on the login screen — the status changes, and nothing asks the router to
/// look again.
///
/// It fires on a change of STATUS only, not on every snapshot. `isBusy`
/// flipping while a request is in flight is not a routing event, and
/// re-running the redirect mid-request would be churn at best.
class _AuthRouterRefresh extends ChangeNotifier {
  AuthStatus _last;

  _AuthRouterRefresh(Ref ref) : _last = ref.read(authControllerProvider).status {
    ref.listen<AuthSnapshot>(authControllerProvider, (previous, next) {
      if (next.status != _last) {
        _last = next.status;
        notifyListeners();
      }
    });
  }
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = _AuthRouterRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: AppRoutes.login,
    refreshListenable: refresh,
    redirect: (context, state) {
      final status = ref.read(authControllerProvider).status;
      return redirectFor(status, state.matchedLocation);
    },
    routes: [
      GoRoute(
        path: AppRoutes.login,
        builder: (_, __) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.signup,
        builder: (_, __) => const SignupScreen(),
      ),
      GoRoute(
        path: AppRoutes.forgotPassword,
        builder: (_, __) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: AppRoutes.home,
        builder: (_, __) => const HomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.personalInformation,
        builder: (_, __) => const PersonalInformationScreen(),
      ),
      GoRoute(
        path: AppRoutes.paymentMethods,
        builder: (_, __) => const PaymentMethodsScreen(),
      ),
      GoRoute(
        path: AppRoutes.selectVehicle,
        builder: (_, __) => const SelectVehicleScreen(),
      ),
      GoRoute(
        path: AppRoutes.notifications,
        builder: (_, __) => const NotificationsScreen(),
      ),
      GoRoute(
        path: AppRoutes.settings,
        builder: (_, __) => const SettingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.rideHistory,
        builder: (_, __) => const RideHistoryScreen(),
      ),
      GoRoute(
        path: AppRoutes.scheduleRide,
        builder: (_, __) => const ScheduleRideScreen(),
      ),
      GoRoute(
        path: AppRoutes.tripDetails,
        builder: (_, state) => TripDetailsScreen(
          rideId: state.uri.queryParameters['ride'] ?? '',
        ),
      ),
      GoRoute(
        path: AppRoutes.helpSupport,
        builder: (_, __) => const HelpSupportScreen(),
      ),
      GoRoute(
        path: AppRoutes.promotional,
        builder: (_, __) => const PromotionalScreen(),
      ),
      GoRoute(
        path: AppRoutes.rideComplete,
        builder: (_, state) => RideCompleteScreen(
          rideId: state.uri.queryParameters['ride'] ?? '',
        ),
      ),
      GoRoute(
        path: AppRoutes.route,
        builder: (_, __) => const RouteEntryScreen(),
      ),
      GoRoute(
        path: AppRoutes.safety,
        builder: (_, state) =>
            SafetyScreen(rideId: state.uri.queryParameters['ride']),
      ),
      GoRoute(
        path: AppRoutes.chat,
        builder: (_, state) => ChatScreen(
          rideId: state.uri.queryParameters['ride'] ?? '',
          driverName: state.uri.queryParameters['driver'] ?? 'Driver',
        ),
      ),
    ],
  );
});
