import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

/// The designed unavailable-state for rider profile read/write (gap 70, SL-5).
///
/// There is no `GET /me/profile` and no `PATCH /me/profile`. There never has
/// been. So the Personal Information screen can SHOW the rider what the session
/// holds, but it cannot change any of it — and every control that looks like it
/// could is a promise the backend cannot keep.
///
/// This rung is CONSTRUCTED **unconditionally** by `personal_info_screen.dart`,
/// above the form. That is deliberate: the seam is not "sometimes null", it is
/// ALWAYS null. There is no branch to hang the disclosure on, and inventing one
/// would be theatre.
///
/// 🔴 Its exit is REAL and ENABLED. Phase 11's `CallUnavailableState` set the
/// precedent — a disclosure that strands the rider is only half-honest. The
/// right to have inaccurate data corrected (UK GDPR Art. 16 rectification) is a
/// real right, and while `PATCH /me/profile` does not exist, a support ticket
/// read by a person is the honest route to it. This is the ONE live callback on
/// the entire screen; everything else on it is deliberately, visibly off.
///
/// Body-swaps to the live profile write with zero view changes when the
/// endpoint ships: the rung disappears and Save gets a callback.
class PersonalInfoUnavailable extends StatelessWidget {
  /// Creates the gap-70 profile-write disclosure.
  const PersonalInfoUnavailable({super.key});

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;

    return HopCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const HopEmptyState(
            compact: true,
            headline: "You can't change these details here yet",
            supporting:
                "Saving isn't switched on. To correct anything we hold about "
                'you, open a support ticket and a person will put it right.',
          ),
          SizedBox(height: hoppin.spacing.sm),
          HopButton.secondary(
            key: const Key('personal.rung.support'),
            label: 'Open a support ticket',
            expand: false,
            // The one live control on this screen. It must actually land —
            // a disclosure that strands the rider is only half-honest.
            onPressed: () => context.go('/support'),
          ),
        ],
      ),
    );
  }
}
