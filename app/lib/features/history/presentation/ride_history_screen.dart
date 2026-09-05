import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/error_codes.dart';
import '../../../core/result.dart';
import '../../../core/theme/colors.dart';
import '../../../shared/nav/app_router.dart';
import '../../booking/data/frequent_trips_repository.dart';
import '../../booking/presentation/home_screen.dart' show rebookFrequentTrip;
import '../data/trip_history_repository.dart';
import '../../../shared/widgets/skeleton.dart';

/// First day of the month the list is filtered to; null = all time.
/// Defaults to the current month, as the frame's "This Month" card shows.
final _monthProvider = StateProvider<DateTime?>((_) {
  final now = DateTime.now();
  return DateTime(now.year, now.month);
});

final _historyProvider =
    FutureProvider.autoDispose<TripHistoryPage>((ref) async {
  final month = ref.watch(_monthProvider);
  final result = await ref.watch(tripHistoryRepositoryProvider).myTrips(
        limit: 50,
        from: month,
        // End-exclusive: the first instant of the next month.
        to: month == null ? null : DateTime(month.year, month.month + 1),
      );
  return switch (result) {
    Ok(:final value) => value,
    Err(:final error) => throw error,
  };
});

/// Ride history, list view — backed by `GET /api/v1/rides`.
///
/// The contract is `rider_trips_read.go` (GetMyTrips): a `{"trips": [...],
/// "has_more": bool, "next_cursor": "<RFC3339>"}` envelope, created_at
/// descending, cursor-paged.
///
/// The frame draws only completed-looking rows, but the endpoint returns
/// cancelled trips too and hiding them would be its own kind of lie — a rider
/// who cancelled a ride should see it. A cancelled card renders a muted
/// "Cancelled" tag where a completed one renders the driver's rating.
///
/// Nothing here is fabricated. A trip with no driver, or a driver nobody has
/// rated, renders no stars rather than "0.0"; a trip that was never charged
/// renders no fare rather than "£0.00".
class RideHistoryScreen extends ConsumerWidget {
  const RideHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(_historyProvider);

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('Ride History'),
        // AppBar only draws a back button automatically when it can find a
        // route to pop to. In isolation (e.g. this screen opened directly, or
        // under test with no navigation stack) that auto-detection finds
        // nothing, so the design's back arrow is wired explicitly instead.
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: Column(
        children: [
          // Above the period filter, because it is not part of the filtered
          // history — it is a shortcut out of it. A rider who opens Ride
          // History to rebook the trip they always take should not have to
          // scroll through the trips to find it.
          const _FrequentTrips(),
          const _MonthFilterCard(),
          Expanded(
            child: history.when(
              // Skeleton rather than a spinner: it holds the exact space
              // the trip rows will take, so nothing jumps when they land.
              loading: () => const SkeletonList(rows: 6, leadingCircle: true),
              error: (e, _) => _HistoryMessage(
                icon: Icons.error_outline,
                // Server copy wins; RiderErrorCopy is only the net for a
                // malformed envelope.
                message: e is ApiException
                    ? RiderErrorCopy.messageFor(e)
                    : 'Could not load your ride history.',
                tone: AppColors.negative,
              ),
              data: (page) => page.trips.isEmpty
                  ? const _HistoryMessage(
                      icon: Icons.history,
                      message: 'No rides in this period',
                      detail: 'Trips you take will appear here.',
                    )
                  : RefreshIndicator(
                      onRefresh: () async =>
                          ref.refresh(_historyProvider.future),
                      child: _HistoryList(trips: page.trips),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The journeys this rider repeats, with a one-tap rebook.
///
/// Hidden entirely when there are none — which is most riders, and everyone
/// new. An empty "Frequent trips" heading over nothing is worse than no
/// heading, and a failed fetch degrades to the same silence rather than
/// putting an error above a screen that loaded fine.
class _FrequentTrips extends ConsumerWidget {
  const _FrequentTrips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trips = ref.watch(frequentTripsProvider).valueOrNull ?? const [];
    if (trips.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Your frequent trips',
              style: theme.textTheme.titleMedium?.copyWith(fontSize: 15)),
          const SizedBox(height: 8),
          for (final trip in trips)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: AppColors.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => rebookFrequentTrip(context, trip),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                    child: Row(
                      children: [
                        const Icon(Icons.replay,
                            size: 20, color: AppColors.primary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${trip.fromLabel} → ${trip.toLabel}',
                                style: theme.textTheme.bodyMedium
                                    ?.copyWith(fontSize: 14, height: 1.25),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                '${trip.tripCount} trips',
                                style: theme.textTheme.bodySmall?.copyWith(
                                    fontSize: 12,
                                    color: AppColors.lightTextSecondary),
                              ),
                            ],
                          ),
                        ),
                        Text('Rebook',
                            style: theme.textTheme.bodyMedium?.copyWith(
                                fontSize: 13, color: AppColors.primary)),
                        const Icon(Icons.chevron_right,
                            size: 20, color: AppColors.lightTextSecondary),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The frame's period card under the title: "This Month / 1 Aug - 31 Aug,
/// 2026 ▾". Tapping opens a picker of recent months plus All time; the list
/// refetches server-side (`GET /rides?from&to`) on change.
class _MonthFilterCard extends ConsumerWidget {
  const _MonthFilterCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final month = ref.watch(_monthProvider);
    final now = DateTime.now();

    final String title;
    final String range;
    if (month == null) {
      title = 'All time';
      range = 'Every trip you have taken';
    } else {
      final isThisMonth = month.year == now.year && month.month == now.month;
      title = isThisMonth ? 'This Month' : DateFormat('MMMM yyyy').format(month);
      final last = DateTime(month.year, month.month + 1, 0);
      range = '${DateFormat('d MMM').format(month)} - '
          '${DateFormat('d MMM, yyyy').format(last)}';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        elevation: 1,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _pick(context, ref, month),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                SvgPicture.asset('assets/icons/schedule_ride.svg',
                    width: 24, height: 26),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title,
                          style: theme.textTheme.titleMedium?.copyWith(
                              fontSize: 15, color: AppColors.navy)),
                      Text(range,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(fontSize: 11.5)),
                    ],
                  ),
                ),
                const Icon(Icons.keyboard_arrow_down,
                    color: AppColors.lightTextSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pick(
      BuildContext context, WidgetRef ref, DateTime? current) async {
    final now = DateTime.now();
    final months = [
      for (var i = 0; i < 12; i++) DateTime(now.year, now.month - i),
    ];

    final chosen = await showModalBottomSheet<Object>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            ListTile(
              title: const Text('All time'),
              trailing: current == null
                  ? const Icon(Icons.check, color: AppColors.navy)
                  : null,
              onTap: () => Navigator.of(ctx).pop('all'),
            ),
            for (final m in months)
              ListTile(
                title: Text(
                  m.year == now.year && m.month == now.month
                      ? 'This Month'
                      : DateFormat('MMMM yyyy').format(m),
                ),
                trailing: current != null &&
                        current.year == m.year &&
                        current.month == m.month
                    ? const Icon(Icons.check, color: AppColors.navy)
                    : null,
                onTap: () => Navigator.of(ctx).pop(m),
              ),
          ],
        ),
      ),
    );

    if (chosen == null) return;
    ref.read(_monthProvider.notifier).state =
        chosen == 'all' ? null : chosen as DateTime;
  }
}

