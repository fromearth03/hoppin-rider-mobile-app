import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

/// The cancellation-penalty schedule shown to a rider BEFORE they confirm a
/// booking (SL-9, Scope Lock §4.1: "Penalty rules MUST be clearly displayed
/// to passengers before booking").
///
/// The live read `GET /me/cancellation-fee-schedule`
/// (`{ free_cancel_window_seconds, penalty_amount, currency, rules? }`) does
/// NOT exist yet (MISSING-FE) — so this shape is populated from a config
/// stub. Body-swap to the live read when the endpoint ships (Phase 13 config
/// switch); the widget never changes.
@immutable
class CancellationFeeSchedule {
  /// Creates a fee schedule from real (or stub) figures.
  const CancellationFeeSchedule({
    required this.freeCancelWindowSeconds,
    required this.penaltyAmountPounds,
    this.currency = 'GBP',
    this.rules = const [],
  });

  /// How long after booking a rider can cancel with no charge.
  final int freeCancelWindowSeconds;

  /// The flat penalty charged once the free-cancel window closes, in pounds.
  final double penaltyAmountPounds;

  /// ISO currency code — GBP throughout the platform.
  final String currency;

  /// Optional finer-grained rules (scenario-specific fees) once the endpoint
  /// carries them; empty until then.
  final List<String> rules;

  /// The stub the app discloses until the live penalty-config endpoint lands.
  /// Plausible launch defaults: free to cancel for 2 minutes, then a flat
  /// £5.00 — disclosed as indicative, never presented as the final charge.
  static const stub = CancellationFeeSchedule(
    freeCancelWindowSeconds: 120,
    penaltyAmountPounds: 5.00,
  );

  /// The free-cancel window expressed in whole minutes for display.
  int get freeCancelWindowMinutes => (freeCancelWindowSeconds / 60).round();
}

/// The config-stub schedule provider. Live returns null (no endpoint, SL-9),
/// so the app sources the disclosure from [CancellationFeeSchedule.stub] and
/// discloses it as indicative. When `GET /me/cancellation-fee-schedule`
/// ships, this body swaps to the live read with no view change.
final cancellationFeeScheduleProvider =
    Provider<CancellationFeeSchedule>((ref) => CancellationFeeSchedule.stub);

/// The pre-booking cancellation-fee DISCLOSURE surface (SL-9, the hard MUST).
///
/// A dumb, token-driven widget: schedule in, disclosure out — no navigation,
/// no repository. It renders the REAL figures (from the stub) as a plain-
/// English collapsed line ("Free to cancel for 2 min, then £5.00") that
/// expands to the fuller schedule. It is NEVER a hidden "coming soon" seam —
/// the number is always shown; only the SOURCE is disclosed as indicative
/// until the live schedule lands.
///
/// Merge-storm note: this ships as a standalone file. The convergence lane
/// (10-05) mounts it into `booking_view.dart` pre-confirm and registers the
/// SL-9 seam; this lane never touches the booking view.
class FeeDisclosure extends StatefulWidget {
  /// Creates the disclosure over [schedule] (defaults to the config stub).
  const FeeDisclosure({this.schedule = CancellationFeeSchedule.stub, super.key});

  /// The penalty schedule to disclose.
  final CancellationFeeSchedule schedule;

  @override
  State<FeeDisclosure> createState() => _FeeDisclosureState();
}

class _FeeDisclosureState extends State<FeeDisclosure> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;
    final type = hoppin.type;
    final schedule = widget.schedule;

    final minutes = schedule.freeCancelWindowMinutes;
    final penalty = formatPounds(schedule.penaltyAmountPounds);
    final windowLabel = '$minutes min';

    // The plain-English one-liner — the number is the point, always present.
    final headline = 'Free to cancel for $windowLabel, then $penalty';

    return HopCard(
      onTap: () => setState(() => _open = !_open),
      padding: EdgeInsets.symmetric(
        horizontal: hoppin.spacing.lg,
        vertical: hoppin.spacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, size: 18, color: colors.textMid),
              SizedBox(width: hoppin.spacing.sm),
              Expanded(
                child: Text(
                  headline,
                  style: type.bodyMedium.copyWith(color: colors.textHi),
                ),
              ),
              Icon(
                _open ? Icons.expand_less : Icons.expand_more,
                size: 20,
                color: colors.textMid,
              ),
            ],
          ),
          // The stub source is disclosed as indicative — honest about the
          // config source (SL-9) — while the figures above stay real.
          SizedBox(height: hoppin.spacing.xs),
          Text(
            'Cancellation policy — figures indicative until confirmed at '
            'booking.',
            style: type.metaSmall.copyWith(color: colors.textMid),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: EdgeInsets.only(top: hoppin.spacing.md),
              child: _ScheduleDetail(schedule: schedule),
            ),
            crossFadeState: _open
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: hoppin.motion.quick,
          ),
        ],
      ),
    );
  }
}

/// The expanded schedule body: the free-cancel window and the penalty spelled
/// out as two rows, plus any scenario rules the endpoint carries.
class _ScheduleDetail extends StatelessWidget {
  const _ScheduleDetail({required this.schedule});

  final CancellationFeeSchedule schedule;

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;
    final type = hoppin.type;
    final minutes = schedule.freeCancelWindowMinutes;
    final penalty = formatPounds(schedule.penaltyAmountPounds);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(height: 1, color: colors.hairline),
        SizedBox(height: hoppin.spacing.md),
        _row(
          context,
          leading: 'Free to cancel',
          // The free window is the positive, no-charge moment — semantic
          // green (#22C55E via colors.success).
          trailing: 'First $minutes min',
          trailingColor: colors.success,
        ),
        SizedBox(height: hoppin.spacing.sm),
        _row(
          context,
          leading: 'Cancellation fee after that',
          trailing: penalty,
          trailingColor: colors.textHi,
        ),
        if (schedule.rules.isNotEmpty) ...[
          SizedBox(height: hoppin.spacing.md),
          for (final rule in schedule.rules)
            Padding(
              padding: EdgeInsets.only(bottom: hoppin.spacing.xs),
              child: Text(
                rule,
                style: type.metaSmall.copyWith(color: colors.textMid),
              ),
            ),
        ],
      ],
    );
  }

  Widget _row(
    BuildContext context, {
    required String leading,
    required String trailing,
    required Color trailingColor,
  }) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;
    final type = hoppin.type;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            leading,
            style: type.meta.copyWith(color: colors.textMid),
          ),
        ),
        SizedBox(width: hoppin.spacing.md),
        Text(
          trailing,
          style: type.bodyMedium.copyWith(
            color: trailingColor,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
