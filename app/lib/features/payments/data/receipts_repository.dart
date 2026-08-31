import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/money.dart';
import '../../../core/result.dart';

/// What a rider was charged for one ride.
///
/// `platform_commission_pence` is deliberately NOT modelled. The backend
/// withdrew it because it let a rider back out driver earnings, and the
/// product owner's position is that the rider does not need our accounting -
/// the total, any waiting charge, the distance and the duration are enough.
class Receipt {
  final String rideId;
  final String? rideCategory;

  /// Null until the ride is actually charged. "Not charged yet" and "free"
  /// are different things and must not both render as 0.00.
  final Pence? farePence;
  final Pence? waitingPence;
  final Pence? totalPence;

  final String currency;
  final String status;
  final double? distanceMiles;
  final DateTime? pickupTime;
  final DateTime? dropoffTime;

  /// Stripe's payment intent, for a support query about a charge.
  final String? providerPaymentId;

  const Receipt({
    required this.rideId,
    required this.rideCategory,
    required this.farePence,
    required this.waitingPence,
    required this.totalPence,
    required this.currency,
    required this.status,
    required this.distanceMiles,
    required this.pickupTime,
    required this.dropoffTime,
    required this.providerPaymentId,
  });

  /// A zero waiting line tells the rider nothing and implies they came close
  /// to being charged for waiting.
  bool get hasWaitingCharge => (waitingPence?.value ?? 0) > 0;

  /// Never throws: an unexpected type (e.g. a stray number) parses as null
  /// rather than taking the whole receipt down with it.
  static DateTime? _time(Object? raw) => switch (raw) {
        String s when s.isNotEmpty => DateTime.tryParse(s)?.toUtc(),
        _ => null,
      };

  /// Empty-to-null for a string field. A pattern match rather than `as
  /// String?`, because the latter throws on a non-string value instead of
  /// treating it as absent.
  static String? _orNull(Object? v) => switch (v) {
        String s when s.isNotEmpty => s,
        _ => null,
      };

  factory Receipt.fromJson(Map<String, dynamic> json) => Receipt(
        rideId: _orNull(json['ride_id']) ?? '',
        rideCategory: _orNull(json['ride_category']),
        farePence: Pence.fromJson(json['fare_pence']),
        waitingPence: Pence.fromJson(json['waiting_pence']),
        totalPence: Pence.fromJson(json['total_pence']),
        currency: _orNull(json['currency']) ?? 'GBP',
        status: _orNull(json['status']) ?? '',
        distanceMiles: (json['distance_miles'] as num?)?.toDouble(),
        pickupTime: _time(json['pickup_time']),
        dropoffTime: _time(json['dropoff_time']),
        providerPaymentId: _orNull(json['provider_payment_id']),
      );
}

class ReceiptsRepository {
  final ApiClient _api;
  const ReceiptsRepository(this._api);

  Future<Result<Receipt>> forRide(String rideId) async {
    final result =
        await _api.get<Map<String, dynamic>>('/rides/$rideId/receipt');
    return switch (result) {
      Ok(:final value) => Ok(Receipt.fromJson(value)),
      Err(:final error) => Err(error),
    };
  }
}

final receiptsRepositoryProvider = Provider<ReceiptsRepository>(
    (ref) => ReceiptsRepository(ref.watch(apiClientProvider)));