/// The date-grouped list from the frame: a "16 Feb" header above the cards for
/// each distinct day, newest first (the order the server already returns).
class _HistoryList extends StatelessWidget {
  final List<TripHistoryItem> trips;

  const _HistoryList({required this.trips});

  /// Groups by local calendar day, preserving the server's ordering. A trip is
  /// filed under the day it actually ran where that is known, falling back to
  /// the day it was requested — which is all a cancelled ride has.
  List<_DaySection> get _sections {
    final sections = <_DaySection>[];
    for (final trip in trips) {
      final local = trip.displayTime.toLocal();
      final day = DateTime(local.year, local.month, local.day);
      if (sections.isNotEmpty && sections.last.day == day) {
        sections.last.trips.add(trip);
      } else {
        sections.add(_DaySection(day: day, trips: [trip]));
      }
    }
    return sections;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sections = _sections;

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: sections.length,
      itemBuilder: (context, i) {
        final section = sections[i];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 8 : 20, bottom: 10),
              child: Text(
                // "16 Feb", exactly as the frame heads each group.
                DateFormat('d MMM').format(section.day),
                style: theme.textTheme.titleMedium,
              ),
            ),
            for (final trip in section.trips)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _TripCard(trip: trip),
              ),
          ],
        );
      },
    );
  }
}

