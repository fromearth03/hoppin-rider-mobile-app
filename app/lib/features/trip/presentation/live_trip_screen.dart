import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;

import '../../../core/api/error_codes.dart';
import '../../../core/geo.dart' as geo;
import '../../../core/result.dart';
import '../../../core/theme/colors.dart';
import '../../../shared/nav/app_router.dart';
import '../../booking/presentation/widgets/map_markers.dart';
import '../../booking/presentation/widgets/rider_map.dart';
import '../data/live_trip_source.dart';
import '../data/ride_actions_repository.dart';
import '../data/ride_context_repository.dart';
import 'widgets/driver_info_card.dart';
import 'widgets/glass_chip.dart';
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
        // Prefer the payload's own id: the route param may be a dispatch
        // request id (or empty straight after booking), and chat / safety /
        // cancel must hit the REAL ride.
        data: (info) => _LiveTripBody(
          info: info,
          rideId: info.rideId.isNotEmpty ? info.rideId : rideId,
        ),
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
    final cancelled = info.status == LiveTripStatus.cancelled;

    return Stack(
      children: [
        Positioned.fill(child: _TripMap(info: info, rideId: rideId)),
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
              // right-aligned within the full-width column above. A dead
              // ride has nobody to chat with and nothing to escalate.
              if (!cancelled)
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
        // Terminal state: say it plainly and offer the way forward, instead
        // of spinning on "finding your driver" for a ride that died.
        if (cancelled)
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              minimum: const EdgeInsets.all(16),
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                elevation: 8,
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('This ride was cancelled',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                  fontSize: 17, color: AppColors.navy)),
                      const SizedBox(height: 6),
                      Text(
                        'No driver could be found nearby, or the ride was '
                        'cancelled. You have not been charged.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 14),
                      FilledButton(
                        onPressed: () => context.go(AppRoutes.home),
                        child: const Text('Book again'),
                      ),
                    ],
                  ),
                ),
              ),
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
        if (!cancelled)
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
    // The configured rider reasons (best-effort: an unreachable list must
    // never block the cancel — the ride is always escapable).
    final reasonsResult =
        await ref.read(rideActionsRepositoryProvider).cancellationReasons();
    final reasons = switch (reasonsResult) {
      Ok(:final value) => value,
      Err() => const <RiderCancelReason>[],
    };
    if (!context.mounted) return;

    final outcome = await showModalBottomSheet<(bool, String?)>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _CancelReasonSheet(reasons: reasons),
    );
    if (outcome == null || outcome.$1 != true || !context.mounted) return;

    final result = await ref
        .read(rideActionsRepositoryProvider)
        .cancelRide(rideId, reasonId: outcome.$2);
    if (!context.mounted) return;

    switch (result) {
      case Ok():
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ride cancelled.')),
        );
        context.go(AppRoutes.home);
      // The ride is already terminal — dispatch auto-cancelled it (no
      // driver) a moment before the tap, or it completed. From the rider's
      // seat that IS a successful cancel, not an error to apologise for.
      case Err(:final error) when error.code == 'ILLEGAL_TRANSITION':
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This ride has already ended.')),
        );
        context.go(AppRoutes.home);
      case Err(:final error):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(RiderErrorCopy.messageFor(error))),
        );
    }
  }
}

/// The map layer of `Driver Arrived.png` / `Start Ride.png`: the ride's
/// route polyline, its pickup/stop/dropoff pins and the driver's live
/// position over the shared [RiderMap].
///
/// Owns two pieces of state the stateless body cannot: the camera (fit to the
/// route exactly once per route, not on every poll tick) and the ~3s driver
/// position poll off `GET /rides/:id/driver-location`.
class _TripMap extends ConsumerStatefulWidget {
  final LiveTripInfo info;
  final String rideId;

  const _TripMap({required this.info, required this.rideId});

  @override
  ConsumerState<_TripMap> createState() => _TripMapState();
}

