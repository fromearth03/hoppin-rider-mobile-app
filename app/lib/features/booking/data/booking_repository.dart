import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/geo.dart';
import '../../../core/result.dart';

// kMaxWaypoints now lives in core/geo.dart so the estimate path enforces the
// same cap -- quoting a six-stop fare and then refusing it at the book button
// would be worse than refusing the sixth stop as it is added.

/// The acknowledgement from `POST /api/v1/rides/request`.
///
/// The returned id IS the ride id: the server creates the ride at booking
/// (status matching), so it is immediately visible in history, cancellable,
/// and pollable — dispatch attaches a driver to it as one matches.
class BookingRequest {
  final String requestId;
  const BookingRequest(this.requestId);

  /// The booking-created ride's id (same value as [requestId]).
  String get rideId => requestId;

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
    // The estimate the rider confirmed, carried onto the booking-created
    // ride so estimate = quote = charge from the first moment.
    int estimatePence = 0,
    int estimateDistanceMeters = 0,
    int estimateDurationSeconds = 0,
    // The place names the rider picked — stored on the ride so history in
    // BOTH apps shows addresses instead of bare coordinates.
    String pickupLabel = '',
    String dropoffLabel = '',
  }) async {
    if (waypoints.length > kMaxWaypoints) {
      return const Err(ApiException(
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
        if (estimatePence > 0) 'estimate_pence': estimatePence,
        if (estimateDistanceMeters > 0)
          'estimate_distance_meters': estimateDistanceMeters,
        if (estimateDurationSeconds > 0)
          'estimate_duration_seconds': estimateDurationSeconds,
        if (pickupLabel.trim().isNotEmpty) 'pickup_label': pickupLabel.trim(),
        if (dropoffLabel.trim().isNotEmpty)
          'dropoff_label': dropoffLabel.trim(),
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
