import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/domain/auth_state.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/signup_screen.dart';

class AppRoutes {
  AppRoutes._();
  static const login = '/login';
  static const signup = '/signup';
  static const home = '/home';
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

  final onAuthScreen =
      location == AppRoutes.login || location == AppRoutes.signup;

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

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoutes.login,
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
        path: AppRoutes.home,
        // Replaced by the booking map in batch 2.
        builder: (_, __) => const Scaffold(
          body: Center(child: Text('Signed in')),
        ),
      ),
    ],
  );
});
