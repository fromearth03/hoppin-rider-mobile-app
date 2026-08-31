import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/result.dart';
import '../../../core/theme/colors.dart';
import '../../booking/data/vehicle_repository.dart';

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

/// Icon keyed by category name, with a generic fallback -- mirrors
/// `vehicle_card.dart`'s `_Artwork`. The API has no image field and
/// categories are admin-editable, so a name this map has never heard of must
/// still render something rather than nothing.
IconData _iconFor(String name) => switch (name.toLowerCase().replaceAll(' ', '')) {
      'standard' => Icons.directions_car,
      'minicar' => Icons.directions_car_outlined,
      'estate' => Icons.directions_car_filled,
      'mpv' => Icons.airport_shuttle_outlined,
      'minibus' => Icons.airport_shuttle,
      'minitruck' => Icons.local_shipping_outlined,
      _ => Icons.directions_car_outlined,
    };

/// Schedule Ride — matches `docs/figma/extracted/Schedule Ride.png`.
///
/// **Scheduling is not wired to the backend.** The API does expose
/// `POST /api/v1/scheduled-rides` (`docs/SCREEN-API-MATRIX.md:74`) with a
/// `GET`/`DELETE` pair alongside it, and dispatch even auto-activates a
/// scheduled ride ~15 minutes before its pickup window
/// (`docs/BACKEND-RIDER-APP-ROUND5-2026-08-30.md:56`). But:
///
/// - `docs/superpowers/specs/2026-08-30-rider-app-milestone1-design.md:57`
///   lists "scheduled rides" under "Out — later milestones".
/// - `docs/superpowers/plans/2026-08-31-batch-2-booking-data.md:1165`:
///   "`/scheduled-rides` is out of milestone 1."
/// - `lib/features/booking/data/booking_repository.dart`'s `request()` takes
///   `pickup`, `dropoff`, `vehicleCategoryId` and `waypoints` only -- no
///   scheduled/future pickup-time parameter exists anywhere.
/// - There is no `scheduled_rides_repository.dart` (or any scheduling data
///   source) anywhere in this codebase to call the endpoint through.
///
/// So this screen renders the full drawn layout -- date/time, route fields,
/// vehicle picker -- but the submit path is an honest "arrives in a later
/// milestone" state rather than a button that pretends to book. This mirrors
/// how `app_drawer.dart`'s milestone-2 destinations are shown but disabled
/// (see `docs/SCREEN-DECISIONS.md`, "Side navigation"), and avoids the one
/// outcome the project rules explicitly forbid: a control that silently
/// drops the rider's chosen time.
class ScheduleRideScreen extends ConsumerStatefulWidget {
  const ScheduleRideScreen({super.key});

  @override
  ConsumerState<ScheduleRideScreen> createState() =>
      _ScheduleRideScreenState();
}

class _ScheduleRideScreenState extends ConsumerState<ScheduleRideScreen> {
  DateTime? _scheduledFor;
  String? _selectedVehicleId;

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
      body: Stack(
        children: [
          // Map placeholder behind the sheet, matching the drawn layout. The
          // real map lives on the booking home screen; this feature owns no
          // map integration.
          Positioned.fill(
            child: Container(
              color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            child: CircleAvatar(
              backgroundColor:
                  isDark ? AppColors.darkSurface : AppColors.lightSurface,
              child: Icon(Icons.menu,
                  color: isDark
                      ? AppColors.darkTextPrimary
                      : AppColors.lightTextPrimary),
            ),
          ),
          DraggableScrollableSheet(
            initialChildSize: 0.82,
            minChildSize: 0.82,
            maxChildSize: 0.95,
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
                    Text('From', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    _FieldTile(
                      label: 'Pickup location',
                      isPlaceholder: true,
                      trailingIcon: Icons.edit_outlined,
                      onTap: () {},
                      isDark: isDark,
                    ),
                    const SizedBox(height: 20),
                    Text('To', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    _FieldTile(
                      label: 'Destination',
                      isPlaceholder: true,
                      trailingIcon: Icons.edit_outlined,
                      onTap: () {},
                      isDark: isDark,
                    ),
                    const SizedBox(height: 24),
                    Text('Ride Type', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    _vehicleCatalogue(theme, isDark),
                    const SizedBox(height: 28),
                    _UnavailableNotice(isDark: isDark),
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
            childAspectRatio: 2.2,
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
}

class _HeaderCard extends StatelessWidget {
  final bool isDark;
  const _HeaderCard({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final border = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    return Row(
      children: [
        Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: border),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(Icons.directions_car, color: AppColors.accent),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              border: Border.all(color: border),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.calendar_month,
                        size: 18, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Text('Schedule Ride', style: theme.textTheme.titleMedium),
                  ],
                ),
                const SizedBox(height: 2),
                Text('Book your ride in advance',
                    style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ),
      ],
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
    final theme = Theme.of(context);
    final border = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final surface = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final selectedFill =
        isDark ? AppColors.darkBorder : AppColors.lightBorder;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? selectedFill : surface,
          border: Border.all(
            color: selected ? AppColors.primary : border,
            width: selected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(_iconFor(category.name),
                color: isDark
                    ? AppColors.darkTextPrimary
                    : AppColors.lightTextPrimary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(category.name,
                      style: theme.textTheme.labelLarge,
                      overflow: TextOverflow.ellipsis),
                  // Same rule as the vehicle picker: a category configured
                  // with neither seats nor bags shows no capacity line
                  // rather than "0 Seats 0 Bags".
                  if (category.hasCapacity)
                    Text('${category.seats} Seats ${category.bags} Bags',
                        style: theme.textTheme.bodyMedium,
                        overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The honest state in place of a fare estimate and a submit button.
///
/// See the class doc on [ScheduleRideScreen] for why: scheduling has no
/// wired backend path from this app, so nothing here claims to book, quote,
/// or estimate a fare for a future pickup time.
class _UnavailableNotice extends StatelessWidget {
  final bool isDark;
  const _UnavailableNotice({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final border = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final surface = isDark ? AppColors.darkSurface : AppColors.lightSurface;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline, color: AppColors.info, size: 20),
              const SizedBox(width: 8),
              Text('Not available yet', style: theme.textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Scheduled rides arrive in a later milestone. You can book an '
            'immediate ride from the home screen today.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          const SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: null,
              child: Text('Confirm Schedule (coming soon)'),
            ),
          ),
        ],
      ),
    );
  }
}
