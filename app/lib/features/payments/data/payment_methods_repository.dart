import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/result.dart';

/// One saved card.
///
/// The app never sees a card number. Stripe returns only these censored
/// fields, and the SDK collects the PAN directly against a setup intent - a
/// raw number in a widget we control would put the whole app in PCI SAQ A-EP
/// rather than SAQ A.
///
/// Note the camelCase keys: this endpoint is alone in a snake_case API.
class SavedCard {
  final String paymentMethodId;
  final String brand;
  final String last4;
  final int expMonth;
  final int expYear;
  final bool isDefault;

  const SavedCard({
    required this.paymentMethodId,
    required this.brand,
    required this.last4,
    required this.expMonth,
    required this.expYear,
    required this.isDefault,
  });

  /// "Visa ····4242". Brand casing from Stripe is lowercase.
  String get displayLabel {
    final b = brand.isEmpty
        ? 'Card'
        : brand[0].toUpperCase() + brand.substring(1);
    return '$b ····$last4';
  }

  /// A card is valid through the LAST day of its expiry month - 12/2026 works
  /// until 31 December 2026. Treating the 1st as expiry would refuse a card
  /// that still works.
  bool isExpiredAt(DateTime now) {
    final firstOfNextMonth = expMonth == 12
        ? DateTime(expYear + 1, 1, 1)
        : DateTime(expYear, expMonth + 1, 1);
    return !now.isBefore(firstOfNextMonth);
  }

  bool get isExpired => isExpiredAt(DateTime.now());

  /// Null for a card with no id - it cannot be made default or deleted, so
  /// rendering it would produce a row whose buttons fail.
  static SavedCard? tryFromJson(Map<String, dynamic> json) {
    final id = json['paymentMethodId'] as String?;
    if (id == null || id.isEmpty) return null;

    return SavedCard(
      paymentMethodId: id,
      brand: (json['brand'] as String?) ?? '',
      last4: (json['last4'] as String?) ?? '',
      expMonth: (json['expMonth'] as num?)?.toInt() ?? 0,
      expYear: (json['expYear'] as num?)?.toInt() ?? 0,
      isDefault: json['isDefault'] == true,
    );
  }

  factory SavedCard.fromJson(Map<String, dynamic> json) =>
      tryFromJson(json)!;
}

/// The handle the Stripe SDK needs to collect a card.
class SetupIntent {
  final String clientSecret;
  const SetupIntent(this.clientSecret);
}

class PaymentMethodsRepository {
  final ApiClient _api;
  const PaymentMethodsRepository(this._api);

  /// Begins adding a card. The returned secret is handed to the Stripe SDK,
  /// which collects the number itself - it never reaches this app.
  Future<Result<SetupIntent>> startAddCard() async {
    final result = await _api
        .post<Map<String, dynamic>>('/me/payment-methods/setup-intent');

    return switch (result) {
      Ok(:final value) => switch (value['clientSecret']) {
          String s when s.isNotEmpty => Ok(SetupIntent(s)),
          // Handing the SDK an empty secret fails opaquely inside Stripe.
          _ => const Err(ApiException(
              'INTERNAL', 'Could not start adding a card. Try again.', 0)),
        },
      Err(:final error) => Err(error),
    };
  }

  /// The rider's saved cards.
  ///
  /// This endpoint returns a BARE ARRAY, unlike every other list in this API.
  Future<Result<List<SavedCard>>> list() async {
    final result = await _api.get<List<dynamic>>('/me/payment-methods');

    return switch (result) {
      Ok(:final value) => Ok(value
          .cast<Map<String, dynamic>>()
          .map(SavedCard.tryFromJson)
          .whereType<SavedCard>()
          .toList(growable: false)),
      Err(:final error) => Err(error),
    };
  }

  /// Makes a card the default. Booking always charges the default card -
  /// there is no per-ride payment selection anywhere in the API.
  Future<Result<void>> setDefault(String pmId) async {
    if (pmId.trim().isEmpty) {
      return const Err(
          ApiException('VALIDATION_FAILED', 'No card selected.', 0));
    }

    final result = await _api
        .post<Map<String, dynamic>>('/me/payment-methods/$pmId/default');

    return switch (result) {
      Ok() => const Ok(null),
      Err(:final error) => Err(error),
    };
  }

  Future<Result<void>> remove(String pmId) async {
    if (pmId.trim().isEmpty) {
      return const Err(
          ApiException('VALIDATION_FAILED', 'No card selected.', 0));
    }

    final result = await _api.delete<dynamic>('/me/payment-methods/$pmId');

    return switch (result) {
      Ok() => const Ok(null),
      Err(:final error) => Err(error),
    };
  }
}

final paymentMethodsRepositoryProvider = Provider<PaymentMethodsRepository>(
    (ref) => PaymentMethodsRepository(ref.watch(apiClientProvider)));
