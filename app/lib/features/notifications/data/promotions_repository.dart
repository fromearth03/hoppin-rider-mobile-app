import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/result.dart';
import '../domain/promotion_item.dart';

String? _orNull(Object? v) => switch (v) {
      String s when s.trim().isNotEmpty => s.trim(),
      _ => null,
    };

/// See the note in `notifications_repository.dart`: `List.cast` is lazy and
/// would throw out of a method that promises a `Result`.
Iterable<Map<String, dynamic>> _objects(Object? raw) =>
    (raw is List ? raw : const []).whereType<Map<String, dynamic>>();

/// `expires_at` arrives as `expires_at::text` from Postgres
/// (`2026-09-02 00:00:00+00`), which `DateTime.tryParse` rejects on the space
/// and the two-digit offset. Normalised here rather than asking the backend to
/// change a column cast half the platform reads.
DateTime? _parseTimestamp(String? raw) {
  if (raw == null) return null;
  var s = raw.replaceFirst(' ', 'T');
  // A bare +00 / -05 offset needs its minutes to be ISO 8601.
  final offset = RegExp(r'([+-])(\d{2})$');
  s = s.replaceFirstMapped(offset, (m) => '${m[1]}${m[2]}:00');
  return DateTime.tryParse(s);
}

/// GET /promotions returns `{"promotions":[...]}` with each row shaped by the
/// Go `PromoOffer`: `{promo_code, title, description, discount_type,
/// discount_value, max_discount_cap, min_ride_amount, new_users_only,
/// expires_at, availed, state}`.
///
/// `state` is server-owned (availed > expired > active) precisely so the
/// client never guesses which tab/pill a promo belongs in.
class PromotionsRepository {
  final ApiClient _api;
  const PromotionsRepository(this._api);

  Future<Result<List<PromotionItem>>> list() async {
    final result = await _api.get<dynamic>('/promotions');
    return switch (result) {
      Ok(:final value) => Ok(_objects(
              value is List ? value : (value is Map ? value['promotions'] : null))
          .map(_tryItem)
          .whereType<PromotionItem>()
          .toList(growable: false)),
      Err(:final error) => Err(error),
    };
  }

  /// Null when the row carries no promo code: there is nothing to redeem, so
  /// the card would be decoration the rider cannot use.
  static PromotionItem? _tryItem(Map<String, dynamic> json) {
    final code = _orNull(json['promo_code']);
    if (code == null) return null;

    final expiresAt = _parseTimestamp(_orNull(json['expires_at']));

    return PromotionItem(
      id: code,
      // COALESCE(title,'') means the server can legitimately send a blank
      // title. The code is the one thing that is always there and it is what
      // the rider types at checkout, so it beats an unlabelled card.
      title: _orNull(json['title']) ?? code,
      description: _orNull(json['description']) ?? '',
      status: _status(json, expiresAt),
      validUntil: expiresAt,
    );
  }

  /// Server first. Only when `state` is absent or a word this build has never
  /// seen does the client fall back - and even then it prefers `availed`,
  /// because showing an "Active" pill on an offer the rider has already spent
  /// is the one wrong answer they would act on.
  static PromotionStatus _status(Map<String, dynamic> json, DateTime? expiry) {
    final availed = json['availed'] == true;
    return switch (_orNull(json['state'])) {
      'active' => PromotionStatus.active,
      'availed' => PromotionStatus.availed,
      'expired' => PromotionStatus.expired,
      _ when availed => PromotionStatus.availed,
      _ when expiry != null && expiry.isBefore(DateTime.now()) =>
        PromotionStatus.expired,
      _ => PromotionStatus.active,
    };
  }
}

final promotionsRepositoryProvider = Provider<PromotionsRepository>(
    (ref) => PromotionsRepository(ref.watch(apiClientProvider)));
