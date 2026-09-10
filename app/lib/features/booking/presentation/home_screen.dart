import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../../../core/geo.dart';
import '../../../core/result.dart';
import '../../../core/theme/colors.dart';
import '../../../shared/nav/app_drawer.dart';
import '../../../shared/nav/app_router.dart';
import '../../trip/data/ride_context_repository.dart';
import '../data/frequent_trips_repository.dart';
import '../data/saved_locations_repository.dart';
import '../data/vehicle_repository.dart';
import 'rebook.dart';
import 'route_entry_screen.dart' show RoutePoint, RoutePrefill;
import 'widgets/rider_map.dart';
import '../../../core/location/location_permission.dart';

/// The categories the rider can book, cheapest first.
///
/// Order comes from the server and is preserved. Re-sorting client-side would
/// reorder the picker away from what the operator configured in the admin
/// panel.
final vehicleCategoriesProvider =
    FutureProvider.autoDispose<List<VehicleCategory>>((ref) async {
  final result = await ref.watch(vehicleRepositoryProvider).list();
  return switch (result) {
    Ok(:final value) => value,
    Err(:final error) => throw error,
  };
});

/// Saved places shown under the search pill — the frame's recents list.
final homeSavedLocationsProvider =
    FutureProvider.autoDispose<List<SavedLocation>>((ref) async {
  final result = await ref.watch(savedLocationsRepositoryProvider).list();
  return switch (result) {
    Ok(:final value) => value,
    // Recents are decoration on Home; an error here should never block the
    // screen, so it degrades to an empty list.
    Err() => const <SavedLocation>[],
  };
});

