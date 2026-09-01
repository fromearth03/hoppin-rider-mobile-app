import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/result.dart';

/// One rider-facing cancellation reason from `GET /cancellation-reasons`.
///
/// The reason is a LABEL server-side: which fee actually applies is derived
/// from ride state + actor, so the fee fields here are shown as honest
/// context ("a fee may apply"), never as the app's own fee calculation.
class RiderCancelReason {
  final String id;
  final String label;
  final bool appliesFee;
  final double? feeAmount;
  final int? freeCancelSeconds;

  /// Whose pocket the fee hits — 'rider' or 'driver'. "Driver didn't show
  /// up" carries a fee, but it is the DRIVER's penalty: the picker must not
  /// show the rider an amount they will never pay.
  final String feeChargedTo;

  const RiderCancelReason({
    required this.id,
    required this.label,
    required this.appliesFee,
    this.feeAmount,
    this.freeCancelSeconds,
    this.feeChargedTo = 'rider',
  });

  /// Whether the fee, if any, is the rider's own to pay.
  bool get riderPays => feeChargedTo != 'driver';

  static RiderCancelReason? tryFromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String || id.isEmpty) return null;
    return RiderCancelReason(
      id: id,
      label: (json['reason_text'] as String?) ?? '',
      appliesFee: json['applies_penalty_fee'] == true,
      feeAmount: (json['penalty_fee_amount'] as num?)?.toDouble(),
      freeCancelSeconds: (json['free_cancel_seconds'] as num?)?.toInt(),
      // Older servers omit the field; assuming the picking actor pays keeps
      // the previous (cautious) behaviour there.
      feeChargedTo: (json['fee_charged_to'] as String?) ?? 'rider',
    );
  }
}

/// Rider-initiated actions on a live ride: cancellation, with its reasons.
///
/// Contract read from `ride_handler.go` (~1065–1135): `PATCH
/// /rides/:id/cancel` with `canceled_by_user_id` (the Supabase subject) and
/// `actor_type: "rider"` — the ownership check compares both, so sending
/// anything else 403s. `reason_id` is optional: a missing reason never
/// blocks the cancel (the ride must always be escapable).
class RideActionsRepository {
  final ApiClient _api;
  final String? Function() _userId;

  const RideActionsRepository(this._api, this._userId);

  /// The active rider reasons for the cancel sheet's picker.
  Future<Result<List<RiderCancelReason>>> cancellationReasons() async {
    final result = await _api
        .get<Map<String, dynamic>>('/cancellation-reasons', query: {
      'actor': 'rider',
    });
    return switch (result) {
      Ok(:final value) => Ok(
          ((value['cancellation_reasons'] as List?) ?? const [])
              .whereType<Map>()
              .map((row) => RiderCancelReason.tryFromJson(
                  Map<String, dynamic>.from(row)))
              .whereType<RiderCancelReason>()
              .toList(growable: false)),
      Err(:final error) => Err(error),
    };
  }

  Future<Result<void>> cancelRide(String rideId, {String? reasonId}) async {
    final userId = _userId();
    if (rideId.isEmpty || userId == null) {
      // No ride or no session: the request could only fail, and the copy
      // must not blame the rider for a state the app got itself into.
      return const Err(ApiException(
          'VALIDATION_FAILED', 'This ride could not be cancelled.', 0));
    }
    final result = await _api.patch<Map<String, dynamic>>(
      '/rides/$rideId/cancel',
      body: {
        'canceled_by_user_id': userId,
        'actor_type': 'rider',
        if (reasonId != null && reasonId.isNotEmpty) 'reason_id': reasonId,
      },
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
