import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

import '../booking/widgets/fee_disclosure.dart';
import 'cancellation_reasons.dart';
import 'trip_builder.dart';
import 'trip_state.dart';

/// The two-stage cancel-intercept (RIDER-06).
///
/// Stage 1 protects the ride: the sheet keeps the trip warm with a live
/// ticking "arrives in M:SS" line and makes KEEPING the ride the positive
/// primary action. Stage 2 — the reason survey — comes only AFTER the
/// cancellation resolved, and is prominently skippable.
///
/// The cancel call resolves an active server-side reason at confirmation time.
/// Pre-trip cancellations use `rider_cancel`; a started trip uses
/// `rider_mid_trip`, whose configured fee floor and time/distance grace are
/// evaluated by the ride service. If no active rule exists, the ride still
/// cancels without a penalty.
Future<void> showCancelIntercept(
  BuildContext context, {
  required String rideId,
}) async {
  final colors = context.hoppin.colors;
  // Scroll-controlled: the gap-#1 rung and its working support action must
  // stay ON SCREEN and TAPPABLE on short viewports. A disclosure clipped
  // below the fold is not a disclosure, and the default sheet cap would clip
  // it — which would quietly restore the exact defect this rung deletes.
  final cancelled = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    elevation: 0,
    backgroundColor: Colors.transparent,
    barrierColor: colors.scrim,
    builder: (_) => HopSheet(child: _InterceptSheet(rideId: rideId)),
  );
  if (cancelled != true || !context.mounted) return;
  // Scroll-controlled so all four reasons AND the Skip stay tappable on
  // short viewports (the default sheet cap would clip the survey).
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    elevation: 0,
    backgroundColor: Colors.transparent,
    barrierColor: colors.scrim,
    builder: (_) => const HopSheet(child: _ReasonSurveySheet()),
  );
}

/// Stage 1: "Cancel this trip?" with the ticking intercept line. The sheet
/// owns NO timers — the line rebuilds off the interactor's 1Hz state tick
/// via ref.watch.
class _InterceptSheet extends ConsumerStatefulWidget {
  const _InterceptSheet({required this.rideId});

  final String rideId;

  @override
  ConsumerState<_InterceptSheet> createState() => _InterceptSheetState();
}

class _InterceptSheetState extends ConsumerState<_InterceptSheet> {
  bool _busy = false;

  Future<void> _confirmCancel() async {
    setState(() => _busy = true);
    final ok = await ref
        .read(tripInteractorProvider(widget.rideId).notifier)
        .cancelWithDefaultReason();
    if (!mounted) return;
    Navigator.of(context).pop(ok);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(tripInteractorProvider(widget.rideId));
    final hoppin = context.hoppin;
    final colors = hoppin.colors;
    final type = hoppin.type;
    final driver = state.driver;
    final first = driver == null
        ? 'Your driver'
        : _firstNameOf(driver.fullName);
    final remaining = state.etaSecondsRemaining;

    // The sheet grew when the gap-#1 rung landed on it, so on a short viewport
    // it must not simply overflow — an overflow clips whatever is at the
    // bottom, and a control the rider cannot reach is worse than no control.
    //
    // The layout answers that in two halves:
    //   * the CONTEXT (header, ETA, fee line, the rung, any ticket error)
    //     scrolls inside a bounded region — the rung is at the TOP of it, so it
    //     is on screen from the first frame, which is the whole point: the
    //     rider is told BEFORE they can rely on the button;
    //   * the ACTIONS are PINNED below it and never scroll away.
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.82,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Cancel this trip?',
                    style: type.title.copyWith(color: colors.textHi),
                  ),
                  SizedBox(height: hoppin.spacing.sm),

                  // In-app cancellation is LIVE: cancelWithDefaultReason fetches
                  // the real seeded reasons from GET /cancellation-reasons and
                  // sends a valid reason_id (gap #1 is closed). The old
                  // "cancellation isn't working, message support" disclosure was
                  // removed once the endpoint landed — showing it now would tell
                  // the rider a working feature is broken.