class _TripMapState extends ConsumerState<_TripMap> {
  RiderMapController? _controller;
  Timer? _driverPoll;
  gmaps.LatLng? _driverPos;

  /// The route the camera was last fitted to; refit only when it changes.
  int _fittedRouteLength = -1;

  /// Labeled waypoint pins (A / 1 / 2 / B), built async once per waypoint
  /// set — the rider must see exactly where each stop sits.
  int _builtWpCount = -1;
  Set<gmaps.Marker> _wpMarkers = const {};

  @override
  void initState() {
    super.initState();
    _driverPoll = Timer.periodic(
        const Duration(seconds: 3), (_) => _pollDriver());
  }

  @override
  void dispose() {
    _driverPoll?.cancel();
    super.dispose();
  }

  Future<void> _pollDriver() async {
    final id = widget.rideId;
    if (id.isEmpty) return;
    // Only while a driver actually exists on a live ride: polling during
    // matching (no driver yet) or after a terminal state is a guaranteed
    // 409 every three seconds.
    final status = widget.info.status;
    if (widget.info.driver == null ||
        status == LiveTripStatus.matching ||
        status == LiveTripStatus.completed ||
        status == LiveTripStatus.cancelled) {
      if (_driverPos != null && mounted) setState(() => _driverPos = null);
      return;
    }
    final pos =
        await ref.read(rideContextRepositoryProvider).driverPosition(id);
    if (!mounted) return;
    setState(() =>
        _driverPos = pos == null ? null : gmaps.LatLng(pos.lat, pos.lng));
  }

  gmaps.LatLng _g(geo.LatLng p) => gmaps.LatLng(p.lat, p.lng);

  @override
  Widget build(BuildContext context) {
    final route = widget.info.route;
    final waypoints = widget.info.waypoints;

    final polylines = <gmaps.Polyline>{
      if (route != null && route.length >= 2)
        gmaps.Polyline(
          polylineId: const gmaps.PolylineId('route'),
          points: [for (final p in route) _g(p)],
          color: AppColors.navy,
          width: 5,
        ),
    };

    _maybeBuildWpMarkers(waypoints);
    final markers = <gmaps.Marker>{..._wpMarkers};
    if (_driverPos != null) {
      markers.add(gmaps.Marker(
        markerId: const gmaps.MarkerId('driver'),
        position: _driverPos!,
        icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(
            gmaps.BitmapDescriptor.hueViolet),
        infoWindow: const gmaps.InfoWindow(title: 'Your driver'),
        anchor: const Offset(0.5, 0.5),
      ));
    }

    _maybeFitCamera(route);

    return RiderMap(
      markers: markers,
      polylines: polylines,
      onMapCreated: (c) {
        _controller = c;
        _fittedRouteLength = -1; // fit once the controller exists
        _maybeFitCamera(route);
      },
      // Keep Google's chrome clear of the driver card.
      padding: const EdgeInsets.only(bottom: 180),
    );
  }

  void _maybeBuildWpMarkers(List<TripWaypoint> waypoints) {
    // No engine, no bitmaps: tests and desktop render the placeholder, and
    // the canvas futures would outlive a test's teardown.
    if (!RiderMap.mapSupported) return;
    if (waypoints.length == _builtWpCount) return;
    _builtWpCount = waypoints.length;
    _buildWpMarkers(List.of(waypoints));
  }

  Future<void> _buildWpMarkers(List<TripWaypoint> waypoints) async {
    final markers = <gmaps.Marker>{};
    for (var i = 0; i < waypoints.length; i++) {
      final pos = waypoints[i].position;
      if (pos == null) continue;
      final isFirst = i == 0;
      final isLast = i == waypoints.length - 1;
      // Pickup A (blue), stops numbered (orange), dropoff B (green).
      final label = isFirst ? 'A' : (isLast ? 'B' : '$i');
      final color = isFirst
          ? AppColors.info
          : (isLast ? AppColors.positive : AppColors.accent);
      markers.add(gmaps.Marker(
        markerId: gmaps.MarkerId(
            isFirst ? 'pickup' : (isLast ? 'dropoff' : 'stop$i')),
        position: _g(pos),
        icon: await circleLabelMarker(label, color),
        infoWindow: gmaps.InfoWindow(
            title: isFirst || isLast
                ? waypoints[i].label
                : 'Stop $i — ${waypoints[i].label}'),
      ));
    }
    if (mounted) setState(() => _wpMarkers = markers);
  }

