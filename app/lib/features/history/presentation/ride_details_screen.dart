import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/error_codes.dart';
import '../../../core/theme/colors.dart';
import '../../payments/data/receipts_repository.dart';
import '../../payments/presentation/ride_complete_screen.dart' show rideReceiptProvider;
import 'widgets/ride_details_summary_card.dart';

/// `Ride Details.png`.
///
/// The design draws one assigned driver (name, rating with count, trips
/// completed, plate, vehicle type, capacity), a Base + Surge fare breakdown,
/// the rider's default card and a cancellation policy, all under a route
/// header. SCREEN-DECISIONS.md records `GET /rides/:id` as the endpoint that
/// would serve all of that in one call — but no repository method for
/// `/rides/:id` exists anywhere in this app; only `ReceiptsRepository`
/// (`GET /rides/:id/receipt`) is wired, and it carries none of those fields:
/// no driver, no fare component split, no payment card, no cancellation
/// policy, no route/polyline.
///
/// This screen therefore consumes the same [Receipt] as Ride Complete and
/// Trip Details, and shows only what that endpoint actually returns — total
/// fare, waiting charge (hidden when zero), distance and duration — exactly
/// the same reasoning already recorded for those two screens. The driver
/// block, fare breakdown, payment card and cancellation policy are omitted
/// rather than fabricated.
class RideDetailsScreen extends ConsumerWidget {
  final String rideId;

  const RideDetailsScreen({super.key, required this.rideId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(rideReceiptProvider(rideId));

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('Ride Details'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                error is ApiException
                    ? RiderErrorCopy.messageFor(error)
                    : 'Could not load this ride.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.negative),
              ),
            ),
          ),
          data: (receipt) => RideDetailsSummaryCard(receipt: receipt),
        ),
      ),
    );
  }
}
