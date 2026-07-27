import 'package:flutter/material.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

/// The soft "verify your account" nudge (AUTH-02).
///
/// The LOCKED decision: nudge everywhere from signup onward, but NEVER block
/// browsing — the hard verify wall lands only at the Book tap (wired in 09-05,
/// mirroring the server `403 ACCOUNT_NOT_ELIGIBLE`). This banner is that soft
/// nudge: a notice-tone [HopBanner] with an optional "Verify now" action.
///
/// It is dismissible-but-recurring by design — dismissing hides it for the
/// current surface, but it re-appears on the next unverified surface (the
/// caller controls visibility from the auth/verification state). Presentation
/// only: state in, events out.
class VerifyBanner extends StatelessWidget {
  const VerifyBanner({this.onVerify, super.key});

  /// Fired when the rider taps "Verify now" — routes to the OTP screen
  /// (wired in 09-05). Null renders the banner message-only.
  final VoidCallback? onVerify;

  @override
  Widget build(BuildContext context) {
    return HopBanner.notice(
      message: 'Verify your account to book your first ride.',
      actionLabel: onVerify == null ? null : 'Verify now',
      onAction: onVerify,
    );
  }
}