  void _maybeFitCamera(List<geo.LatLng>? route) {
    final c = _controller;
    if (c == null || route == null || route.length < 2) return;
    if (_fittedRouteLength == route.length) return;
    _fittedRouteLength = route.length;

    var minLat = route.first.lat, maxLat = route.first.lat;
    var minLng = route.first.lng, maxLng = route.first.lng;
    for (final p in route) {
      if (p.lat < minLat) minLat = p.lat;
      if (p.lat > maxLat) maxLat = p.lat;
      if (p.lng < minLng) minLng = p.lng;
      if (p.lng > maxLng) maxLng = p.lng;
    }
    c.fitBounds(
      gmaps.LatLngBounds(
        southwest: gmaps.LatLng(minLat, minLng),
        northeast: gmaps.LatLng(maxLat, maxLng),
      ),
      64,
    );
  }
}

/// "Why are you cancelling?" — the admin-configured rider reasons as a radio
/// list, fee-bearing ones labelled honestly ("a fee may apply", with the
/// free window when one is configured). The reason is optional: the ride
/// must always be escapable, so "Prefer not to say" cancels with no reason
/// and the server derives any fee from ride state either way.
class _CancelReasonSheet extends StatefulWidget {
  final List<RiderCancelReason> reasons;
  const _CancelReasonSheet({required this.reasons});

  @override
  State<_CancelReasonSheet> createState() => _CancelReasonSheetState();
}

class _CancelReasonSheetState extends State<_CancelReasonSheet> {
  String? _selected;

  String? _feeHint(RiderCancelReason r) {
    if (!r.appliesFee) return null;
    final fee = r.feeAmount;
    final free = r.freeCancelSeconds;
    final feePart = fee != null && fee > 0
        ? 'A £${fee.toStringAsFixed(2)} fee may apply'
        : 'A fee may apply';
    if (free != null && free > 0) {
      final mins = (free / 60).round();
      return '$feePart · free within ${mins < 1 ? '$free sec' : '$mins min'}';
    }
    return feePart;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          children: [
            Text('Cancel this ride?',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontSize: 17, color: AppColors.navy)),
            const SizedBox(height: 4),
            Text('Tell us why (optional):',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            for (final r in widget.reasons)
              RadioListTile<String>(
                value: r.id,
                // ignore: deprecated_member_use
                groupValue: _selected,
                // ignore: deprecated_member_use
                onChanged: (v) => setState(() => _selected = v),
                dense: true,
                contentPadding: EdgeInsets.zero,
                activeColor: AppColors.navy,
                title: Text(r.label, style: const TextStyle(fontSize: 14)),
                subtitle: _feeHint(r) == null
                    ? null
                    : Text(_feeHint(r)!,
                        style: const TextStyle(
                            fontSize: 11.5, color: AppColors.warning)),
              ),
            RadioListTile<String>(
              value: '',
              // ignore: deprecated_member_use
              groupValue: _selected,
              // ignore: deprecated_member_use
              onChanged: (v) => setState(() => _selected = v),
              dense: true,
              contentPadding: EdgeInsets.zero,
              activeColor: AppColors.navy,
              title: const Text('Prefer not to say',
                  style: TextStyle(fontSize: 14)),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(
                  (true, _selected == null || _selected!.isEmpty
                      ? null
                      : _selected)),
              child: const Text('Cancel Ride'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop((false, null)),
              child: const Text('Keep ride'),
            ),
          ],
        ),
      ),
    );
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
    return GlassChip(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
