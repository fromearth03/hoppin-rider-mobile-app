import 'package:flutter/material.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

/// The designed disclosure state for the 18+/DOB eligibility seam (SL-5, #55).
///
/// Signup collects the 18+ declaration and date of birth into the client-side
/// `SignupEligibility` holder, but there is no rider-profile PATCH to PERSIST
/// them yet (MISSING-BE). Rather than silently drop the collected eligibility
/// — or pretend it was saved — this designed state honestly discloses that the
/// declaration is held on this device until account profiles can store it.
///
/// This is the registered unavailable-state widget for the 18+/SL-5 seam
/// (`kSeamRegistry`); the seam_registry_test group-C check pumps it and
/// asserts a designed, non-blank surface. Token-driven throughout.
class SignupEligibilityNotice extends StatelessWidget {
  /// Creates the 18+/DOB eligibility disclosure state.
  const SignupEligibilityNotice({super.key});

  @override
  Widget build(BuildContext context) {
    return const HopEmptyState(
      compact: true,
      headline: 'Age confirmed on this device',
      supporting:
          "You've confirmed you're 18 or over. We keep this with you until "
          'account profiles can store it — your booking eligibility is checked '
          'securely on our servers each time.',
    );
  }
}
