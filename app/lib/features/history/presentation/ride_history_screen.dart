import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/error_codes.dart';
import '../../../core/result.dart';
import '../../../core/theme/colors.dart';
import '../../../shared/nav/app_router.dart';
import '../data/trip_history_repository.dart';

final _historyProvider =
    FutureProvider.autoDispose<TripHistoryPage>((ref) async {
  final result = await ref.watch(tripHistoryRepositoryProvider).myTrips();
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
      body: history.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _HistoryMessage(
          icon: Icons.error_outline,
          // Server copy wins; RiderErrorCopy is only the net for a malformed
          // envelope.
          message: e is ApiException
              ? RiderErrorCopy.messageFor(e)
              : 'Could not load your ride history.',
          tone: AppColors.negative,
        ),
        data: (page) => page.trips.isEmpty
            ? const _HistoryMessage(
                icon: Icons.history,
                message: 'No rides yet',
                detail: 'Trips you take will appear here.',
              )
            : RefreshIndicator(
                onRefresh: () async => ref.refresh(_historyProvider.future),
                child: _HistoryList(trips: page.trips),
              ),
      ),
    );
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
