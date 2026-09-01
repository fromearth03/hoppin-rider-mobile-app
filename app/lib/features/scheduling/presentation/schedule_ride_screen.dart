import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/error_codes.dart';
import '../../../core/result.dart';
import '../../../core/theme/colors.dart';
import '../../../shared/nav/app_drawer.dart';
import '../../../shared/nav/app_router.dart';
import '../../booking/data/fare_repository.dart';
import '../../booking/data/vehicle_repository.dart';
import '../../booking/presentation/route_entry_screen.dart'
    show ChosenRoute;
import '../../booking/presentation/widgets/rider_map.dart';
import '../../booking/presentation/widgets/vehicle_card.dart';
import '../data/scheduled_rides_repository.dart';

/// The rider's booked future rides, refreshed after every create/cancel.
final _scheduledListProvider =
    FutureProvider.autoDispose<List<ScheduledRide>>((ref) async {
  final result = await ref.watch(scheduledRidesRepositoryProvider).list();
  return switch (result) {
    Ok(:final value) => value,
    Err(:final error) => throw error,
  };
});

/// Rider cancellation scenarios for the policy card the frame draws.
final _policyProvider =
    FutureProvider.autoDispose<List<CancellationScenario>>((ref) async {
  final result =
      await ref.watch(scheduledRidesRepositoryProvider).cancellationPolicy();
  return switch (result) {
    Ok(:final value) => value,
    Err(:final error) => throw error,
  };
});

/// Live vehicle categories for the "Ride Type" picker, from `GET
/// /vehicle-types` -- the same call and the same live values `Select
/// Vehicle` renders. This screen used to hardcode Standard/Estate/MPV/Minibus
/// with the exact seats/bags numbers `Select Vehicle`'s own decision log
/// records as wrong (Estate 4/4 vs live 5/4, MPV 6/4 vs live 7/5, Minibus
/// 16/12 vs live 8/6) -- fixed here to read the same source of truth rather
/// than repeat a rejected set of numbers.
final _vehicleCatalogueProvider =
    FutureProvider.autoDispose<List<VehicleCategory>>((ref) async {
  final result = await ref.watch(vehicleRepositoryProvider).list();
  return switch (result) {
    Ok(:final value) => value.where((c) => c.hasCapacity).toList(),
    Err(:final error) => throw error,
  };
});


/// Schedule Ride — matches `docs/figma/extracted/Schedule Ride.png`, wired
/// to the live `POST/GET/DELETE /scheduled-rides` surface (verified in
/// `ride_handler.go`; an earlier build believed the docs that said this was
/// a later milestone — the endpoints exist and dispatch's watchdog activates
/// the ride as the pickup window opens).
///
/// The frame's fare section draws Base + Surge rows; the estimate endpoint
/// returns a total (and duration) with no base/surge split for a future
/// ride, so the card shows the real total honestly rather than inventing a
/// split — recorded in docs/SCREEN-DECISIONS.md.
class ScheduleRideScreen extends ConsumerStatefulWidget {
  const ScheduleRideScreen({super.key});

  @override
  ConsumerState<ScheduleRideScreen> createState() =>
      _ScheduleRideScreenState();
}

class _ScheduleRideScreenState extends ConsumerState<ScheduleRideScreen> {
  DateTime? _scheduledFor;
  String? _selectedVehicleId;
  ChosenRoute? _route;
  bool _submitting = false;
  String? _serverError;

  Future<void> _pickRoute() async {
    // Editing an already-chosen route arrives pre-filled; only a first pick
    // starts blank.
    final result = await context.push(
      AppRoutes.route,
      extra: _route ?? 'pick',
    );
    if (result is ChosenRoute && mounted) {
      setState(() {
        _route = result;
        _serverError = null;
      });
    }
  }

