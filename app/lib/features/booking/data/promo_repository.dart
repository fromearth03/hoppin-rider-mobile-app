import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/result.dart';

/// A promo code applied to a ride, and what it took off.
///
/// The server computes the discount from the ride's quoted fare and records the
/// redemption; the app never calculates a discount itself. `newFare` is what the
/// rider will actually be charged, so it is the only figure worth showing beside
/// the original.
class AppliedPromo {
  final String code;
  final String discountType; // 'flat_amount' | 'percentage'
  final double originalFare;
  final double discountAmount;
  final double newFare;

  const AppliedPromo({
    required this.code,
    required this.discountType,
    required this.originalFare,
    required this.discountAmount,
    required this.newFare,
  });

  /// Null when the response carries no code or no discount. A promo that took
  /// nothing off is not worth showing as applied — it would tell the rider they
  /// had saved money they have not.
  static AppliedPromo? tryFromJson(Map<String, dynamic> json) {
    final code = (json['promo_code'] as String?)?.trim();
    if (code == null || code.isEmpty) return null;

    final discount = _num(json['discount_amount']);
    if (discount <= 0) return null;

    return AppliedPromo(
      code: code,
      discountType: (json['discount_type'] as String?) ?? '',
      originalFare: _num(json['original_fare']),
      discountAmount: discount,
      newFare: _num(json['new_fare']),
    );
  }

  static double _num(Object? v) => switch (v) {
        final num n => n.toDouble(),
        final String s => double.tryParse(s) ?? 0,
        _ => 0,
      };
}

/// Promo codes on a ride.
///
/// Codes have always been creatable in the admin panel and redeemable by these
/// endpoints; the rider app listed promotions but had no way to enter one, so
/// nothing created there could actually be used.
///
/// Two steps, because they answer different questions:
///
///   * [validate] is the pre-ride check — does this code exist, is it live, has
///     this rider already used it. It runs before a ride exists, so it cannot
///     see the fare or the pickup zone.
///   * [applyToRide] is the real one. It needs a ride, checks the fare-dependent
///     rules (minimum spend, zone) and records the redemption.
///
/// A code can therefore pass [validate] and still be refused by [applyToRide].
/// That is expected, not a bug — the two know different things.
class PromoRepository {
  final ApiClient _api;
  PromoRepository(this._api);

  /// Pre-ride check. Ok(null) means the code is usable so far.
  Future<Result<void>> validate(String code) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) {
      return const Err(ApiException(
          'VALIDATION_FAILED', 'Enter a promo code first.', 0));
    }
    final result = await _api.get<dynamic>(
        '/promotions/validate?code=${Uri.encodeQueryComponent(trimmed)}');
    return switch (result) {
      Ok() => const Ok(null),
      Err(:final error) => Err(error),
    };
  }

  /// Applies the code to a created ride and returns what it took off.
  Future<Result<AppliedPromo>> applyToRide(String rideId, String code) async {
    final result = await _api.post<Map<String, dynamic>>(
      '/rides/$rideId/promo',
      body: {'promo_code': code.trim().toUpperCase()},
    );
    return switch (result) {
      // A success carrying no usable discount is a failure. Telling the rider a
      // code worked when the fare did not move is worse than saying it did not.
      Ok(:final value) => switch (AppliedPromo.tryFromJson(value)) {
          final AppliedPromo p => Ok(p),
          null => const Err(ApiException('PROMO_INELIGIBLE',
              'That code did not change this fare.', 0)),
        },
      Err(:final error) => Err(error),
    };
  }

  /// Reads back whatever promo is on the ride, so the discount survives a
  /// screen rebuild instead of living only in the response to applying it.
  Future<Result<AppliedPromo?>> forRide(String rideId) async {
    final result = await _api.get<dynamic>('/rides/$rideId/promo');
    return switch (result) {
      Ok(:final value) => Ok(value is Map<String, dynamic>
          ? AppliedPromo.tryFromJson(value)
          : null),
      Err(:final error) => Err(error),
    };
  }

  /// Removes a mistyped code from a ride.
  Future<Result<void>> removeFromRide(String rideId) async {
    final result = await _api.delete<dynamic>('/rides/$rideId/promo');
    return switch (result) {
      Ok() => const Ok(null),
      Err(:final error) => Err(error),
    };
  }
}

final promoRepositoryProvider = Provider<PromoRepository>(
    (ref) => PromoRepository(ref.watch(apiClientProvider)));
