import 'package:flutter/material.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

/// Stable widget keys the cancellation disclosure exposes for tests.
abstract final class CancellationDisclosureKeys {
  /// The pre-commit disclosure rung itself.
  static const notice = ValueKey('cancel-unavailable-notice');

  /// The WORKING route out — files a real support ticket for this ride.
  static const contactSupport = ValueKey('cancel-contact-support');
}

/// The pre-commit disclosure for **cancellation is broken on live** (backend
/// gap #1, P0 — `DOCS/backend-gaps/p0-cancellation-reasons-BROKEN.md`).
///
/// ## What is actually broken
///
/// `PATCH /rides/:id/cancel` REQUIRES a valid `reason_id` uuid and rejects
/// unknown ones with `VALIDATION_FAILED`. The reasons exist — seeded, managed
/// on the admin API's `/config` — but `:8080` exposes **no endpoint the rider
/// app can read them through**. Existing is not reachable. So the app sends a
/// placeholder uuid that is not in the database, and **every rider cancellation
/// on live is rejected. 100% of the time.**
///
/// This CANNOT be fixed app-side. Inventing uuids would be a guess that fails
/// the same way and rots on the next reseed. Only `GET /me/cancellation-reasons`
/// (the ask) or the real seeded ids can fix it.
///
/// ## Why this rung exists, and why it is PRE-commit
///
/// The bug was known and documented — in a **source comment**, which is a
/// surface no rider will ever read. Over that comment the app shipped a
/// confident "Cancel ride" button and a normal destructive confirm. The rider
/// found out only AFTER committing, from a post-hoc error, while the ride kept
/// running and kept charging. A disclosure that arrives after the user has
/// relied on the capability is not a disclosure; it is an apology.
///
/// So the truth moves in FRONT of the confirm: before the rider can commit,
/// they are told plainly that in-app cancellation is not working right now.
///
/// ## The button is NOT disabled — a dead control is its own lie
///
/// The rider still wants ONE outcome: to stop the ride and not be charged for
/// it. Greying out "Cancel ride" would disclose the gap and strand them with
/// it. So this rung carries the route that ACTUALLY works today — the same
/// mechanism the Art. 17 erasure route rides on: a real
/// `POST /me/support-tickets`, tagged with this ride, that lands in a real
/// database and is read and actioned by a real person. The cancel attempt is
/// still made (if the backend is fixed, or reasons are seeded, it simply
/// succeeds and this rung stops mattering), and the honest post-hoc error stays
/// where it is as the second line of defence.
///
/// The rung is the fallback surface for gap #1. It is CONSTRUCTED by
/// `cancel_flow.dart` on the intercept sheet, above every action — the seam is
/// not sometimes-null, it is always-null, so the disclosure is unconditional.
class CancellationUnavailableState extends StatelessWidget {
  /// Creates the gap-#1 cancellation degrade rung.
  const CancellationUnavailableState({
    required this.onContactSupport,
    this.busy = false,
    super.key,
  });

  /// Files the real support ticket for this ride and routes the rider to it.
  /// This is the WORKING alternative — never inert, never a dead end.
  final VoidCallback onContactSupport;

  /// True while the ticket is being filed — the action must not double-file.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;

    final body = hoppin.type.meta.copyWith(color: colors.textMid);

    return Container(
      key: CancellationDisclosureKeys.notice,
      width: double.infinity,
      padding: EdgeInsets.all(hoppin.spacing.md),
      decoration: BoxDecoration(
        color: colors.warnSubtle,
        borderRadius: BorderRadius.circular(hoppin.radii.input),
        border: Border.all(color: colors.hairline),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. The plain truth, BEFORE the rider relies on the button.
          Text(
            "Cancelling in the app isn't working right now",
            style: hoppin.type.titleSmall.copyWith(color: colors.textHi),
          ),
          SizedBox(height: hoppin.spacing.xs),

          // 2. What will actually happen if they tap Cancel ride. No euphemism:
          //    the request is expected to be refused, and the ride keeps
          //    running — which means it keeps charging.
          Text(
            'If you tap Cancel ride we will still try, but the request is very '
            'likely to be refused — and your trip would carry on running, and '
            'carry on charging.',
            style: body,
          ),
          SizedBox(height: hoppin.spacing.sm),

          // 3. The route that DOES work. A real ticket, a real person.
          Text(
            'The way that works today is to tell us. Sending a message opens a '
            'support ticket about this exact trip, and a person will stop the '
            'ride and sort out any charge for you.',
            style: body,
          ),
          SizedBox(height: hoppin.spacing.md),

          // Deliberately `secondary`: on the intercept sheet "No, keep my ride"
          // remains the positive primary (RIDER-06). This is still a LIVE,
          // working control — the only one on the sheet that reaches the
          // outcome the rider actually wants.
          HopButton.secondary(
            key: CancellationDisclosureKeys.contactSupport,
            label: busy ? 'Sending…' : 'Message support to cancel',
            onPressed: busy ? null : onContactSupport,
          ),
        ],
      ),
    );
  }
}
