import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/error_codes.dart';
import '../../../core/result.dart';
import '../../../core/theme/colors.dart';
import '../../../shared/nav/app_router.dart';
import '../../booking/presentation/widgets/rider_map.dart';
import '../data/live_trip_source.dart';
import '../data/ride_actions_repository.dart';
import '../data/ride_context_repository.dart';
import 'widgets/driver_info_card.dart';
import 'widgets/trip_route_header.dart';
import 'widgets/trip_status_banner.dart';
import 'widgets/turn_banner.dart';

/// Streams [LiveTripInfo] for one ride from [LiveTripSource].
///
/// `autoDispose` + `family`: each ride gets its own subscription, torn down
/// when the screen watching it is gone, matching the pattern used by
/// `rideReceiptProvider` and `emergencyContactsProvider` elsewhere in the app.
final liveTripInfoProvider =
    StreamProvider.autoDispose.family<LiveTripInfo, String>(
  // The real `GET /rides/:id` poll — the spec's documented fallback
  // transport. The moment dispatch assigns a driver, this stream carries
  // the driver card onto the screen.
  (ref, rideId) => ref.watch(rideContextRepositoryProvider).watch(rideId),
);

/// Driver Arrived / Start Ride / trip-in-progress, combined into one screen
/// driven by [LiveTripInfo.status].
///
/// The Figma pack draws these as two frames (`Driver Arrived.png`,
/// `Start Ride.png`) that share the same map, driver card and Cancel Ride
/// action -- they differ only in the status banner text, and the in-progress
/// state adds the turn-by-turn banner and a destination bar. One screen with
/// state-driven chrome avoids duplicating that shared shell.
///
/// **`GET /rides/:id` has no repository yet.** docs/SCREEN-DECISIONS.md
/// documents it as the call that would serve driver identity, rating with
/// count, trips completed, plate, vehicle type/capacity, the fare estimate
/// and the cancellation policy in one shot, but no method for it exists
/// anywhere in `lib/features/booking/data/` today. This screen is driven by
/// [LiveTripSource], an explicit placeholder that returns the honest
/// "finding your driver" state rather than inventing an endpoint call or
/// fabricating a driver. See that file for the full explanation.
///
/// The map is [RiderMap], reused exactly as `HomeScreen` uses it -- live
/// tiles on Android/iOS, the honest placeholder elsewhere. The route,
/// waypoint pins and driver marker this design draws over the map are not
/// rendered yet; they need the `GET /rides/:id` data this screen also lacks.
class LiveTripScreen extends ConsumerWidget {
  final String rideId;

  const LiveTripScreen({super.key, this.rideId = ''});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(liveTripInfoProvider(rideId));

    return Scaffold(
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        // A transport hiccup degrades to the same honest awaiting state
        // rather than a dead-end error screen -- the rider is mid-trip and
        // needs Cancel Ride and SOS to keep working regardless.
        error: (_, __) => _LiveTripBody(
          info: LiveTripInfo.awaiting(rideId),
          rideId: rideId,
        ),
        data: (info) => _LiveTripBody(info: info, rideId: rideId),
      ),
    );
  }
}

class _LiveTripBody extends ConsumerWidget {
  final LiveTripInfo info;
  final String rideId;

  const _LiveTripBody({required this.info, required this.rideId});

  bool get _isDriving =>
      info.status == LiveTripStatus.accepted ||
      info.status == LiveTripStatus.arriving ||
      info.status == LiveTripStatus.started;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final topInset = MediaQuery.of(context).padding.top + 12;

    return Stack(
      children: [
        const Positioned.fill(child: RiderMap()),
        Positioned(
          top: topInset,
          left: 16,
          right: 16,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TripStatusBanner(status: info.status),
              if (_isDriving) TurnBanner(steps: info.steps),
              const SizedBox(height: 10),
              // The frame's glass route panel — pickup, stops, dropoff over
              // the map. Renders only once the ride's geo block arrives.
              TripRouteHeader(waypoints: info.waypoints),
              const SizedBox(height: 10),
              // A persistent way to reach chat and SOS regardless of whether
              // a driver has been assigned yet -- SOS in particular must
              // remain a real safety control throughout matching, not only
              // once a driver exists to message. Stacked below the status
              // banner rather than beside it, so the two never overlap, and
              // right-aligned within the full-width column above.
              Align(
                alignment: Alignment.centerRight,
                child: _QuickActions(
                  rideId: rideId,
                  driverName: info.driver?.name,
                ),
              ),
            ],
          ),
        ),
        if (info.status == LiveTripStatus.started &&
            info.destinationLabel != null)
          Positioned(
            left: 16,
            right: 16,
            bottom: 220,
            child: _DestinationBar(label: info.destinationLabel!),
          ),
        Align(
          alignment: Alignment.bottomCenter,
          child: DriverInfoCard(
            driver: info.driver,
            totalPence: info.totalPence,
            currency: info.currency,
            onChat: () => context.push(
              '${AppRoutes.chat}?ride=$rideId&driver=${Uri.encodeComponent(info.driver?.name ?? 'Driver')}',
            ),
            onSafety: () => context.push('${AppRoutes.safety}?ride=$rideId'),
            onCancel: () => _confirmCancel(context, ref),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmCancel(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel this ride?'),
        content: const Text(
          'The cancellation policy for this trip may apply a fee.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep ride'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Cancel Ride'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    // The dialog's answer used to be discarded here — the button looked
    // live and cancelled nothing, leaving the request queued in dispatch.
    final result =
        await ref.read(rideActionsRepositoryProvider).cancelRide(rideId);
    if (!context.mounted) return;

    switch (result) {
      case Ok():
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ride cancelled.')),
        );
        context.go(AppRoutes.home);
      case Err(:final error):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(RiderErrorCopy.messageFor(error))),
        );
    }
  }
}

class _QuickActions extends StatelessWidget {
  final String rideId;
  final String? driverName;

  const _QuickActions({required this.rideId, required this.driverName});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _CircleButton(
          icon: Icons.chat_bubble,
          onTap: () => context.push(
            '${AppRoutes.chat}?ride=$rideId&driver=${Uri.encodeComponent(driverName ?? 'Driver')}',
          ),
        ),
        const SizedBox(width: 10),
        _CircleButton(
          icon: Icons.warning_rounded,
          color: AppColors.negative,
          onTap: () => context.push('${AppRoutes.safety}?ride=$rideId'),
        ),
      ],
    );
  }
}

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final VoidCallback onTap;

  const _CircleButton({required this.icon, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, size: 20, color: color ?? AppColors.primary),
        ),
      ),
    );
  }
}

/// The "Destination" bar on `Start Ride.png`, shown only once the trip has
/// actually started -- before that there is no in-progress journey to name a
/// destination for.
class _DestinationBar extends StatelessWidget {
  final String label;
  const _DestinationBar({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Destination',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
