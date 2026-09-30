import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/colors.dart';
import '../../data/cancellation_rate_repository.dart';

/// The rider's cancellation record, on their own profile.
///
/// Here because it can cost them money: over the operator's line, their fares
/// carry a surcharge until the rate comes back down. A rider being charged more
/// for a number they cannot see has no way to understand the bill or to do
/// anything about it. Cancelling itself stays free before a trip starts.
///
/// Hidden entirely for a rider with no rides in the window. A brand-new rider
/// does not need a compliance meter on their profile before they have taken a
/// single trip.
class CancellationRateCard extends ConsumerWidget {
  const CancellationRateCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(myCancellationRateProvider).valueOrNull;
    if (stats == null || !stats.hasRecord) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final pct = stats.ratePct!;
    final over = stats.overThreshold;
    final tone = over ? AppColors.negative : AppColors.navy;

    return Container(
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: over
                ? AppColors.negative.withValues(alpha: 0.35)
                : AppColors.lightBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Your cancellations',
                    style: theme.textTheme.titleMedium?.copyWith(fontSize: 15)),
              ),
              Text('${pct.toStringAsFixed(pct % 1 == 0 ? 0 : 1)}%',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontSize: 20, color: tone)),
            ],
          ),
          const SizedBox(height: 4),
          // The counts, not just the percentage: 50% means something very
          // different at 2 rides and at 200, and the bare number invites a
          // rider to panic about a rate built from almost nothing.
          Text(
            '${stats.cancelled} of your last ${stats.ridesTotal} '
            '${stats.ridesTotal == 1 ? 'booking' : 'bookings'} '
            'in ${stats.windowDays} days',
            style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12.5),
          ),
          if (stats.policyActive) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: stats.progress,
                minHeight: 6,
                backgroundColor: AppColors.lightBorder,
                valueColor: AlwaysStoppedAnimation(tone),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              // Says what it costs AND how it recovers. "You are over the
              // limit" tells a rider off without telling them anything they
              // can act on.
              cancellationRateMessage(stats),
              style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 12.5,
                  color: over
                      ? AppColors.negative
                      : AppColors.lightTextSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

String _pct(double v) => v.toStringAsFixed(v % 1 == 0 ? 0 : 1);

/// The line under the bar. Always about FARES: cancelling before a trip
/// starts is free, and the only cost of a high rate is a fare surcharge.
@visibleForTesting
String cancellationRateMessage(RiderCancellationRate stats) {
  final line = _pct(stats.thresholdPct);
  final surcharge = _pct(stats.fareSurchargePct);
  if (stats.surchargeActive) {
    return 'Your fares include a +$surcharge% surcharge while you are above '
        '$line%. It comes off as you complete rides.';
  }
  if (stats.overThreshold) {
    return 'You are above $line%. It comes back down as you complete rides.';
  }
  if (stats.ridesTotal < stats.minRides) {
    return 'This starts counting once you have ${stats.minRides} bookings.';
  }
  return stats.fareSurchargePct > 0
      ? 'Above $line%, your fares carry a +$surcharge% surcharge.'
      : 'Try to keep this under $line%.';
}
