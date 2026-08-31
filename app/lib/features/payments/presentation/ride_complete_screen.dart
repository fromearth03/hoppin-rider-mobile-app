import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/error_codes.dart';
import '../../../core/result.dart';
import '../../../core/theme/colors.dart';
import '../../../shared/widgets/hoppin_button.dart';
import '../data/receipts_repository.dart';
import 'widgets/receipt_row.dart';

/// Fetches the receipt for one ride. Keyed by ride id so a rider who somehow
/// lands on two different completed rides never sees a cached mix-up.
final rideReceiptProvider =
    FutureProvider.family<Receipt, String>((ref, rideId) {
  // An empty id only comes from a hand-typed URL; the request it would
  // send — /rides//receipt — is malformed. Fail here without the network.
  if (rideId.isEmpty) {
    throw const ApiException(
        'RIDE_NOT_FOUND', 'This ride could not be found.', 0);
  }
  final repo = ref.watch(receiptsRepositoryProvider);
  return repo.forRide(rideId).then((result) => switch (result) {
        Ok(:final value) => value,
        Err(:final error) => throw error,
      });
});

/// Ride Complete / receipt screen.
///
/// `GET /rides/:id/receipt` returns a total, an optional waiting charge and
/// a distance — there is no fare breakdown (Base/Distance/Time/Wait) and no
/// driver info on this endpoint, unlike the Figma pack. Decision recorded in
/// docs/SCREEN-DECISIONS.md: the rider does not need our accounting, so this
/// screen shows the final summary only.
class RideCompleteScreen extends ConsumerWidget {
  final String rideId;
  final VoidCallback? onDone;

  const RideCompleteScreen({super.key, required this.rideId, this.onDone});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(rideReceiptProvider(rideId));
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                error is ApiException
                    ? RiderErrorCopy.messageFor(error)
                    : 'Something went wrong loading your receipt.',
                style: const TextStyle(color: AppColors.negative),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          data: (receipt) => _RideCompleteBody(
            receipt: receipt,
            theme: theme,
            onDone: onDone,
          ),
        ),
      ),
    );
  }
}

class _RideCompleteBody extends StatelessWidget {
  final Receipt receipt;
  final ThemeData theme;
  final VoidCallback? onDone;

  const _RideCompleteBody({
    required this.receipt,
    required this.theme,
    this.onDone,
  });

  /// Null unless both timestamps parsed. Never guesses a duration from one
  /// side alone.
  Duration? get _duration {
    final pickup = receipt.pickupTime;
    final dropoff = receipt.dropoffTime;
    if (pickup == null || dropoff == null) return null;
    final diff = dropoff.difference(pickup);
    return diff.isNegative ? null : diff;
  }

  String get _durationLabel {
    final d = _duration;
    if (d == null) return '';
    return '${d.inMinutes} min';
  }

  /// "Not charged yet", never "£0.00" — a null total is not a free ride.
  String get _totalLabel =>
      receipt.totalPence?.format(currency: receipt.currency) ?? 'Not charged yet';

  @override
  Widget build(BuildContext context) {
    final duration = _duration;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Ride Completed',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineLarge?.copyWith(fontSize: 24),
        ),
        const SizedBox(height: 6),
        Text(
          'Thank you for riding with us!',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        _Card(
          theme: theme,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Journey Summary', style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: _SummaryStat(
                      icon: Icons.place_outlined,
                      label: 'Distance',
                      value: receipt.distanceMiles != null
                          ? '${receipt.distanceMiles!.toStringAsFixed(1)} mi'
                          : '—',
                      theme: theme,
                    ),
                  ),
                  if (duration != null)
                    Expanded(
                      child: _SummaryStat(
                        icon: Icons.access_time,
                        label: 'Duration',
                        value: _durationLabel,
                        theme: theme,
                      ),
                    ),
                  Expanded(
                    child: _SummaryStat(
                      icon: Icons.currency_pound,
                      label: 'Total Fare',
                      value: _totalLabel,
                      theme: theme,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _Card(
          theme: theme,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Total Fare', style: theme.textTheme.titleMedium),
              Text(_totalLabel,
                  style: theme.textTheme.headlineLarge?.copyWith(fontSize: 22)),
              const Divider(height: 24),
              if (receipt.hasWaitingCharge)
                ReceiptRow(
                  label: 'Wait Time',
                  value: receipt.waitingPence!.format(currency: receipt.currency),
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        HoppinButton(label: 'Done', onPressed: onDone ?? () {}),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  final ThemeData theme;
  final Widget child;

  const _Card({required this.theme, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }
}

class _SummaryStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final ThemeData theme;

  const _SummaryStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: theme.textTheme.bodyMedium?.color),
        const SizedBox(height: 4),
        Text(label, style: theme.textTheme.bodyMedium),
        Text(
          value,
          style: theme.textTheme.titleMedium,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
