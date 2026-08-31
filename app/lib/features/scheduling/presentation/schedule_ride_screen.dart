import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/colors.dart';

/// One vehicle category tile, matching `Select Vehicle`'s live values.
///
/// Scheduling has no fare-quote call wired to a future pickup time anywhere
/// in this codebase (see the class doc on [ScheduleRideScreen]), so seats and
/// bags are shown for context only -- never a fare.
class _VehicleOption {
  final String name;
  final int seats;
  final int bags;
  final IconData icon;

  const _VehicleOption(this.name, this.seats, this.bags, this.icon);
}

const _vehicleOptions = [
  _VehicleOption('Standard', 4, 2, Icons.directions_car),
  _VehicleOption('Estate', 4, 4, Icons.directions_car_filled),
  _VehicleOption('MPV', 6, 4, Icons.airport_shuttle),
  _VehicleOption('Minibus', 16, 12, Icons.directions_bus),
];

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
class ScheduleRideScreen extends StatefulWidget {
  const ScheduleRideScreen({super.key});

  @override
  State<ScheduleRideScreen> createState() => _ScheduleRideScreenState();
}

class _ScheduleRideScreenState extends State<ScheduleRideScreen> {
  DateTime? _scheduledFor;
  int _selectedVehicle = 0;

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
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _vehicleOptions.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 2.2,
                      ),
                      itemBuilder: (context, index) {
                        final option = _vehicleOptions[index];
                        final selected = index == _selectedVehicle;
                        return _VehicleTile(
                          option: option,
                          selected: selected,
                          isDark: isDark,
                          onTap: () =>
                              setState(() => _selectedVehicle = index),
                        );
                      },
                    ),
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
  final _VehicleOption option;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;

  const _VehicleTile({
    required this.option,
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
            Icon(option.icon,
                color: isDark
                    ? AppColors.darkTextPrimary
                    : AppColors.lightTextPrimary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(option.name, style: theme.textTheme.labelLarge),
                  Text('${option.seats} Seats ${option.bags} Bags',
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
