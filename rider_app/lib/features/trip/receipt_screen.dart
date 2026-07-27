import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

import '../booking/booking_builder.dart';
import 'driver_info_provider.dart';
import 'trip_builder.dart';
import 'trip_handoff.dart';
import 'trip_router.dart';

/// Itemised receipt — `GET /rides/:id/receipt`. Amounts arrive as integer
/// pence (docs/04); rendered with [formatPence].
final receiptProvider = FutureProvider.autoDispose.family<Receipt, String>((
  ref,
  rideId,
) {
  return ref.watch(ridesRepositoryProvider).receipt(rideId);
});

/// The meter-readout money moment (RIDER-04/07): the completed [RouteStrip]
/// reappears at the top for visual continuity with the live trip, the fare
/// table aligns label-left/amount-right in Geist Mono tabular numerals, an
/// applied promo renders as a satisfying negative line, and the total is
/// bold and pence-exact.
///
/// Riblet-lite by contract: [receiptProvider] stays the fetch brain, this
/// view renders state and forwards intents — navigation leaves ONLY through
/// the trip family's [TripNavigationHost] (Rebook → book intent, Done →
/// home intent). This file itself never navigates.
class ReceiptScreen extends ConsumerWidget {
  const ReceiptScreen({required this.rideId, super.key});

  final String rideId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receiptAsync = ref.watch(receiptProvider(rideId));

