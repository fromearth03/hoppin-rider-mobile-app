import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../payments/data/receipts_repository.dart';
import '../../../payments/presentation/widgets/receipt_row.dart';

/// The body of [RideDetailsScreen] once its [Receipt] has loaded.
///
/// Mirrors the journey-summary / fare-card layout already used on Ride
/// Complete and Trip Details, and the same money rules: [Pence.format] for
/// every amount, a null total read as "Not charged yet" rather than
/// "£0.00", and a waiting row shown only when the charge is non-zero.
class RideDetailsSummaryCard extends StatelessWidget {
  final Receipt receipt;

  const RideDetailsSummaryCard({super.key, required this.receipt});

  /// Both timestamps are independently nullable. Only render a duration when
  /// both are actually present.
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

  /// "Not charged yet", never "£0.00" — a null total means the ride has not
  /// been charged, not that it was free.
  String get _totalLabel => receipt.totalPence == null
      ? 'Not charged yet'
      : receipt.totalPence!.format(currency: receipt.currency);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final duration = _duration;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
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
                        value:
                            duration == null ? '—' : _formatDuration(duration),
                      ),
                    ),
                    Expanded(
                      child: _SummaryStat(
                        icon: Icons.currency_pound,
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
                Text('Fare Estimate', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(_totalLabel,
                    style: theme.textTheme.headlineLarge?.copyWith(fontSize: 24)),
                const Divider(height: 28),
                if (receipt.hasWaitingCharge)
                  ReceiptRow(
                    label: 'Wait Time',
                    value:
                        receipt.waitingPence!.format(currency: receipt.currency),
                  ),
              ],
            ),
          ),
        ),
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
