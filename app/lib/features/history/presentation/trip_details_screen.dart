import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/error_codes.dart';
import '../../../core/result.dart';
import '../../../core/theme/colors.dart';
import '../../../shared/widgets/profile_avatar.dart';
import '../../payments/data/receipts_repository.dart';
import '../../payments/presentation/ride_complete_screen.dart'
    show rideCompleteContextProvider;
import '../../payments/presentation/widgets/route_preview.dart';
import '../../trip/data/live_trip_source.dart' show LiveTripInfo;

final _receiptProvider =
    FutureProvider.autoDispose.family<Receipt, String>((ref, rideId) async {
  // An empty id only comes from a hand-typed URL; the request it would
  // send — /rides//receipt — is malformed. Fail here without the network.
  if (rideId.isEmpty) {
    throw const ApiException(
        'RIDE_NOT_FOUND', 'This ride could not be found.', 0);
  }
  final result = await ref.watch(receiptsRepositoryProvider).forRide(rideId);
  return switch (result) {
    Ok(:final value) => value,
    Err(:final error) => throw error,
  };
});

/// A past ride's receipt: total charged, distance and duration.
///
/// Backed entirely by `GET /rides/:id/receipt` via [ReceiptsRepository]. That
/// endpoint returns no fare component split (no base/distance/time/wait
/// breakdown) - see the "Ride complete" decision in SCREEN-DECISIONS.md, which
/// applies identically here since both screens read the same [Receipt]. This
/// screen shows only what the receipt actually carries: it does not invent a
/// breakdown, and it does not show driver details the receipt has no field for.
class TripDetailsScreen extends ConsumerWidget {
  final String rideId;

  const TripDetailsScreen({super.key, required this.rideId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receipt = ref.watch(_receiptProvider(rideId));
    // Route + driver enrichment off `GET /rides/:id` — best-effort; its
    // failure never takes the receipt down with it.
    final detail = ref.watch(rideCompleteContextProvider(rideId));

    return Scaffold(
      appBar: AppBar(title: const Text('Trip Details')),
      body: receipt.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              e is ApiException
                  ? RiderErrorCopy.messageFor(e)
                  : 'Could not load this trip.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.negative),
            ),
          ),
        ),
        data: (r) =>
            _TripDetailsBody(receipt: r, detail: detail.valueOrNull),
      ),
    );
  }
}

class _TripDetailsBody extends StatelessWidget {
  final Receipt receipt;
  final LiveTripInfo? detail;
  const _TripDetailsBody({required this.receipt, required this.detail});

  /// Both timestamps are nullable and independently absent. Only render a
  /// duration when both are actually present - anything else would be a
  /// guess dressed up as a number.
  Duration? get _duration {
    final pickup = receipt.pickupTime;
    final dropoff = receipt.dropoffTime;
    if (pickup == null || dropoff == null) return null;
    final delta = dropoff.difference(pickup);
    return delta.isNegative ? null : delta;
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    if (minutes < 1) return '<1 min';
    return '$minutes min';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final duration = _duration;
    final route = detail?.route;
    final driver = detail?.driver;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // The frame's route snapshot above the summary.
        if (route != null && route.length >= 2) ...[
          RoutePreview(points: route),
          const SizedBox(height: 16),
        ],
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Journey Summary', style: theme.textTheme.titleMedium),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: _SummaryStat(
                        icon: Icons.place_outlined,
                        label: 'Distance',
                        value: receipt.distanceMiles == null
                            ? '—'
                            : '${receipt.distanceMiles!.toStringAsFixed(1)} mi',
                      ),
                    ),
                    Expanded(
                      child: _SummaryStat(
                        icon: Icons.access_time,
                        label: 'Duration',
                        value: duration == null
                            ? '—'
                            : _formatDuration(duration),
                      ),
                    ),
                    Expanded(
                      child: _SummaryStat(
                        icon: Icons.attach_money,
                        label: 'Total Fare',
                        value: _totalLabel,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Total Fare',
                    style: theme.textTheme.headlineLarge
                        ?.copyWith(fontSize: 24)),
                const SizedBox(height: 4),
                Text(_totalLabel, style: theme.textTheme.headlineLarge),
                if (receipt.hasWaitingCharge) ...[
                  const Divider(height: 28),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text('Waiting time',
                            style: theme.textTheme.bodyMedium),
                      ),
                      Text(
                        receipt.waitingPence!.format(currency: receipt.currency),
                        style: theme.textTheme.bodyLarge,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        // The frame's Your Driver card, when the ride detail carries one.
        if (driver != null) ...[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  ProfileAvatar(
                      avatarUrl: driver.avatarUrl,
                      name: driver.name,
                      radius: 26),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Your Driver',
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(fontSize: 12)),
                        Text(driver.name,
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontSize: 17)),
                        if (driver.hasRating)
                          Row(
                            children: [
                              const Icon(Icons.star_rounded,
                                  size: 16, color: AppColors.warning),
                              const SizedBox(width: 3),
                              Text(
                                '${driver.rating!.toStringAsFixed(1)}'
                                '${driver.ratingCount > 0 ? ' (${driver.ratingCount})' : ''}',
                                style: theme.textTheme.bodyMedium
                                    ?.copyWith(fontSize: 12),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (receipt.pickupTime != null) ...[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Date', style: theme.textTheme.bodyMedium),
                  Flexible(
                    child: Text(
                      DateFormat('d MMM yyyy, HH:mm')
                          .format(receipt.pickupTime!.toLocal()),
                      style: theme.textTheme.bodyLarge,
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// "Not yet charged" rather than "£0.00" - a null total means the ride has
  /// not been charged, not that it was free. Rendering it as zero would lie
  /// about money.
  String get _totalLabel => receipt.totalPence == null
      ? 'Not yet charged'
      : receipt.totalPence!.format(currency: receipt.currency);
}

class _SummaryStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _SummaryStat({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: theme.colorScheme.surface,
          child: Icon(icon, size: 18),
        ),
        const SizedBox(height: 6),
        Text(label, style: theme.textTheme.bodyMedium),
        Text(
          value,
          style: theme.textTheme.labelLarge,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