                  // The intercept: the ride is close and getting closer — the
                  // ticking ETA rides a numeric pill so the digits never jitter.
                  Row(
                    children: [
                      if (remaining != null) ...[
                        StatusPill(
                          label: 'Arrives in ${_mmss(remaining)}',
                          tone: PillTone.accent,
                          dot: true,
                          numeric: true,
                        ),
                        SizedBox(width: hoppin.spacing.sm),
                        Expanded(
                          child: Text(
                            '$first is on the way to you.',
                            style: type.body.copyWith(color: colors.textMid),
                          ),
                        ),
                      ] else
                        Expanded(
                          child: Text(
                            '$first is waiting for you.',
                            style: type.body.copyWith(color: colors.textMid),
                          ),
                        ),
                    ],
                  ),
                  SizedBox(height: hoppin.spacing.sm),
                  // A started trip uses a different billing rule: the server
                  // computes the metered partial fare and applies the active
                  // rider_mid_trip fee floor only after its time/distance grace
                  // is evaluated. Do not show the generic pre-trip £5 example
                  // here; it is not the amount that will be charged.
                  Builder(
                    builder: (context) {
                      if (state.phase == TripPhase.onRoad) {
                        return Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 16,
                              color: colors.textMid,
                            ),
                            SizedBox(width: hoppin.spacing.xs),
                            Expanded(
                              child: Text(
                                'A partial fare may apply based on time and distance travelled.',
                                style: type.metaSmall.copyWith(
                                  color: colors.textMid,
                                ),
                              ),
                            ),
                          ],
                        );
                      }
                      final schedule = ref.watch(
                        cancellationFeeScheduleProvider,
                      );
                      return Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 16,
                            color: colors.textMid,
                          ),
                          SizedBox(width: hoppin.spacing.xs),
                          Expanded(
                            child: Text(
                              'Cancellation fee may apply — '
                              '${formatPounds(schedule.penaltyAmountPounds)}.',
                              style: type.metaSmall.copyWith(
                                color: colors.textMid,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          SizedBox(height: hoppin.spacing.lg),
          // Keeping the ride is the positive primary action (RIDER-06). The
          // rung's support button is deliberately a step below it in weight: it
          // is the WORKING route, but "keep the ride" is still the safe default.
          HopButton.primary(
            label: 'No, keep my ride',
            onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          ),
          SizedBox(height: hoppin.spacing.xs),
          // In-app cancel is live and bound (gap #1 closed). On the rare live
          // failure the interactor still names it honestly, but the default
          // path now genuinely cancels the ride.
          TextButton(
            onPressed: _busy ? null : _confirmCancel,
            style: TextButton.styleFrom(
              foregroundColor: colors.error,
              minimumSize: const Size.fromHeight(44),
            ),
            child: Text(_busy ? 'Cancelling…' : 'Cancel ride'),
          ),
        ],
      ),
    );
  }
}

/// Stage 2: the post-cancel reason survey. Selection is acknowledgment-only
/// — no app-facing endpoint records a post-cancel reason (backend gap,
/// tracked in cancellation_reasons.dart); the cancel already carried the
/// seeded default id. Skipping is a first-class choice.
class _ReasonSurveySheet extends ConsumerWidget {
  const _ReasonSurveySheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Post-cancel survey reasons — the ride is already cancelled by this point
    // (cancelWithDefaultReason), so this list is purely for the "why?" prompt.
    // Now the REAL seeded reasons rather than fabricated labels; an empty/failed
    // read just yields no chips, and the Skip button still closes the sheet.
    final reasonsAsync = ref.watch(cancellationReasonsProvider);
    final reasons = reasonsAsync.hasValue
        ? reasonsAsync.requireValue
        : const <CancellationReason>[];
    final hoppin = context.hoppin;
    final colors = hoppin.colors;
    final type = hoppin.type;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Mind telling us why?',
          style: type.title.copyWith(color: colors.textHi),
        ),
        SizedBox(height: hoppin.spacing.xs),
        // WAVE-0: this said "Optional — it helps us improve." while EVERY
        // option was a bare `Navigator.pop()`. The reason was collected and
        // discarded — no endpoint records a post-cancel reason (backend gap,
        // see cancellation_reasons.dart). Telling a rider their feedback helps
        // when it goes nowhere is a small lie, but it is still a lie, and it is
        // the kind that erodes trust in every other confirmation the app shows.
        // The copy now promises only what the app can keep. When the reason
        // endpoint ships, this records for real and the copy can grow back.
        Text(
          'Optional — this just closes the ride for you.',
          style: type.bodySmall.copyWith(color: colors.textMid),
        ),
        SizedBox(height: hoppin.spacing.md),
        for (var i = 0; i < reasons.length; i++) ...[
          if (i > 0) const Divider(height: 1),
          InkWell(
            onTap: () => Navigator.of(context).pop(),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: hoppin.spacing.xs),
                  child: Text(
                    reasons[i].label,
                    style: type.body.copyWith(color: colors.textHi),
                  ),
                ),
              ),
            ),
          ),
        ],
        SizedBox(height: hoppin.spacing.md),
        HopButton.secondary(
          label: 'Skip',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

String _mmss(int seconds) {
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

String _firstNameOf(String fullName) {
  final parts = fullName.trim().split(' ');
  return parts.isEmpty ? fullName : parts.first;
}
