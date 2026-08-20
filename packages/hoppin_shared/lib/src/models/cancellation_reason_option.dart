/// A seeded cancellation reason from `GET /cancellation-reasons`. The `id` is
/// the real DB uuid that `PATCH /rides/:id/cancel` validates `reason_id`
/// against — the app must send one of these, never a fabricated placeholder.
class CancellationReasonOption {
  const CancellationReasonOption({
    required this.id,
    required this.reasonText,
    required this.appliesPenaltyFee,
    required this.actorType,
    this.event,
    this.freeCancelSeconds,
    this.freeCancelMeters,
    this.penaltyFeeAmount,
  });

  final String id;
  final String reasonText;
  final bool appliesPenaltyFee;

  /// "rider" or "driver" — who this reason is offered to.
  final String actorType;

  /// Server-side charging event. `rider_mid_trip` is the only event used for
  /// a rider cancellation after the driver has started the trip.
  final String? event;

  /// Configured grace thresholds returned for the confirmation disclosure.
  final int? freeCancelSeconds;
  final int? freeCancelMeters;
  final double? penaltyFeeAmount;

  factory CancellationReasonOption.fromJson(Map<String, dynamic> json) =>
      CancellationReasonOption(
        id: json['id'] as String,
        reasonText: (json['reason_text'] as String?) ?? '',
        appliesPenaltyFee: (json['applies_penalty_fee'] as bool?) ?? false,
        actorType: (json['actor_type'] as String?) ?? 'rider',
        event: json['event'] as String?,
        freeCancelSeconds: (json['free_cancel_seconds'] as num?)?.toInt(),
        freeCancelMeters: (json['free_cancel_meters'] as num?)?.toInt(),
        penaltyFeeAmount: (json['penalty_fee_amount'] as num?)?.toDouble(),
      );
}
