import 'package:flutter/material.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

/// The password-reset deep-link landing (AUTH-04, GATED on gap #49).
///
/// The Supabase Auth redirect URL for reset emails is not configured yet, so
/// this screen is honestly INERT: it renders a DESIGNED "reset link unavailable"
/// state via [HopEmptyState] — never a fake password form that pretends to
/// work. When #49 lands (the dashboard redirect config), this screen becomes
/// the real reset entry point.
///
/// ## Seam note for 09-05
/// This is the GATED #49 seam. 09-05 must:
///   * register it in `kSeamRegistry` (`SeamState.GATED`, gap 49,
///     `unavailableWidget: 'ResetLandingScreen'`), and
///   * allowlist its route in the router redirect (router.dart:44-52) so a
///     signed-out deep link is NOT bounced to /login before it renders.
class ResetLandingScreen extends StatelessWidget {
  const ResetLandingScreen({this.onBackToSignIn, super.key});

  /// Optional "Back to sign in" action (wired to the router in 09-05).
  final VoidCallback? onBackToSignIn;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: HopEmptyState(
            headline: "This reset link isn't active yet",
            supporting:
                "Password reset by email is coming soon. In the meantime, sign "
                "in with your existing password, or contact support if you're "
                'locked out.',
            actionLabel: onBackToSignIn == null ? null : 'Back to sign in',
            onAction: onBackToSignIn,
          ),
        ),
      ),
    );
  }
}
