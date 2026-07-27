import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

import '../../providers.dart';
import '../trip/driver_info_provider.dart';

/// rideId → charged pence, joined from `GET /me/transactions`. Works
/// identically live — same endpoint, local-DB read. Rides without a
/// transaction row simply show no price (graceful blank).
final ridePricesProvider =
    FutureProvider.autoDispose<Map<String, int>>((ref) async {
  final txs =
      await ref.watch(paymentsRepositoryProvider).transactions(limit: 50);
  return {
    for (final tx in txs)
      if (tx.rideId != null) tx.rideId!: tx.amountPence,
  };
});

/// Trip history as an Activity hub — `GET /rides`, newest first. Completed
/// rows open the receipt; active rows return to the live trip.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  @override
  void initState() {
    super.initState();
    // Refetch on every open: the home screen lower in the navigator keeps
    // the autoDispose caches warm for the whole session, so without this a
    // ride completed THIS session never reaches the hub until a manual
    // pull-to-refresh. Same behavior live — both are cheap reads.
    Future.microtask(() {
      if (!mounted) return;
      ref.invalidate(historyProvider);
      ref.invalidate(ridePricesProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final rides = ref.watch(historyProvider);
    final hoppin = context.hoppin;

    // Every scroll view on this tab is inset by the chrome it now passes under.
    // Without this the first ride row parks permanently beneath the floating
    // pill and cannot be scrolled up to.
    final scrollPadding = context.chromeScrollPadding(
      horizontal: hoppin.spacing.gutter,
      top: hoppin.spacing.md,
      bottom: hoppin.spacing.md,
    );

    return Scaffold(
      // NO AppBar. The shell already renders a HopTopBar titled "History" over
      // every tab, and this screen was quietly drawing a SECOND header
      // underneath it ("Ride History") — the same stacked-chrome bug
      // shell_chrome_test was written for, just wearing a stock AppBar so the
      // HopTopBar sweep never saw it.
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(historyProvider),
        child: rides.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            padding: scrollPadding,
            children: [HopBanner.error(message: friendlyErrorMessage(e))],
          ),
          data: (list) => list.isEmpty
              ? ListView(
                  padding: scrollPadding,
                  children: [
                    SizedBox(height: hoppin.spacing.xl),
                    HopEmptyState(
                      headline: 'No trips yet',
                      supporting: 'Your completed rides will appear here.',
                      actionLabel: 'Book a ride',
                      onAction: () => context.go('/book'),
                    ),
                  ],
                )
              : ListView.builder(
                  padding: scrollPadding,
                  itemCount: list.length,
                  itemBuilder: (context, i) => RideRow(ride: list[i]),
                ),
        ),
      ),
    );
  }
}

/// One ride in a list — the Activity-hub row shared between Home and
/// History: destination BOLD as the title (via the DEMO-07 seam, gracefully
/// generic when it answers null), short date subtitle, and a trailing
/// price + status column. Cancelled rows show no price.
///
/// Navigation note: home/history are NOT converted riblets this milestone
/// (DOCS/05 migration policy — off-demo-path shells keep their shape), so
/// the row keeps its direct `context.go`; the riblet grep exempts it by
/// location.
class RideRow extends ConsumerWidget {
  const RideRow({required this.ride, super.key});

  final Ride ride;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;
    final type = hoppin.type;

    // Destination + driver rating via the capability seam — null is a valid
    // (live) answer and each falls back gracefully (generic title, hidden
    // star), never a raw id.
    final info = ref.watch(driverInfoProvider(ride.id)).value;
    final destination = info?.destinationLabel;
    final rating = info?.rating;
    final pricePence = ref.watch(ridePricesProvider).value?[ride.id];

    final completed = ride.status == RideStatus.completed;
    final cancelled = ride.status == RideStatus.cancelled;
    final (statusLabel, tone) = switch (ride.status) {
      RideStatus.completed => ('Completed', PillTone.success),
      RideStatus.cancelled => ('Cancelled', PillTone.error),
      _ => ('Active', PillTone.accent),
    };

    return Padding(
      padding: EdgeInsets.symmetric(vertical: hoppin.spacing.xs),
      child: HopCard(
        // The receipt is PUSHED: it is a leaf the rider comes back from, and
        // `go` would replace this list — so back from the receipt would fall
        // through to a fallback instead of returning to the history they were
        // scrolling. Resuming an in-progress trip is a `go`: that is a
        // destination, not a leaf, and it should not stack over the tab.
        onTap: () => completed
            ? unawaited(context.push('/trip/${ride.id}/receipt'))
            : context.go('/trip/${ride.id}'),
        padding: EdgeInsets.symmetric(
          horizontal: hoppin.spacing.lg,
          vertical: hoppin.spacing.md,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    destination ?? 'Ride',
                    style: type.titleSmall.copyWith(color: colors.textHi),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    ride.createdAt == null
                        ? '—'
                        : formatShortDateTime(ride.createdAt!),
                    style: type.bodySmall.copyWith(color: colors.textMid),
                  ),
                ],
              ),
            ),
            SizedBox(width: hoppin.spacing.md),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (!cancelled && pricePence != null) ...[
                  Text(
                    formatPence(pricePence),
                    style: type.ledger.copyWith(
                      color: colors.textHi,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: hoppin.spacing.xs),
                ],
                // The driver's star rating on completed rows (Figma) — hidden
                // gracefully when the identity seam answers null, never a 0.
                if (completed && rating != null) ...[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.star, size: 14, color: colors.warn),
                      SizedBox(width: hoppin.spacing.xs),
                      Text(
                        rating.toStringAsFixed(1),
                        style: type.metaSmall.copyWith(color: colors.textMid),
                      ),
                    ],
                  ),
                  SizedBox(height: hoppin.spacing.xs),
                ],
                StatusPill(label: statusLabel, tone: tone),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
