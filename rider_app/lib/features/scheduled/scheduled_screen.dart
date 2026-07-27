import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

import '../booking/booking_builder.dart';
import 'schedule_picker.dart';
import 'scheduled_builder.dart';
import 'scheduled_state.dart';

/// The scheduled-rides list (Figma scheduled-list frame). Dumb by contract:
/// renders [ScheduledState], forwards intents to the interactor, owns zero
/// timers, never navigates and never talks to the data layer directly.
///
/// Loads `GET /scheduled-rides` on mount. Each row is the upcoming pickup
/// time + status. An empty set shows the designed empty state; a read failure
/// shows the friendly error rung (never a raw 500 — gap #22).
///
/// Reminder pairing (a notification before the pickup) is Phase 11's job — the
/// list ships now; the reminder is a disclosed seam with no UI wired here.
class ScheduledScreen extends ConsumerStatefulWidget {
  const ScheduledScreen({super.key});

  @override
  ConsumerState<ScheduledScreen> createState() => _ScheduledScreenState();
}

class _ScheduledScreenState extends ConsumerState<ScheduledScreen> {
  @override
  void initState() {
    super.initState();
    // Load once on open; a NotifierProvider is created lazily so the first
    // read here is what kicks the fetch.
    Future.microtask(() {
      if (!mounted) return;
      ref.read(scheduledInteractorProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(scheduledInteractorProvider);
    final hoppin = context.hoppin;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // A DEAD END until now. This screen sits OUTSIDE the shell, so it
            // gets no bottom nav and no shell bar, and the stock AppBar it used
            // only auto-draws a back arrow when `Navigator.canPop()` is true.
            // It is reached with `context.go`, which REPLACES rather than
            // pushes — so there was nothing to pop, no arrow ever rendered, and
            // the rider was stranded on the scheduled list. The design-system
            // bar with a real back intent is the only thing that gives it an
            // exit. Pop when there is a stack; otherwise fall back to Book,
            // which is where the rider came from.
            HopTopBar(
              title: 'Scheduled rides',
              onBack: () =>
                  context.canPop() ? context.pop() : context.go('/book'),
            ),
            Expanded(child: _body(context, state, hoppin)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openPicker(context),
        icon: const Icon(Icons.add),
        label: const Text('Schedule a ride'),
      ),
    );
  }

  /// Opens the ≥30-min [SchedulePicker] and, on a valid confirm, binds
  /// `POST /scheduled-rides` via the interactor. The pickup/dropoff are read
  /// from the current booking selection (the scheduled surface is entered from
  /// the Book screen) — with pickup/dropoff already chosen a future ride is
  /// created; without them the rider is told to pick locations first (honest,
  /// never a silent no-op).
  Future<void> _openPicker(BuildContext context) async {
    final booking = ref.read(bookingInteractorProvider);
    final pickup = booking.pickup;
    final dropoff = booking.dropoff;
    final colors = context.hoppin.colors;

    if (pickup == null || dropoff == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Choose your pickup and destination on the Book screen first, '
            'then schedule it for later.',
          ),
          backgroundColor: colors.textHi,
        ),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      elevation: 0,
      backgroundColor: Colors.transparent,
      barrierColor: colors.scrim,
      builder: (_) => HopSheet(
        child: SchedulePicker(
          onConfirm: (when) {
            Navigator.of(context).pop();
            ref
                .read(scheduledInteractorProvider.notifier)
                .create(
                  pickupLat: pickup.lat,
                  pickupLng: pickup.lng,
                  dropoffLat: dropoff.lat,
                  dropoffLng: dropoff.lng,
                  requestedPickupTime: when,
                  // No client-held estimate id on the FareEstimate model — the
                  // server prices the scheduled ride at pickup time. Left null
                  // until an estimate-id is carried on the contract.
                  estimatedFareId: null,
                );
          },
        ),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    ScheduledState state,
    HoppinTokens hoppin,
  ) {
    switch (state.phase) {
      case ScheduledPhase.idle:
      case ScheduledPhase.loading:
        if (state.rides.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        // A refresh over an existing list — keep the list, don't flash a
        // spinner over content.
        return _list(context, state, hoppin);

      case ScheduledPhase.error:
        return ListView(
          padding: EdgeInsets.all(hoppin.spacing.gutter),
          children: [
            HopBanner.error(message: state.error ?? 'Something went wrong.'),
            SizedBox(height: hoppin.spacing.lg),
            HopButton.secondary(
              label: 'Try again',
              onPressed: () =>
                  ref.read(scheduledInteractorProvider.notifier).load(),
            ),
          ],
        );

      case ScheduledPhase.ready:
        if (state.rides.isEmpty) {
          return ListView(
            padding: EdgeInsets.all(hoppin.spacing.gutter),
            children: [
              SizedBox(height: hoppin.spacing.xl),
              const HopEmptyState(
                headline: 'No scheduled rides',
                supporting: 'Book a ride for later and it will appear here.',
              ),
            ],
          );
        }
        return _list(context, state, hoppin);
    }
  }

  Widget _list(
    BuildContext context,
    ScheduledState state,
    HoppinTokens hoppin,
  ) {
    return RefreshIndicator(
      onRefresh: () => ref.read(scheduledInteractorProvider.notifier).load(),
      child: ListView.builder(
        padding: EdgeInsets.symmetric(
          horizontal: hoppin.spacing.gutter,
          vertical: hoppin.spacing.md,
        ),
        itemCount: state.rides.length,
        itemBuilder: (context, i) => _ScheduledRow(ride: state.rides[i]),
      ),
    );
  }
}

/// One scheduled ride — the upcoming pickup time as the title, the status as
/// a trailing pill. Booked-for time is the money detail here.
class _ScheduledRow extends StatelessWidget {
  const _ScheduledRow({required this.ride});

  final ScheduledRide ride;

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;
    final type = hoppin.type;

    final (label, tone) = switch (ride.status) {
      'converted_to_active_ride' => ('On its way', PillTone.accent),
      'searching_for_driver' => ('Finding driver', PillTone.accent),
      _ => ('Scheduled', PillTone.success),
    };

    return Padding(
      padding: EdgeInsets.symmetric(vertical: hoppin.spacing.xs),
      child: HopCard(
        padding: EdgeInsets.symmetric(
          horizontal: hoppin.spacing.lg,
          vertical: hoppin.spacing.md,
        ),
        child: Row(
          children: [
            Icon(Icons.schedule, color: colors.accent),
            SizedBox(width: hoppin.spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    formatShortDateTime(ride.requestedPickupTime),
                    style: type.titleSmall.copyWith(color: colors.textHi),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Booked for later',
                    style: type.bodySmall.copyWith(color: colors.textMid),
                  ),
                ],
              ),
            ),
            SizedBox(width: hoppin.spacing.md),
            StatusPill(label: label, tone: tone),
          ],
        ),
      ),
    );
  }
}
