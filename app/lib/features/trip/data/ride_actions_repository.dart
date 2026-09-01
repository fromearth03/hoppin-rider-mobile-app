import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/result.dart';

/// Rider-initiated actions on a live ride. Today: cancellation.
///
/// Contract read from `ride_handler.go` (~1065–1135): `PATCH
/// /rides/:id/cancel` with `canceled_by_user_id` (the Supabase subject) and
/// `actor_type: "rider"` — the ownership check compares both, so sending
/// anything else 403s. `reason_id` is optional and not sent until the app
/// grows a reason picker (`GET /cancellation-reasons` serves the rows).
class RideActionsRepository {
  final ApiClient _api;
  final String? Function() _userId;

  const RideActionsRepository(this._api, this._userId);

  Future<Result<void>> cancelRide(String rideId) async {
    final userId = _userId();
    if (rideId.isEmpty || userId == null) {
      // No ride or no session: the request could only fail, and the copy
      // must not blame the rider for a state the app got itself into.
      return const Err(ApiException(
          'VALIDATION_FAILED', 'This ride could not be cancelled.', 0));
    }
    final result = await _api.patch<Map<String, dynamic>>(
      '/rides/$rideId/cancel',
      body: {'canceled_by_user_id': userId, 'actor_type': 'rider'},
    );
    return switch (result) {
      Ok() => const Ok(null),
      Err(:final error) => Err(error),
    };
  }

  /// `POST /rides/:id/rating` with `{score, comments}` (rateRideBody in
  /// driver_handler.go) — the reviewer is the bearer token's subject, so no
  /// user id travels in the body. One rating per reviewer per ride; posting
  /// again edits it in place. Server rejects with VALIDATION_FAILED (score
  /// out of 1–5), ILLEGAL_TRANSITION (ride not completed, 409) or
  /// RIDE_NOT_FOUND.
  Future<Result<void>> rateRide(String rideId, int score,
      {String comments = ''}) async {
    if (rideId.isEmpty || score < 1 || score > 5) {
      return const Err(ApiException(
          'VALIDATION_FAILED', 'rating must be between 1 and 5', 0));
    }
    final result = await _api.post<Map<String, dynamic>>(
      '/rides/$rideId/rating',
      body: {'score': score, 'comments': comments},
    );
    return switch (result) {
      Ok() => const Ok(null),
      Err(:final error) => Err(error),
    };
  }
}

final rideActionsRepositoryProvider = Provider<RideActionsRepository>(
  (ref) => RideActionsRepository(
    ref.watch(apiClientProvider),
    () => Supabase.instance.client.auth.currentUser?.id,
  ),
);