class _DaySection {
  final DateTime day;
  final List<TripHistoryItem> trips;

  _DaySection({required this.day, required this.trips});
}

/// One white card: pickup (pin) and dropoff (flag) rows with the fare
/// right-aligned, then the time bottom-left and the driver's rating (or a
/// cancelled tag) bottom-right.
class _TripCard extends StatelessWidget {
  final TripHistoryItem trip;

  const _TripCard({required this.trip});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.push('${AppRoutes.tripDetails}?ride=${trip.id}'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PlaceRow(
                icon: Icons.place,
                // The server can return a ride with no geocoded label. Saying
                // so beats an empty row that looks like a rendering bug.
                label: trip.pickupLabel ?? 'Pickup location unavailable',
                muted: trip.pickupLabel == null,
              ),
              const SizedBox(height: 8),
              // The dropoff row carries the fare on its right, as in the frame.
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: _PlaceRow(
                      icon: Icons.flag,
                      label:
                          trip.dropoffLabel ?? 'Dropoff location unavailable',
                      muted: trip.dropoffLabel == null,
                    ),
                  ),
                  if (trip.totalPence != null) ...[
                    const SizedBox(width: 12),
                    Text(
                      trip.totalPence!.format(currency: trip.currency),
                      style: theme.textTheme.bodyLarge,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      DateFormat('h:mm a').format(trip.displayTime.toLocal()),
                      style: theme.textTheme.bodyMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _TripTrailing(trip: trip),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The bottom-right slot: the driver's rating on a completed trip, a muted
/// "Cancelled" tag on a cancelled one, and deliberately nothing at all when
/// there is no driver or nobody has rated them yet.
class _TripTrailing extends StatelessWidget {
  final TripHistoryItem trip;

  const _TripTrailing({required this.trip});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (trip.isCancelled) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: theme.colorScheme.error.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          'Cancelled',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.error,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    final rating = trip.driver?.rating;
    // No driver, or a driver nobody has rated: render nothing rather than
    // inventing "0.0 (0)", which would libel a new driver.
    if (rating == null) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.star, size: 18, color: AppColors.warning),
        const SizedBox(width: 6),
        Text(
          '${rating.toStringAsFixed(1)} (${trip.driver!.ratingCount})',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurface),
        ),
      ],
    );
  }
}

class _PlaceRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool muted;

  const _PlaceRow({
    required this.icon,
    required this.label,
    this.muted = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 18, color: theme.colorScheme.onSurface),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: muted
                ? theme.textTheme.bodyMedium
                : theme.textTheme.bodyLarge,
            // One line, as the frame draws it: a place label that wraps makes
            // the card grow and breaks the even rhythm of the list. A long
            // address ellipsises instead — trip details carries the full one.
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// Empty and error states share one centred layout so neither can drift into
/// looking like a broken screen.
class _HistoryMessage extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? detail;
  final Color? tone;

  const _HistoryMessage({
    required this.icon,
    required this.message,
    this.detail,
    this.tone,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: tone ?? theme.textTheme.bodyMedium?.color),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(color: tone),
            ),
            if (detail != null) ...[
              const SizedBox(height: 8),
              Text(
                detail!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
