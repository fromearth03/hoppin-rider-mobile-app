import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/result.dart';
import 'fare_repository.dart' show LatLng;

/// The server caps intermediate stops at five.
const kMaxWaypoints = 5;

/// The acknowledgement from `POST /api/v1/rides/request`.
///
/// Booking is fire-and-forget: a 202 means dispatch has the request, not that
/// a driver exists. The trip screen watches for the match.
class BookingRequest {
  final String requestId;
  const BookingRequest(this.requestId);

  factory BookingRequest.fromJson(Map<String, dynamic> json) =>
      BookingRequest((json['request_id'] as String?) ?? '');
}

class BookingRepository {
  final ApiClient _api;
  const BookingRepository(this._api);

  /// Requests a ride.
  ///
  /// The server prices every leg at this moment, while it still holds the
  /// rider's token, so the estimate, the driver's offer and the final charge
  /// all agree. Sending stops in a different order than they were quoted
  /// would change the fare.
  Future<Result<BookingRequest>> request({
    required LatLng pickup,
    required LatLng dropoff,
    required String vehicleCategoryId,
    List<LatLng> waypoints = const [],
  }) async {
    if (waypoints.length > kMaxWaypoints) {
      return Err(ApiException(
        'VALIDATION_FAILED',
        'A trip can have at most $kMaxWaypoints stops.',
        0,
      ));
    }

    final result = await _api.post<Map<String, dynamic>>(
      '/rides/request',
      body: {
        'pickup_lat': pickup.lat,
        'pickup_lng': pickup.lng,
        'dropoff_lat': dropoff.lat,
        'dropoff_lng': dropoff.lng,
        'vehicle_category_id': vehicleCategoryId,
        if (waypoints.isNotEmpty)
          'waypoints': waypoints.map((w) => w.toJson()).toList(),
      },
    );

    return switch (result) {
      Ok(:final value) => Ok(BookingRequest.fromJson(value)),
      Err(:final error) => Err(error),
    };
  }
}

final bookingRepositoryProvider = Provider<BookingRepository>(
    (ref) => BookingRepository(ref.watch(apiClientProvider)));
