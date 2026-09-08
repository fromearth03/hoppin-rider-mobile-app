import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/error_codes.dart';
import '../../../core/result.dart';
import '../../../shared/nav/app_router.dart';
import '../data/booking_repository.dart';
import '../data/fare_repository.dart' show FareEstimate;
import '../data/promo_repository.dart';
import '../data/vehicle_repository.dart';
import 'fare_confirm_screen.dart';
import 'home_screen.dart' show vehicleCategoriesProvider;
import 'route_entry_screen.dart' show ChosenRoute;

/// Owns the fare-confirm step of the booking flow: fetches the categories,
/// hands them to [FareConfirmScreen], books the chosen one, and moves the
/// rider to the live trip.
///
/// Booking is fire-and-forget on the server — a 202 with a request id means
/// dispatch has the request, not that a driver exists — so success navigates
/// straight to the trip screen's honest "finding your driver" state carrying
/// that id.
class FareConfirmFlow extends ConsumerStatefulWidget {
  final ChosenRoute route;

  const FareConfirmFlow({super.key, required this.route});

  @override
  ConsumerState<FareConfirmFlow> createState() => _FareConfirmFlowState();
}

class _FareConfirmFlowState extends ConsumerState<FareConfirmFlow> {
  bool _booking = false;

  Future<void> _book(VehicleCategory category, FareEstimate? estimate,
      String note, String promoCode) async {
    if (_booking) return; // a double-tap on Confirm must not book twice
    setState(() => _booking = true);

    final result = await ref.read(bookingRepositoryProvider).request(
          pickup: widget.route.pickup.position,
          dropoff: widget.route.dropoff.position,
          vehicleCategoryId: category.id,
          // Labels travel with the stops, so the trip screen names them the
          // way the rider chose them instead of falling back to "Stop 1".
          waypoints: [
            for (final stop in widget.route.stops)
              (label: stop.label, position: stop.position),
          ],
          // The confirmed quote rides along so the booking-created ride
          // carries the exact fare the rider agreed to.
          estimatePence: estimate?.totalPence.value ?? 0,
          estimateDistanceMeters: estimate?.distanceMeters ?? 0,
          estimateDurationSeconds: estimate?.durationSeconds ?? 0,
          pickupLabel: widget.route.pickup.label,
          dropoffLabel: widget.route.dropoff.label,
          riderNote: note,
        );
    if (!mounted) return;
    setState(() => _booking = false);

    switch (result) {
      case Ok(:final value):
        // A promo can only be applied once a ride exists — the discount is
        // computed from the ride's quoted fare, and the zone and minimum-spend
        // rules need a real journey to check against. So it happens here, after
        // booking, not as part of the request.
        //
        // A refusal must NOT block the ride. The rider has confirmed a fare and
        // a driver is being found; losing the trip because a code was ineligible
        // would be a far worse outcome than paying full price. Tell them and
        // carry on.
        if (promoCode.isNotEmpty) {
          final applied = await ref
              .read(promoRepositoryProvider)
              .applyToRide(value.rideId, promoCode);
          if (!mounted) return;
          switch (applied) {
            case Ok(value: final promo):
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('${promo.code} applied — '
                    '£${promo.discountAmount.toStringAsFixed(2)} off.'),
              ));
            case Err(:final error):
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(
                    '${RiderErrorCopy.messageFor(error)} Your ride is still booked.'),
              ));
          }
        }
        if (!mounted) return;
        // The returned id IS the ride id now (the server creates the ride at
        // booking), so the trip screen binds to it instantly; /me/active-ride
        // stays as the fallback resolver for stale links.
        context.go('${AppRoutes.liveTrip}?ride=${value.rideId}');
      case Err(:final error):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(RiderErrorCopy.messageFor(error))),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(vehicleCategoriesProvider);

    return categories.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, __) => Scaffold(
        appBar: AppBar(title: const Text('Pricing Details')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Could not load vehicle options.',
                    style: Theme.of(context).textTheme.bodyLarge),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => ref.invalidate(vehicleCategoriesProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
      data: (list) => FareConfirmScreen(
        pickup: widget.route.pickup.position,
        dropoff: widget.route.dropoff.position,
        waypoints: [for (final stop in widget.route.stops) stop.position],
        categories: list,
        routeLabels: [
          widget.route.pickup.label,
          for (final stop in widget.route.stops) stop.label,
          widget.route.dropoff.label,
        ],
        onConfirm: _book,
      ),
    );
  }
}