/// Home — `Ride Type.png` collapsed, `Select Vehicle.png` expanded.
///
/// A full-bleed map with a white booking sheet over it.
///
/// The sheet does NOT ask which vehicle. The design pack draws that grid here,
/// but the fare screen has to ask again anyway — it is the only place a real
/// quote per category exists — so asking on Home put the same question to the
/// rider twice, the first time with no prices to answer it by. Both the Ride
/// Type card and the search field now open the booking flow, and the vehicle
/// is chosen once, against live fares.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  /// One check per app launch: a rider who reopens the app mid-ride must land
  /// ON that ride, nowhere else. Static so in-app navigation back to Home
  /// (e.g. from a completed trip) never bounces them again.
  static bool _resumeCheckedThisLaunch = false;

  RiderMapController? _map;

  /// Whether the map may show the rider's own position. Starts false so the
  /// first frame never asks the platform for a layer it has no permission for.
  bool _locationGranted = false;

  @override
  void initState() {
    super.initState();
    if (!_resumeCheckedThisLaunch) {
      _resumeCheckedThisLaunch = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _resumeActiveRide());
    }
    // Home is where the rider is deciding where they are going, so it is the
    // one moment the request explains itself. Previously nothing in the app
    // asked at all until a trip was already under way — see
    // LocationPermissionService for what that cost.
    WidgetsBinding.instance.addPostFrameCallback((_) => _askForLocation());
  }

  Future<void> _askForLocation() async {
    final granted = await LocationPermissionService.ensure();
    // Booking works fine from a typed address, so a refusal changes nothing
    // except the blue dot. Never block, never nag.
    if (!mounted || granted == _locationGranted) return;
    setState(() => _locationGranted = granted);
  }

  Future<void> _resumeActiveRide() async {
    final String? id;
    try {
      id = await ref.read(rideContextRepositoryProvider).activeRideId();
    } catch (_) {
      // The provider graph needs a live app bootstrap (Supabase session for
      // the token interceptor); in harnesses without one the resume check is
      // simply skipped — never a crash on the home screen.
      return;
    }
    if (!mounted || id == null) return;
    context.go('${AppRoutes.liveTrip}?ride=$id');
  }

  @override
  Widget build(BuildContext context) {
    final saved = ref.watch(homeSavedLocationsProvider);

    return Scaffold(
      drawer: const AppDrawer(),
      body: Stack(
        children: [
          Positioned.fill(
            child: RiderMap(
              onMapCreated: (c) => _map = c,
              showMyLocation: _locationGranted,
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 16,
            // Builder, not `context`: `Scaffold.of` needs a context BELOW the
            // Scaffold, and this screen's own context sits above it. Without
            // the Builder the menu button throws instead of opening.
            child: Builder(
              builder: (context) => MapCircleButton(
                icon: Icons.menu,
                onTap: () => Scaffold.of(context).openDrawer(),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // The frame's locate control: white circle, navigation arrow,
                // sat just above the sheet on the right.
                Padding(
                  padding: const EdgeInsets.only(right: 16, bottom: 12),
                  child: MapCircleButton(
                    icon: Icons.navigation_outlined,
                    onTap: () => _map?.moveTo(RiderMap.initialCamera),
                  ),
                ),
                // PointerInterceptor: on web the map is a DOM platform view
                // and touches over the sheet can fall through and pan the
                // map. No-op on native.
                PointerInterceptor(child: _BookingSheet(saved: saved)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The white circular button the frames float over the map (menu, locate).
class MapCircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const MapCircleButton({super.key, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(icon, size: 22, color: AppColors.navy),
        ),
      ),
    );
  }
}

class _BookingSheet extends StatelessWidget {
  final AsyncValue<List<SavedLocation>> saved;

  const _BookingSheet({required this.saved});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Color(0xFFF7F7FA),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
              color: Color(0x1F000000), blurRadius: 18, offset: Offset(0, -4)),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        MediaQuery.of(context).padding.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _ModeRow(),
          const SizedBox(height: 12),
          const _SearchField(),
          // Above saved places: a journey the rider has actually taken three
          // times is a better guess than a place they once bookmarked.
          const _FrequentTripRow(),
          _SavedList(saved: saved),
        ],
      ),
    );
  }
}

/// "Ride Type" and "Schedule Ride".
///
/// `Ride Type.png` draws this card as the handle for an inline vehicle grid
/// (`Select Vehicle.png` is the same screen expanded). It opens the booking
/// flow instead — the vehicle question belongs on the fare screen, where the
/// answer has prices attached. So the card is a way IN to booking, like the
/// search field below it, rather than a question of its own.
class _ModeRow extends StatelessWidget {
  const _ModeRow();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final rideTypeCard = Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => context.push(AppRoutes.route),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.navy, width: 1.4),
          ),
          child: Row(
            children: [
              SvgPicture.asset('assets/vehicles/car_orange.svg',
                  width: 34, height: 24),
              const SizedBox(width: 10),
              Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Ride Type',
                          style: theme.textTheme.titleMedium?.copyWith(
                              fontSize: 14.5, color: AppColors.navy)),
                      Text('Pick the vehicle that fits your trip',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(fontSize: 10.5),
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    final scheduleIcon =
        SvgPicture.asset('assets/icons/schedule_ride.svg', width: 26, height: 28);

    void scheduleTap() => context.push(AppRoutes.scheduleRide);

    return Row(
      children: [
        Expanded(child: rideTypeCard),
        const SizedBox(width: 10),
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          elevation: 1,
          child: InkWell(
            onTap: scheduleTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
                padding: const EdgeInsets.all(11), child: scheduleIcon),
          ),
        ),
      ],
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Material + InkWell rather than Container: the whole bar is the way
    // into route entry, and a tap target should ripple.
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      elevation: 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push(AppRoutes.route),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Icon(Icons.search,
                  color: theme.textTheme.bodyMedium?.color, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Where to & for how much?',
                  style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The saved places under the search pill — the frame lists them plainly with
/// an outline pin, no card chrome.
/// One-tap rebook for the rider's most-taken journey.
///
/// Only the top one, and only on Home: this sits under the search pill in the
/// booking sheet, and a list of five would push the sheet over the map it is
/// meant to sit on. The full list lives in Ride History.
class _FrequentTripRow extends ConsumerWidget {
  const _FrequentTripRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trips = ref.watch(frequentTripsProvider).valueOrNull ?? const [];
    if (trips.isEmpty) return const SizedBox.shrink();
    final trip = trips.first;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Material(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => rebookFrequentTrip(context, trip),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                const Icon(Icons.replay, size: 20, color: AppColors.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Book again: ${trip.toLabel}',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontSize: 14, height: 1.25),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'From ${trip.fromLabel} · ${trip.tripCount} trips',
                        style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 12, color: AppColors.lightTextSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right,
                    size: 20, color: AppColors.lightTextSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens the booking flow on a repeated journey with both ends filled.
void rebookFrequentTrip(BuildContext context, FrequentTrip trip) {
  rebookJourney(
    context,
    pickupLabel: trip.fromLabel,
    pickup: trip.pickup,
    dropoffLabel: trip.toLabel,
    dropoff: trip.dropoff,
  );
}

class _SavedList extends StatelessWidget {
  final AsyncValue<List<SavedLocation>> saved;

  const _SavedList({required this.saved});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final places = saved.valueOrNull ?? const <SavedLocation>[];
    if (places.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final p in places.take(2))
          InkWell(
            // Prefilled as the DESTINATION: a saved place tapped from Home is
            // where the rider wants to go. Opening a blank picker made the
            // list decorative.
            onTap: () => context.push(
              AppRoutes.route,
              extra: RoutePrefill(
                  dropoff: RoutePoint(p.label, LatLng(p.lat, p.lng))),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 11),
              child: Row(
                children: [
                  const Icon(Icons.location_on_outlined,
                      size: 20, color: AppColors.lightTextSecondary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      p.label,
                      style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
