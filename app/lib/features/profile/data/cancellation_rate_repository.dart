import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/result.dart';

/// The rider's own cancellation record.
///
/// Shown to them because it can cost them money: a rider over the operator's
/// line pays a higher cancellation fee, and being charged more for a number you
/// cannot see is indefensible.
class RiderCancellationRate {
  final int windowDays;
  final int ridesTotal;
  final int cancelled;

  /// Null when they have booked nothing in the window. A rider with no rides
  /// has no rate — 0% would claim a clean record they have not earned, and
  /// 100% would accuse them of the opposite.
  final double? ratePct;

  /// Whether the higher cancellation fee currently applies to them.
  final bool overThreshold;

  final double thresholdPct;
  final int minRides;
  final bool policyActive;

  const RiderCancellationRate({
    required this.windowDays,
    required this.ridesTotal,
    required this.cancelled,
    required this.ratePct,
    required this.overThreshold,
    required this.thresholdPct,
    required this.minRides,
    required this.policyActive,
  });

  /// Nothing worth showing until they have actually booked something.
  bool get hasRecord => ridesTotal > 0 && ratePct != null;

  /// How close they are to the line, for the bar. Clamped: a rider at 90%
  /// against a 60% line is fully over, not 150% of a bar.
  double get progress => thresholdPct <= 0
      ? 0
      : ((ratePct ?? 0) / thresholdPct).clamp(0.0, 1.0);

  static RiderCancellationRate fromJson(Map<String, dynamic> json) {
    final policy = switch (json['policy']) {
      Map m => m.cast<String, dynamic>(),
      _ => const <String, dynamic>{},
    };
    double? pct;
    if (json['rate_pct'] is num) pct = (json['rate_pct'] as num).toDouble();
    return RiderCancellationRate(
      windowDays: (json['window_days'] as num?)?.toInt() ?? 30,
      ridesTotal: (json['rides_total'] as num?)?.toInt() ?? 0,
      cancelled: (json['cancelled'] as num?)?.toInt() ?? 0,
      ratePct: pct,
      overThreshold: json['over_threshold'] == true,
      thresholdPct: (policy['threshold_pct'] as num?)?.toDouble() ?? 60,
      minRides: (policy['min_rides'] as num?)?.toInt() ?? 5,
      policyActive: policy['is_active'] == true,
    );
  }
}

class CancellationRateRepository {
  final ApiClient _api;
  const CancellationRateRepository(this._api);

  Future<Result<RiderCancellationRate>> mine() async {
    final res = await _api.get<Map<String, dynamic>>('/me/cancellation-rate');
    return switch (res) {
      Ok(:final value) => Ok(RiderCancellationRate.fromJson(value)),
      Err(:final error) => Err(error),
    };
  }
}

final cancellationRateRepositoryProvider = Provider<CancellationRateRepository>(
    (ref) => CancellationRateRepository(ref.watch(apiClientProvider)));

/// Degrades to null rather than an error: this sits on a screen the rider
/// opened for something else, and a failure here must not break it.
final myCancellationRateProvider =
    FutureProvider.autoDispose<RiderCancellationRate?>((ref) async {
  final result = await ref.watch(cancellationRateRepositoryProvider).mine();
  return switch (result) {
    Ok(:final value) => value,
    Err() => null,
  };
});
