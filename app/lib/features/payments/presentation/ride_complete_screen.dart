import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/error_codes.dart';
import '../../../core/result.dart';
import '../../../core/theme/colors.dart';
import '../../../shared/nav/app_router.dart';
import '../../../shared/widgets/bottom_scroll_fade.dart';
import '../../../shared/widgets/hoppin_button.dart';
import '../../../shared/widgets/profile_avatar.dart';
import '../../trip/data/live_trip_source.dart';
import '../../trip/data/ride_actions_repository.dart';
import '../../trip/data/ride_context_repository.dart';
import '../data/receipts_repository.dart';
import 'widgets/receipt_row.dart';
import 'widgets/route_preview.dart';

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

/// The ride detail (`GET /rides/:id`) that enriches this screen: the route
/// polyline for the preview and the driver block for the Your Driver card.
///
/// Enrichment only — a failure degrades to the awaiting shape (no route, no
/// driver) rather than taking the receipt down with it.
final rideCompleteContextProvider =
    FutureProvider.family<LiveTripInfo, String>((ref, rideId) async {
  final result = await ref.watch(rideContextRepositoryProvider).fetch(rideId);
  return switch (result) {
    Ok(:final value) => value,
    Err() => LiveTripInfo.awaiting(rideId),
  };
});

/// Ride Complete / receipt screen, to the frame: route preview, Journey
/// Summary chips, the fare card, Your Driver, and the 1–5 star prompt.
///
/// `GET /rides/:id/receipt` returns a total, an optional waiting charge and
/// a distance — there is no fare breakdown (Base/Distance/Time/Wait), so the
/// fare card renders the real fields only (fare, waiting when non-zero,
/// total). Decision recorded in docs/SCREEN-DECISIONS.md.
class RideCompleteScreen extends ConsumerWidget {
  final String rideId;
  final VoidCallback? onDone;

  const RideCompleteScreen({super.key, required this.rideId, this.onDone});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(rideReceiptProvider(rideId));
    final detail = ref.watch(rideCompleteContextProvider(rideId));
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
            rideId: rideId,
            receipt: receipt,
            detail: detail.valueOrNull,
            theme: theme,
            onDone: onDone ?? () => context.go(AppRoutes.home),
          ),
        ),
      ),
    );
  }
}

class _RideCompleteBody extends StatelessWidget {
  final String rideId;
  final Receipt receipt;
  final LiveTripInfo? detail;
  final ThemeData theme;
  final VoidCallback onDone;

  const _RideCompleteBody({
    required this.rideId,
    required this.receipt,
    required this.detail,
    required this.theme,
    required this.onDone,
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
      receipt.totalPence?.format(currency: receipt.currency) ??
      'Not charged yet';

  @override
  Widget build(BuildContext context) {
    final duration = _duration;
    final route = detail?.route;
    final driver = detail?.driver;

    return BottomScrollFade(
      child: ListView(
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
          const SizedBox(height: 20),
          if (route != null && route.length >= 2) ...[
            RoutePreview(points: route),
            const SizedBox(height: 16),
          ],
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
                    style:
                        theme.textTheme.headlineLarge?.copyWith(fontSize: 22)),
                const Divider(height: 24),
                if (receipt.farePence != null)
                  ReceiptRow(
                    label: 'Fare',
                    value:
                        receipt.farePence!.format(currency: receipt.currency),
                  ),
                if (receipt.hasWaitingCharge)
                  ReceiptRow(
                    label: 'Wait Time',
                    value: receipt.waitingPence!
                        .format(currency: receipt.currency),
                  ),
              ],
            ),
          ),
          if (driver != null) ...[
            const SizedBox(height: 16),
            _Card(
              theme: theme,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Your Driver', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      // Fetched WITH the bearer token — a plain NetworkImage
                      // (an <img> on web) cannot send it and 401s silently.
                      ProfileAvatar(
                        avatarUrl: driver.avatarUrl,
                        name: driver.name,
                        radius: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(driver.name,
                                style: theme.textTheme.titleMedium),
                            if (driver.vehicleType != null)
                              Text(driver.vehicleType!,
                                  style: theme.textTheme.bodyMedium),
                          ],
                        ),
                      ),
                      if (driver.hasRating) ...[
                        const Icon(Icons.star_rounded,
                            size: 20, color: AppColors.warning),
                        const SizedBox(width: 4),
                        Text(driver.rating!.toStringAsFixed(1),
                            style: theme.textTheme.titleMedium),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          _RatingCard(rideId: rideId, theme: theme),
          const SizedBox(height: 24),
          HoppinButton(label: 'Done', onPressed: onDone),
        ],
      ),
    );
  }
}

/// "How was your ride?" — the 1–5 star prompt wired to
/// `POST /rides/:id/rating`. One rating per reviewer per ride, editable in
/// place: tapping another star simply posts the new score.
class _RatingCard extends ConsumerStatefulWidget {
  final String rideId;
  final ThemeData theme;

  const _RatingCard({required this.rideId, required this.theme});

  @override
  ConsumerState<_RatingCard> createState() => _RatingCardState();
}

class _RatingCardState extends ConsumerState<_RatingCard> {
  int _score = 0;
  bool _busy = false;

  Future<void> _rate(int score) async {
    if (_busy) return;
    final previous = _score;
    setState(() {
      _score = score;
      _busy = true;
    });

    final result =
        await ref.read(rideActionsRepositoryProvider).rateRide(
              widget.rideId,
              score,
            );
    if (!mounted) return;
    setState(() => _busy = false);

    switch (result) {
      case Ok():
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Thanks for your feedback!')),
        );
      case Err(:final error):
        // The tapped stars must not claim a rating the server refused.
        setState(() => _score = previous);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(RiderErrorCopy.messageFor(error))),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Card(
      theme: widget.theme,
      child: Column(
        children: [
          Text('How was your ride?', style: widget.theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 1; i <= 5; i++)
                IconButton(
                  key: ValueKey('rate-star-$i'),
                  onPressed: () => _rate(i),
                  icon: Icon(
                    i <= _score ? Icons.star_rounded : Icons.star_outline_rounded,
                    size: 32,
                    color: i <= _score
                        ? AppColors.warning
                        : AppColors.lightTextDisabled,
                  ),
                ),
            ],
          ),
        ],
      ),
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