    return Scaffold(
      body: TripNavigationHost(
        rideId: rideId,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The receipt is OUTSIDE the shell, so it inherits no bottom nav
              // and no shell bar. It used a stock AppBar whose `leading` was
              // conditional on `Navigator.canPop()` — and this screen is reached
              // with `context.go` (see trip_router), which REPLACES rather than
              // pushes, so canPop is ALWAYS false. The conditional was a trap
              // waiting to close: the moment the leading was dropped on the
              // other branch there would be no exit at all. The design-system
              // bar takes an UNCONDITIONAL back intent instead.
              //
              // Riblet rule (DOCS/05) intact: when there is genuinely nothing to
              // pop we do not navigate from here — we fire the home INTENT and
              // TripNavigationHost above does the going.
              HopTopBar(
                title: 'Receipt',
                onBack: () => context.canPop()
                    ? context.pop()
                    : ref
                          .read(tripInteractorProvider(rideId).notifier)
                          .requestHome(),
              ),
              Expanded(
                child: receiptAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(
                    child: Padding(
                      padding: EdgeInsets.all(context.hoppin.spacing.gutter),
                      child: HopBanner.error(
                        message: friendlyErrorMessage(e),
                        actionLabel: 'Try again',
                        onAction: () => ref.invalidate(receiptProvider(rideId)),
                      ),
                    ),
                  ),
                  data: (receipt) =>
                      _ReceiptBody(rideId: rideId, receipt: receipt),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReceiptBody extends ConsumerWidget {
  const _ReceiptBody({required this.rideId, required this.receipt});

  final String rideId;
  final Receipt receipt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;
    final type = hoppin.type;

    // DEMO-07 seam: null data is a VALID state (live mode, archived route
    // after a reload) — labels fall back, the driver line hides.
    final driver = ref.watch(driverInfoProvider(rideId)).value;

    // The promo trace (RIDER-07): the receipt model carries no promo fields,
    // so the discount is DERIVED — pre-discount fare + waiting − charged
    // total. Positive means a promo landed; the maths stays pence-exact.
    final discountPence =
        receipt.farePence + receipt.waitingPence - receipt.totalPence;

    final pickup = receipt.pickupTime;
    final dropoff = receipt.dropoffTime;
    final dateStamp = dropoff ?? pickup;

    return ListView(
      // The last control on this list is "Done" — the receipt's ONLY exit — and
      // it used to sit exactly one gutter off the bottom of the viewport, which
      // is to say: on the edge, with nothing in reserve. That holds right up
      // until something takes vertical room away (the floating top pill now
      // does; a shorter phone would too), at which point the exit scrolls to the
      // last available pixel and STILL straddles the boundary. It is visible. It
      // is not pressable. That is worse than no exit at all, because the rider
      // can see it and keeps trying.
      //
      // So the list carries a real bottom reserve — a full section gap BELOW the
      // gutter — and the final control always lands clear of the edge with room
      // to spare, whatever the chrome above it does.
      padding: EdgeInsets.fromLTRB(
        hoppin.spacing.gutter,
        hoppin.spacing.gutter,
        hoppin.spacing.gutter,
        hoppin.spacing.gutter + hoppin.spacing.xl,
      ),
      children: [
        // ── The journey, completed: the live-trip strip reappears here ──
        RouteStrip(
          originLabel: driver?.originLabel ?? 'Pickup',
          destinationLabel: driver?.destinationLabel ?? 'Destination',
          progress: 1.0,
          complete: true,
          showCarMarker: false,
        ),
        SizedBox(height: hoppin.spacing.lg),
        if (dateStamp != null) ...[
          Text(
            formatShortDateTime(dateStamp),
            style: type.label.copyWith(color: colors.textMid),
          ),
          SizedBox(height: hoppin.spacing.sm),
        ],
        // ── Meter-readout fare table ─────────────────────────────────────
        HopCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _MeterRow(label: 'Fare', amount: formatPence(receipt.farePence)),
              if (receipt.waitingPence > 0)
                _MeterRow(
                  label: 'Waiting time',
                  amount: formatPence(receipt.waitingPence),
                ),
              if (discountPence > 0)
                _MeterRow(
                  label: 'Promo applied',
                  amount: '−${formatPence(discountPence)}',
                  color: colors.success,
                ),
              SizedBox(height: hoppin.spacing.sm),
              Container(height: 1, color: colors.hairline),
              SizedBox(height: hoppin.spacing.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Total',
                    style: type.titleSmall.copyWith(color: colors.textHi),
                  ),
                  Text(
                    formatPence(receipt.totalPence),
                    style: type.moneyTitle.copyWith(
                      color: colors.textHi,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              if (receipt.status == 'paid') ...[
                SizedBox(height: hoppin.spacing.md),
                Row(
                  children: [
                    const StatusPill(label: 'Paid', tone: PillTone.success),
                    if (receipt.providerPaymentId != null) ...[
                      SizedBox(width: hoppin.spacing.sm),
                      Expanded(
                        child: Text(
                          'Payment ref: ${receipt.providerPaymentId}',
                          style: type.bodySmall.copyWith(color: colors.textMid),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
        SizedBox(height: hoppin.spacing.md),
        // ── Trip details ─────────────────────────────────────────────────
        HopCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (receipt.distanceMiles != null)
                _MeterRow(
                  label: 'Distance',
                  amount: '${receipt.distanceMiles!.toStringAsFixed(1)} mi',
                ),
              if (pickup != null)
                _MeterRow(label: 'Picked up', amount: formatTime(pickup)),
              if (dropoff != null)
                _MeterRow(label: 'Dropped off', amount: formatTime(dropoff)),
            ],
          ),
        ),
        // ── Driver line: initials + name from the seam (hidden on null) ──
        if (driver != null) ...[
          SizedBox(height: hoppin.spacing.md),
          HopCard(
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.accentSubtle,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    driver.initials,
                    style: type.label.copyWith(color: colors.accent),
                  ),
                ),
                SizedBox(width: hoppin.spacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your driver',
                        style: type.labelSmall.copyWith(color: colors.textMid),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        driver.fullName,
                        style: type.body.copyWith(color: colors.textHi),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
        SizedBox(height: hoppin.spacing.lg),
        // ── Exits: rebook or done — never a dead end ─────────────────────
        HopButton.primary(
          label: 'Rebook this trip',
          onPressed: () {
            // Carry the trip: seed the root-scoped booking interactor with
            // this ride's journey (the home 'Go again' pattern) so /book
            // opens estimated, not blank. A stale or absent handoff (reload,
            // history receipts) degrades to the fresh picker.
            final handoff = ref.read(tripHandoffProvider);
            if (handoff?.rideId == rideId &&
                handoff?.pickup != null &&
                handoff?.dropoff != null) {
              ref.read(bookingInteractorProvider.notifier)
                ..setPickup(handoff!.pickup!)
                ..setDropoff(handoff.dropoff!);
            }
            ref.read(tripInteractorProvider(rideId).notifier).requestBook();
          },
        ),
        SizedBox(height: hoppin.spacing.sm),
        HopButton.ghost(
          label: 'Done',
          onPressed: () =>
              ref.read(tripInteractorProvider(rideId).notifier).requestHome(),
        ),
      ],
    );
  }
}

/// One meter-readout line: label left in text Geist, amount right in the
/// ledger mono style (tabular figures + slashed zero) so every amount cell
/// lands in a true column.
class _MeterRow extends StatelessWidget {
  const _MeterRow({required this.label, required this.amount, this.color});

  final String label;
  final String amount;

  /// Amount colour override — the promo line's success green.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: hoppin.spacing.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: hoppin.type.body.copyWith(color: color ?? colors.textMid),
          ),
          Text(
            amount,
            style: hoppin.type.ledger.copyWith(color: color ?? colors.textHi),
          ),
        ],
      ),
    );
  }
}
