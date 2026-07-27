import 'package:flutter/material.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

/// BOOK-08 — the automated "finding another driver" retry rung.
///
/// The Scope Lock Document (§4.1) promises: *"If no driver is found or a
/// driver cancels, the system shall automatically retry driver assignment
/// and notify the passenger."* The backend owns the actual re-dispatch
/// (`POST /offers/:id/decline` re-queues offers to a cap, then cancels); the
/// client's job is to PRESENT that ongoing retry honestly instead of the
/// old dead-end "Try again" failure card.
///
/// This is a dumb widget (riblet view rules): state in via [isRetrying]
/// (derived by the convergence lane from the existing `searching`/`failed`
/// booking phases — no `booking_state.dart` change), events out via
/// [onExit]. It owns no timers and no repository. The convergence lane
/// (10-05) mounts it into `booking_view.dart` and registers the BOOK-08 seam.
///
/// Honesty guarantees (decision 5, no-holes rule):
/// - It reflects the LIVE search ("still looking"), never a fake "found!".
///   The signal that a NEW driver was actually matched is SEAMED on the
///   Phase 11 notification plumbing — this rung never claims it.
/// - A manual exit ([onExit]) stays reachable under the retry so the rider
///   is never trapped; the retry presentation simply leads.
class MatchingRung extends StatelessWidget {
  /// Creates the "finding another driver" retry rung.
  const MatchingRung({
    required this.onExit,
    this.isRetrying = true,
    this.exitLabel = 'Cancel search',
    super.key,
  });

  /// Whether the automated re-dispatch is still in flight. `true` shows the
  /// live "finding another driver" search; the convergence lane derives this
  /// from the booking `searching`/`failed` phases. Kept as an input so the
  /// widget stays dumb — it never reads the interactor itself.
  final bool isRetrying;

  /// Fires the rider's manual escape from the retry loop. The caller stops
  /// the client-side search and offers the skippable cancel survey.
  final VoidCallback onExit;

  /// Label for the always-visible manual exit.
  final String exitLabel;

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;
    final type = hoppin.type;

    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(hoppin.spacing.gutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The same radar language the first-pass matching beat uses —
            // this is the SAME search continuing, not a new kind of wait.
            const RadarPulse(size: 180),
            SizedBox(height: hoppin.spacing.xl),
            Text(
              'Finding you another driver…',
              textAlign: TextAlign.center,
              style: type.title.copyWith(color: colors.textHi),
            ),
            SizedBox(height: hoppin.spacing.xs),
            // Honest about the ongoing re-dispatch — never a fake success.
            Text(
              "Your last driver couldn't make it, so we're automatically "
              'matching you with another one nearby. This usually only takes '
              'a moment.',
              textAlign: TextAlign.center,
              style: type.bodySmall.copyWith(color: colors.textMid),
            ),
            SizedBox(height: hoppin.spacing.lg),
            // A calm "still looking" reassurance chip — accent, not error:
            // this is a live retry, not the terminal failure state.
            StatusPill(
              label: isRetrying ? 'Still looking' : 'Retrying…',
              tone: PillTone.accent,
            ),
            SizedBox(height: hoppin.spacing.xl),
            // The escape hatch is ALWAYS reachable — the retry leads, but the
            // rider is never trapped (no dead ends, 2026-07-08 directive).
            TextButton(
              onPressed: onExit,
              style: TextButton.styleFrom(
                foregroundColor: colors.textMid,
                minimumSize: const Size(44, 44),
              ),
              child: Text(exitLabel),
            ),
          ],
        ),
      ),
    );
  }
}