  Future<void> _submit() async {
    final route = _route;
    final when = _scheduledFor;
    if (route == null || when == null || _submitting) return;

    setState(() {
      _submitting = true;
      _serverError = null;
    });

    final result = await ref.read(scheduledRidesRepositoryProvider).create(
          pickup: route.pickup.position,
          dropoff: route.dropoff.position,
          pickupTime: when,
          vehicleCategoryId: _selectedVehicleId,
        );
    if (!mounted) return;

    switch (result) {
      case Ok():
        setState(() {
          _submitting = false;
          _route = null;
          _scheduledFor = null;
        });
        ref.invalidate(_scheduledListProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Ride scheduled. A driver is dispatched as the '
                  'pickup time approaches.')),
        );
      case Err(:final error):
        setState(() {
          _submitting = false;
          // The 30-minute rule especially: the server's own words.
          _serverError = RiderErrorCopy.messageFor(error);
        });
    }
  }

  Future<void> _cancelScheduled(ScheduledRide ride) async {
    final result =
        await ref.read(scheduledRidesRepositoryProvider).cancel(ride.id);
    if (!mounted) return;
    switch (result) {
      case Ok():
        ref.invalidate(_scheduledListProvider);
      case Err(:final error):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(RiderErrorCopy.messageFor(error))),
        );
    }
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _scheduledFor ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 90)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: _scheduledFor != null
          ? TimeOfDay.fromDateTime(_scheduledFor!)
          : TimeOfDay.fromDateTime(now),
    );
    if (time == null) return;

    setState(() {
      _scheduledFor =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final scheduledLabel = _scheduledFor == null
        ? 'Choose a date and time'
        : DateFormat('MMMM d, yyyy  -  h:mm a').format(_scheduledFor!);

    return Scaffold(
      drawer: const AppDrawer(),
      body: Stack(
        children: [
          // The real map behind the sheet, as the frame draws it.
          const Positioned.fill(child: RiderMap()),
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            // Builder: `Scaffold.of` needs a context BELOW this Scaffold.
            // The hamburger opens the same side nav as Home — a drawn menu
            // button that does nothing reads as broken.
            child: Builder(
              builder: (context) => Material(
                color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                shape: const CircleBorder(),
                elevation: 2,
                child: InkWell(
                  onTap: () => Scaffold.of(context).openDrawer(),
                  customBorder: const CircleBorder(),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Icon(Icons.menu,
                        size: 22,
                        color: isDark
                            ? AppColors.darkTextPrimary
                            : AppColors.lightTextPrimary),
                  ),
                ),
              ),
            ),
          ),
          // This screen is PUSHED from the drawer; without an exit the rider
          // was stranded (the hamburger above is decorative map chrome, per
          // the frame). Same circled close as route entry.
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            right: 16,
            child: CircleAvatar(
              backgroundColor:
                  isDark ? AppColors.darkSurface : AppColors.lightSurface,
              child: IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: Icon(Icons.close,
                    size: 20,
                    color: isDark
                        ? AppColors.darkTextPrimary
                        : AppColors.lightTextPrimary),
                tooltip: 'Close',
              ),
            ),
          ),
          DraggableScrollableSheet(
            initialChildSize: 0.82,
            // Collapsible to a peek so the rider can actually see and use
            // the map behind the form; snaps between peek / open / full.
            minChildSize: 0.16,
            maxChildSize: 0.95,
            snap: true,
            snapSizes: const [0.16, 0.82],
            builder: (context, scrollController) {
              return Container(
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.darkBackground
                      : AppColors.lightBackground,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: ListView(
                  key: const Key('scheduleRideSheetList'),
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppColors.darkBorder
                              : AppColors.lightBorder,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    _HeaderCard(isDark: isDark),
                    const SizedBox(height: 24),
                    Text('Schedule for', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    _FieldTile(
                      label: scheduledLabel,
                      isPlaceholder: _scheduledFor == null,
                      trailingIcon: Icons.calendar_today_outlined,
                      onTap: _pickDateTime,
                      isDark: isDark,
                    ),
                    const SizedBox(height: 20),
                    Text('Route', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    // ONE bar, exactly like Home's "Where to?": tap once,
                    // pick pickup + destination together; afterwards it
                    // shows "From → To" and tapping edits pre-filled. Two
                    // fields that both opened the same both-ends picker
                    // read as broken.
                    _RouteBar(route: _route, onTap: _pickRoute),
                    const SizedBox(height: 24),
                    Text('Ride Type', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    _vehicleCatalogue(theme, isDark),
                    const SizedBox(height: 24),
                    _fareEstimate(theme, isDark),
                    const SizedBox(height: 24),
                    Text('Cancellation Policy',
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    _policyCard(theme, isDark),
                    if (_serverError != null) ...[
                      const SizedBox(height: 16),
                      Text(_serverError!,
                          style: const TextStyle(color: AppColors.negative)),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primaryDark,
                        minimumSize: const Size.fromHeight(52),
                      ),
                      onPressed:
                          _route != null && _scheduledFor != null && !_submitting
                              ? _submit
                              : null,
                      child: Text(_submitting
                          ? 'Scheduling…'
                          : 'Confirm Schedule'),
                    ),
                    const SizedBox(height: 28),
                    _upcomingList(theme, isDark),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  /// The Ride Type grid, driven by the live `GET /vehicle-types` catalogue --
  /// see the provider doc above for why this replaced a hardcoded, partly
  /// wrong four-category list. Loading/error states are quiet placeholders
  /// rather than blocking spinners or error banners, since the rest of this
  /// screen (date/time, route fields) works regardless of whether the
  /// catalogue has loaded and the submit path is unavailable either way.
  Widget _vehicleCatalogue(ThemeData theme, bool isDark) {
    final catalogue = ref.watch(_vehicleCatalogueProvider);

    return catalogue.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Text(
        'Could not load vehicle types',
        style: theme.textTheme.bodyMedium,
      ),
      data: (categories) {
        if (categories.isEmpty) {
          return Text('No vehicles available right now',
              style: theme.textTheme.bodyMedium);
        }

        final selectedId = _selectedVehicleId ?? categories.first.id;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: categories.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            // A fixed aspect ratio shrinks cell height along with cell width
            // as the screen narrows, while the two lines of text inside each
            // tile (name + seats/bags) do not shrink to match — at 320px
            // wide that squeeze overflowed the tile's Column by a couple of
            // pixels. 1.9 keeps cells comfortably tall enough at narrow
            // widths without a visible change at the 430px Figma width.
            childAspectRatio: 1.9,
          ),
          itemBuilder: (context, index) {
            final category = categories[index];
            final selected = category.id == selectedId;
            return _VehicleTile(
              category: category,
              selected: selected,
              isDark: isDark,
              onTap: () => setState(() => _selectedVehicleId = category.id),
            );
          },
        );
      },
    );
  }

  /// Fare Estimate, as the frame draws the section. The estimate endpoint
  /// returns a total and duration with no base/surge split for a future
  /// ride, so the real total renders and nothing is invented.
  Widget _fareEstimate(ThemeData theme, bool isDark) {
    final route = _route;
    final catalogue = ref.watch(_vehicleCatalogueProvider).valueOrNull;
    final categoryId = _selectedVehicleId ??
        (catalogue != null && catalogue.isNotEmpty ? catalogue.first.id : null);

    final rows = <Widget>[];
    if (route == null || categoryId == null) {
      rows.add(Text('Choose a route to see your fare.',
          style: theme.textTheme.bodyMedium));
    } else {
      final quote = ref.watch(_quoteProvider((
        pickup: route.pickup.position,
        dropoff: route.dropoff.position,
        categoryId: categoryId,
      )));
      rows.add(quote.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Center(
              child: SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))),
        ),
        error: (error, _) => Text(
          error is ApiException
              ? RiderErrorCopy.messageFor(error)
              : 'Could not quote this trip.',
          style: const TextStyle(color: AppColors.negative),
        ),
        data: (estimate) => Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Total', style: theme.textTheme.titleMedium),
            Text(estimate.totalPence.format(currency: estimate.currency),
                style: theme.textTheme.titleMedium),
          ],
        ),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Fare Estimate', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
            border: Border.all(
                color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: rows),
        ),
      ],
    );
  }

  /// The rider's cancellation scenarios from `GET /cancellation-policy`,
  /// rendered with the server's own labels and fees.
  Widget _policyCard(ThemeData theme, bool isDark) {
    final policy = ref.watch(_policyProvider);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        border: Border.all(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
        borderRadius: BorderRadius.circular(16),
      ),
      child: policy.when(
        loading: () => Text('Loading policy…', style: theme.textTheme.bodyMedium),
        error: (_, __) => Text(
          'Cancellation fees may apply after a driver is assigned.',
          style: theme.textTheme.bodyMedium,
        ),
        data: (scenarios) => scenarios.isEmpty
            ? Text('No cancellation fee applies to this trip.',
                style: theme.textTheme.bodyMedium)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final s in scenarios) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                            child: Text(s.label,
                                style: theme.textTheme.bodyMedium)),
                        const SizedBox(width: 12),
                        Text(
                          s.feePence.value == 0 ? 'Free' : s.feePence.format(),
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                    if (s != scenarios.last) const SizedBox(height: 8),
                  ],
                ],
              ),
      ),
    );
  }

  /// The rider's booked future rides, with a cancel per row. Not drawn on
  /// the frame, but a booking the rider cannot see or cancel would be worse
  /// than the section's absence.
  Widget _upcomingList(ThemeData theme, bool isDark) {
    final list = ref.watch(_scheduledListProvider);

    return list.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (rides) {
        final upcoming = rides
            .where((r) => r.status != 'cancelled' && r.activeRideId == null)
            .toList(growable: false);
        if (upcoming.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Upcoming rides', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final ride in upcoming) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color:
                      isDark ? AppColors.darkSurface : AppColors.lightSurface,
                  border: Border.all(
                      color: isDark
                          ? AppColors.darkBorder
                          : AppColors.lightBorder),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            ride.requestedPickupTime == null
                                ? 'Scheduled ride'
                                : DateFormat('MMM d, yyyy  -  h:mm a').format(
                                    ride.requestedPickupTime!.toLocal()),
                            style: theme.textTheme.bodyLarge,
                          ),
                          if (ride.vehicleCategory != null ||
                              ride.estimatePence != null)
                            Text(
                              [
                                if (ride.vehicleCategory != null)
                                  ride.vehicleCategory!,
                                if (ride.estimatePence != null)
                                  ride.estimatePence!
                                      .format(currency: ride.currency),
                              ].join('  ·  '),
                              style: theme.textTheme.bodyMedium,
                            ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => _cancelScheduled(ride),
                      child: const Text('Cancel',
                          style: TextStyle(color: AppColors.negative)),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// One quote for the chosen route + category, cached per key so reselecting
/// a vehicle re-uses the fetched estimate.
final _quoteProvider = FutureProvider.autoDispose.family<FareEstimate,
    ({LatLng pickup, LatLng dropoff, String categoryId})>((ref, key) async {
  final result = await ref.watch(fareRepositoryProvider).estimate(
        pickup: key.pickup,
        dropoff: key.dropoff,
        vehicleCategoryId: key.categoryId,
      );
  return switch (result) {
    Ok(:final value) => value,
    Err(:final error) => throw error,
  };
});

class _HeaderCard extends StatelessWidget {
  final bool isDark;
  const _HeaderCard({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final border = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    // The frame's header: the orange car in a white rounded square, beside a
    // navy-bordered card carrying the calendar icon + title/subtitle.
    return Row(
      children: [
        // The orange car is the way BACK to a normal (now) booking — the
        // calendar card beside it is this screen's own mode.
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: () => context.go(AppRoutes.home),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border.all(color: border),
                borderRadius: BorderRadius.circular(14),
              ),
              child: SvgPicture.asset('assets/vehicles/car_orange.svg',
                  width: 34, height: 24),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: AppColors.navy, width: 1.2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                SvgPicture.asset('assets/icons/schedule_ride.svg',
                    width: 26, height: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Schedule Ride',
                          style: theme.textTheme.titleMedium?.copyWith(
                              fontSize: 15, color: AppColors.navy),
                          overflow: TextOverflow.ellipsis),
                      Text('Book your ride in advance',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(fontSize: 11.5),
                          overflow: TextOverflow.ellipsis),
                    ],
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

/// Home's "Where to?" bar, reused for the scheduled route: one tap opens the
/// route picker once; a chosen route renders as "From → To" and tapping
/// again edits it pre-filled.
class _RouteBar extends StatelessWidget {
  final ChosenRoute? route;
  final VoidCallback onTap;

  const _RouteBar({required this.route, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chosen = route;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      elevation: 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Icon(
                chosen == null ? Icons.search : Icons.route_outlined,
                color: chosen == null
                    ? theme.textTheme.bodyMedium?.color
                    : AppColors.navy,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: chosen == null
                    ? Text('Where to & from?',
                        style:
                            theme.textTheme.bodyMedium?.copyWith(fontSize: 14),
                        overflow: TextOverflow.ellipsis)
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(chosen.pickup.label,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                  fontSize: 13.5, color: AppColors.navy),
                              overflow: TextOverflow.ellipsis),
                          Text(
                            '→ ${chosen.dropoff.label}'
                            '${chosen.stops.isNotEmpty ? '  ·  ${chosen.stops.length} stop${chosen.stops.length == 1 ? '' : 's'}' : ''}',
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
              ),
              const Icon(Icons.edit_outlined,
                  size: 18, color: AppColors.lightTextSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _FieldTile extends StatelessWidget {
  final String label;
  final bool isPlaceholder;
  final IconData trailingIcon;
  final VoidCallback onTap;
  final bool isDark;

  const _FieldTile({
    required this.label,
    required this.isPlaceholder,
    required this.trailingIcon,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final border = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final surface = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final textColor = isPlaceholder
        ? (isDark ? AppColors.darkTextDisabled : AppColors.lightTextDisabled)
        : (isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: surface,
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: theme.textTheme.bodyLarge?.copyWith(color: textColor)),
            ),
            Icon(trailingIcon,
                size: 18,
                color: isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.lightTextSecondary),
          ],
        ),
      ),
    );
  }
}

class _VehicleTile extends StatelessWidget {
  final VehicleCategory category;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;

  const _VehicleTile({
    required this.category,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Same tile as the home picker (`Select Vehicle.png`): white card, the
    // supplied car render, grey fill when selected. One widget, one look.
    return VehicleCard(category: category, selected: selected, onTap: onTap);
  }
}

