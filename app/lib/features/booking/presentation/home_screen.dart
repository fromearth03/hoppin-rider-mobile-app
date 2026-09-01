import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/error_codes.dart';
import '../../../core/result.dart';
import '../../../core/theme/colors.dart';
import '../../../shared/nav/app_drawer.dart';
import '../../../shared/nav/app_router.dart';
import '../../trip/data/ride_context_repository.dart';
import '../application/booking_draft.dart';
import '../data/saved_locations_repository.dart';
import '../data/vehicle_repository.dart';
import 'widgets/rider_map.dart';
import 'widgets/vehicle_card.dart';

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
/// A full-bleed map with a white booking sheet over it. Tapping the
/// "Ride Type" card toggles the vehicle grid, exactly as the two frames draw
/// the same screen in its two states.
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

  String? _selectedCategoryId;
  bool _pickerOpen = false;
  RiderMapController? _map;

  @override
  void initState() {
    super.initState();
    if (!_resumeCheckedThisLaunch) {
      _resumeCheckedThisLaunch = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _resumeActiveRide());
    }
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
    final categories = ref.watch(vehicleCategoriesProvider);
    final saved = ref.watch(homeSavedLocationsProvider);

    return Scaffold(
      drawer: const AppDrawer(),
      body: Stack(
        children: [
          Positioned.fill(
            child: RiderMap(onMapCreated: (c) => _map = c),
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
                PointerInterceptor(
                  child: _BookingSheet(
                    categories: categories,
                    saved: saved,
                    selectedId: _selectedCategoryId,
                    pickerOpen: _pickerOpen,
                    onSelect: (id) {
                      setState(() => _selectedCategoryId = id);
                      // Carried into fare-confirm so the rider is never
                      // asked to pick the same vehicle twice.
                      ref
                          .read(draftVehicleCategoryProvider.notifier)
                          .state = id;
                    },
                    onTogglePicker: () =>
                        setState(() => _pickerOpen = !_pickerOpen),
                  ),
                ),
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
  final AsyncValue<List<VehicleCategory>> categories;
  final AsyncValue<List<SavedLocation>> saved;
  final String? selectedId;
  final bool pickerOpen;
  final ValueChanged<String> onSelect;
  final VoidCallback onTogglePicker;

  const _BookingSheet({
    required this.categories,
    required this.saved,
    required this.selectedId,
    required this.pickerOpen,
    required this.onSelect,
    required this.onTogglePicker,
  });

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
      child: AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ModeRow(pickerOpen: pickerOpen, onTogglePicker: onTogglePicker),
            if (pickerOpen) ...[
              const SizedBox(height: 12),
              _Categories(
                categories: categories,
                selectedId: selectedId,
                onSelect: onSelect,
              ),
            ],
            const SizedBox(height: 12),
            const _SearchField(),
            _SavedList(saved: saved),
          ],
        ),
      ),
    );
  }
}

/// "Ride Type" and "Schedule Ride", in both frame states.
///
/// Collapsed (`Ride Type.png`): a wide bordered card with the orange car and
/// the "Pick the vehicle that fits your trip" line, plus a square schedule
/// button. Expanded (`Select Vehicle.png`): two labelled chips side by side.
class _ModeRow extends StatelessWidget {
  final bool pickerOpen;
  final VoidCallback onTogglePicker;

  const _ModeRow({required this.pickerOpen, required this.onTogglePicker});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final rideTypeCard = Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTogglePicker,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: EdgeInsets.symmetric(
              horizontal: 12, vertical: pickerOpen ? 12 : 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.navy, width: 1.4),
          ),
          child: Row(
            children: [
              SvgPicture.asset('assets/vehicles/car_orange.svg',
                  width: 34, height: 24),
              const SizedBox(width: 10),
              if (pickerOpen)
                Text('Ride Type',
                    style: theme.textTheme.titleMedium?.copyWith(
                        fontSize: 14.5, color: AppColors.navy))
              else
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

    if (!pickerOpen) {
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

    return Row(
      children: [
        Expanded(child: rideTypeCard),
        const SizedBox(width: 10),
        Expanded(
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            elevation: 1,
            child: InkWell(
              onTap: scheduleTap,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    scheduleIcon,
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text('Schedule Ride',
                          style: theme.textTheme.titleMedium?.copyWith(
                              fontSize: 14.5, color: AppColors.navy),
                          overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Categories extends StatelessWidget {
  final AsyncValue<List<VehicleCategory>> categories;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  const _Categories({
    required this.categories,
    required this.selectedId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return categories.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      ),
      // The server's own message, never invented copy: one backend code
      // carries two unrelated meanings distinguished only by its text.
      error: (e, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          e is ApiException
              ? RiderErrorCopy.messageFor(e)
              : 'Could not load vehicles.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.negative),
        ),
      ),
      data: (list) {
        if (list.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text('No vehicles available right now.',
                textAlign: TextAlign.center),
          );
        }

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: list.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            mainAxisExtent: 66,
          ),
          itemBuilder: (_, i) {
            final c = list[i];
            return VehicleCard(
              category: c,
              selected: c.id == selectedId,
              onTap: () => onSelect(c.id),
            );
          },
        );
      },
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
            onTap: () => context.push(AppRoutes.route),
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
