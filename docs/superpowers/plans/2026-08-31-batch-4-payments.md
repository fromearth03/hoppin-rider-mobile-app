# Batch 4 — Payments data layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** The card-management and receipt data layers — everything the payment screens consume — built and tested against the real API shapes.

**Architecture:** Feature-first under `lib/features/payments/`. Repositories return `Result<T>` through the existing `ApiClient`.

**Tech Stack:** Flutter 3.44.4 · Dart 3.12.2 · flutter_riverpod 2.6.1 · mocktail 1.0.5

**Spec:** `docs/superpowers/specs/2026-08-30-rider-app-milestone1-design.md`
**Screen decisions:** `docs/SCREEN-DECISIONS.md` (payment section)

## Global Constraints

- **The backend is the source of truth.** No field the API does not return.
- **Money is never a `double`** — use `Pence` from `lib/core/money.dart`.
- **Server-owned copy is rendered verbatim.**
- **TDD throughout**, tests before implementation.
- Stage only the files each task creates. Never `git add -A`.

## Two API quirks that will catch you out

Both verified in `payments_handler.go:68-130` and `payments/moneyloop.go:100-107`.
Neither matches the rest of this API:

1. **`GET /me/payment-methods` returns a BARE ARRAY**, not `{"cards": [...]}`. Every
   other list endpoint wraps its rows in a named key. Parsing it the usual way yields
   nothing.
2. **The card DTO is camelCase** — `paymentMethodId`, `brand`, `last4`, `expMonth`,
   `expYear`, `isDefault` — alone in a snake_case API.

## The PCI boundary, which is not negotiable

The app **never** touches a card number. `POST /me/payment-methods/setup-intent`
returns a `clientSecret`; the Stripe SDK collects the card against it directly. A raw
PAN in a `TextField` we control would put the whole app in PCI SAQ A-EP; the SDK
element keeps it at SAQ A. The Figma draws raw card fields — those are not built.

This batch stops at the data layer. The SDK integration itself needs
`flutter_stripe` and native config, and belongs with the screen.

---

### Task 1: Payment methods

**Files:**
- Create: `app/lib/features/payments/data/payment_methods_repository.dart`
- Test: `app/test/features/payments/data/payment_methods_repository_test.dart`

**Interfaces:**
- Consumes: `ApiClient`, `apiClientProvider`, `Result`, `ApiException`.
- Produces: `SavedCard` (`paymentMethodId`, `brand`, `last4`, `expMonth`, `expYear`, `isDefault`, plus `isExpired` and `displayLabel`); `SetupIntent` (`clientSecret`); `PaymentMethodsRepository` with `startAddCard()`, `list()`, `setDefault(String pmId)`, `remove(String pmId)`; `paymentMethodsRepositoryProvider`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/api/api_client.dart';
import 'package:hoppin_rider/core/api/api_exception.dart';
import 'package:hoppin_rider/core/result.dart';
import 'package:hoppin_rider/features/payments/data/payment_methods_repository.dart';
import 'package:mocktail/mocktail.dart';

class _MockApi extends Mock implements ApiClient {}

void main() {
  late _MockApi api;
  late PaymentMethodsRepository repo;

  setUp(() {
    api = _MockApi();
    repo = PaymentMethodsRepository(api);
  });

  group('SavedCard.fromJson', () {
    test('reads the camelCase DTO', () {
      // This endpoint is camelCase alone in a snake_case API.
      final c = SavedCard.fromJson(const {
        'paymentMethodId': 'pm_123',
        'brand': 'visa',
        'last4': '4242',
        'expMonth': 12,
        'expYear': 2030,
        'isDefault': true,
      });

      expect(c.paymentMethodId, 'pm_123');
      expect(c.brand, 'visa');
      expect(c.last4, '4242');
      expect(c.expMonth, 12);
      expect(c.expYear, 2030);
      expect(c.isDefault, isTrue);
    });

    test('renders a label a rider recognises', () {
      final c = SavedCard.fromJson(const {
        'paymentMethodId': 'pm_1', 'brand': 'visa', 'last4': '4242',
        'expMonth': 1, 'expYear': 2030, 'isDefault': false,
      });

      expect(c.displayLabel, 'Visa ····4242');
    });

    test('a card expires at the END of its month', () {
      // A card marked 12/2026 is valid through 31 December 2026. Treating the
      // 1st as expiry would refuse a card that still works.
      final c = SavedCard.fromJson(const {
        'paymentMethodId': 'pm_1', 'brand': 'visa', 'last4': '4242',
        'expMonth': 12, 'expYear': 2026, 'isDefault': false,
      });

      expect(c.isExpiredAt(DateTime(2026, 12, 31)), isFalse);
      expect(c.isExpiredAt(DateTime(2027, 1, 1)), isTrue);
    });
  });

  group('list', () {
    test('parses a BARE ARRAY, not a wrapped object', () async {
      // Unlike every other list endpoint in this API.
      when(() => api.get<List<dynamic>>(any()))
          .thenAnswer((_) async => const Ok([
                {'paymentMethodId': 'pm_1', 'brand': 'visa', 'last4': '4242',
                 'expMonth': 12, 'expYear': 2030, 'isDefault': true},
                {'paymentMethodId': 'pm_2', 'brand': 'mastercard',
                 'last4': '5555', 'expMonth': 1, 'expYear': 2031,
                 'isDefault': false},
              ]));

      final cards = ((await repo.list()) as Ok<List<SavedCard>>).value;

      expect(cards, hasLength(2));
      expect(cards.first.isDefault, isTrue);
      expect(cards.last.brand, 'mastercard');
    });

    test('no cards is a success, not an error', () async {
      when(() => api.get<List<dynamic>>(any()))
          .thenAnswer((_) async => const Ok([]));

      final result = await repo.list();

      expect(result, isA<Ok<List<SavedCard>>>());
      expect((result as Ok<List<SavedCard>>).value, isEmpty);
    });

    test('skips a card with no payment method id', () async {
      // The id is what set-default and delete are called with, so a card
      // without one renders as a row whose buttons fail.
      when(() => api.get<List<dynamic>>(any()))
          .thenAnswer((_) async => const Ok([
                {'paymentMethodId': 'pm_1', 'brand': 'visa', 'last4': '4242',
                 'expMonth': 12, 'expYear': 2030, 'isDefault': true},
                {'brand': 'visa', 'last4': '9999', 'expMonth': 1,
                 'expYear': 2031, 'isDefault': false},
              ]));

      final cards = ((await repo.list()) as Ok<List<SavedCard>>).value;

      expect(cards, hasLength(1));
      expect(cards.single.last4, '4242');
    });
  });

  group('startAddCard', () {
    test('returns the client secret the Stripe SDK needs', () async {
      when(() => api.post<Map<String, dynamic>>(any()))
          .thenAnswer((_) async => const Ok({'clientSecret': 'seti_123_secret'}));

      final intent = ((await repo.startAddCard()) as Ok<SetupIntent>).value;

      expect(intent.clientSecret, 'seti_123_secret');
    });

    test('a response with no client secret is a failure, not an empty one',
        () async {
      // Handing the SDK an empty secret fails opaquely inside Stripe; failing
      // here names the problem.
      when(() => api.post<Map<String, dynamic>>(any()))
          .thenAnswer((_) async => const Ok({}));

      final result = await repo.startAddCard();

      expect((result as Err).error.code, 'INTERNAL');
    });
  });

  group('setDefault and remove', () {
    test('setDefault calls the right path', () async {
      when(() => api.post<Map<String, dynamic>>(any()))
          .thenAnswer((_) async => const Ok({'payment_method_id': 'pm_1',
                                             'default': true}));

      await repo.setDefault('pm_1');

      verify(() => api.post<Map<String, dynamic>>(
          '/me/payment-methods/pm_1/default')).called(1);
    });

    test('remove calls the right path', () async {
      when(() => api.delete<dynamic>(any()))
          .thenAnswer((_) async => const Ok(null));

      await repo.remove('pm_1');

      verify(() => api.delete<dynamic>('/me/payment-methods/pm_1')).called(1);
    });

    test('refuses a blank id before calling', () async {
      final result = await repo.remove('  ');

      expect((result as Err).error.code, 'VALIDATION_FAILED');
      verifyNever(() => api.delete<dynamic>(any()));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/payments/data/payment_methods_repository_test.dart`
Expected: FAIL — URI does not exist.

- [ ] **Step 3: Write the implementation**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/result.dart';

/// One saved card.
///
/// The app never sees a card number. Stripe returns only these censored
/// fields, and the SDK collects the PAN directly against a setup intent -- a
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

  /// A card is valid through the LAST day of its expiry month -- 12/2026 works
  /// until 31 December 2026. Treating the 1st as expiry would refuse a card
  /// that still works.
  bool isExpiredAt(DateTime now) {
    final firstOfNextMonth = expMonth == 12
        ? DateTime(expYear + 1, 1, 1)
        : DateTime(expYear, expMonth + 1, 1);
    return !now.isBefore(firstOfNextMonth);
  }

  bool get isExpired => isExpiredAt(DateTime.now());

  /// Null for a card with no id -- it cannot be made default or deleted, so
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

  factory SavedCard.fromJson(Map<String, dynamic> json) => tryFromJson(json)!;
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
  /// which collects the number itself -- it never reaches this app.
  Future<Result<SetupIntent>> startAddCard() async {
    final result = await _api
        .post<Map<String, dynamic>>('/me/payment-methods/setup-intent');

    return switch (result) {
      Ok(:final value) => switch (value['clientSecret']) {
          String s when s.isNotEmpty => Ok(SetupIntent(s)),
          // Handing the SDK an empty secret fails opaquely inside Stripe.
          _ => Err(ApiException('INTERNAL',
              'Could not start adding a card. Try again.', 0)),
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

  /// Makes a card the default. Booking always charges the default card --
  /// there is no per-ride payment selection anywhere in the API.
  Future<Result<void>> setDefault(String pmId) async {
    if (pmId.trim().isEmpty) {
      return Err(ApiException(
          'VALIDATION_FAILED', 'No card selected.', 0));
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
      return Err(ApiException(
          'VALIDATION_FAILED', 'No card selected.', 0));
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/payments/data/payment_methods_repository_test.dart`
Expected: PASS (11 tests)

- [ ] **Step 5: Run the full suite and commit**

```bash
flutter test
git add app/lib/features/payments/data/payment_methods_repository.dart app/test/features/payments/data/payment_methods_repository_test.dart
git commit -m "feat: payment methods repository

Two quirks unique in this API, both verified against the handler: the
list endpoint returns a bare array rather than a named key like every
other list, and the card DTO is camelCase alone in a snake_case API.

A card is expired only after the LAST day of its expiry month. Treating
the 1st as expiry would refuse a card that still works for another
month.

An empty client secret is a failure rather than an empty success --
handing the Stripe SDK an empty string fails opaquely inside Stripe,
where failing here names the problem."
```

---

### Task 2: Receipts and transactions

**Files:**
- Create: `app/lib/features/payments/data/receipts_repository.dart`
- Test: `app/test/features/payments/data/receipts_repository_test.dart`

**Interfaces:**
- Consumes: `ApiClient`, `Pence`, `Result`.
- Produces: `Receipt` (`rideId`, `rideCategory`, `farePence`, `waitingPence`, `totalPence`, `currency`, `status`, `distanceMiles`, `pickupTime`, `dropoffTime`, `providerPaymentId`, plus `hasWaitingCharge`); `ReceiptsRepository.forRide(String rideId)`; `receiptsRepositoryProvider`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/api/api_client.dart';
import 'package:hoppin_rider/core/money.dart';
import 'package:hoppin_rider/core/result.dart';
import 'package:hoppin_rider/features/payments/data/receipts_repository.dart';
import 'package:mocktail/mocktail.dart';

class _MockApi extends Mock implements ApiClient {}

void main() {
  late _MockApi api;
  late ReceiptsRepository repo;

  setUp(() {
    api = _MockApi();
    repo = ReceiptsRepository(api);
  });

  test('reads the receipt and keeps money as pence', () async {
    when(() => api.get<Map<String, dynamic>>(any()))
        .thenAnswer((_) async => const Ok({
              'ride_id': 'r1',
              'ride_category': 'standard',
              'fare_pence': 1238,
              'waiting_pence': 0,
              'total_pence': 1238,
              'currency': 'GBP',
              'status': 'captured',
              'distance_miles': 4.7,
              'pickup_time': '2026-08-31T09:00:00Z',
              'dropoff_time': '2026-08-31T09:20:00Z',
              'provider_payment_id': 'pi_123',
            }));

    final r = ((await repo.forRide('r1')) as Ok<Receipt>).value;

    expect(r.farePence, const Pence(1238));
    expect(r.totalPence, const Pence(1238));
    expect(r.distanceMiles, 4.7);
    expect(r.hasWaitingCharge, isFalse);
  });

  test('a waiting charge is shown only when it is non-zero', () async {
    // A zero waiting line tells the rider nothing and implies they were
    // nearly charged for waiting.
    when(() => api.get<Map<String, dynamic>>(any()))
        .thenAnswer((_) async => const Ok({
              'ride_id': 'r1', 'fare_pence': 1000, 'waiting_pence': 250,
              'total_pence': 1250, 'currency': 'GBP', 'status': 'captured',
            }));

    final r = ((await repo.forRide('r1')) as Ok<Receipt>).value;

    expect(r.hasWaitingCharge, isTrue);
    expect(r.waitingPence, const Pence(250));
  });

  test('an uncharged ride has a null total rather than zero', () async {
    // "Not charged yet" and "free" are different things and must not both
    // render as GBP 0.00.
    when(() => api.get<Map<String, dynamic>>(any()))
        .thenAnswer((_) async => const Ok({
              'ride_id': 'r1', 'fare_pence': null, 'waiting_pence': null,
              'total_pence': null, 'currency': 'GBP', 'status': 'pending',
            }));

    final r = ((await repo.forRide('r1')) as Ok<Receipt>).value;

    expect(r.totalPence, isNull);
    expect(r.farePence, isNull);
  });

  test('does not model platform commission', () async {
    // It was removed from the receipt deliberately: it let a rider back out
    // driver earnings. Modelling it would resurrect a field the backend
    // withdrew on purpose.
    when(() => api.get<Map<String, dynamic>>(any()))
        .thenAnswer((_) async => const Ok({
              'ride_id': 'r1', 'fare_pence': 1000, 'total_pence': 1000,
              'currency': 'GBP', 'status': 'captured',
              'platform_commission_pence': 200,
            }));

    final r = ((await repo.forRide('r1')) as Ok<Receipt>).value;

    expect(r.totalPence, const Pence(1000));
    // No accessor exists for commission; this test documents the intent.
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/payments/data/receipts_repository_test.dart`
Expected: FAIL — URI does not exist.

- [ ] **Step 3: Write the implementation**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/money.dart';
import '../../../core/result.dart';

/// What a rider was charged for one ride.
///
/// `platform_commission_pence` is deliberately NOT modelled. The backend
/// withdrew it because it let a rider back out driver earnings, and the
/// product owner's position is that the rider does not need our accounting --
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

  static DateTime? _time(Object? raw) =>
      raw is String ? DateTime.tryParse(raw)?.toUtc() : null;

  static String? _orNull(Object? v) {
    final s = v as String?;
    return (s == null || s.isEmpty) ? null : s;
  }

  factory Receipt.fromJson(Map<String, dynamic> json) => Receipt(
        rideId: (json['ride_id'] as String?) ?? '',
        rideCategory: _orNull(json['ride_category']),
        farePence: Pence.fromJson(json['fare_pence']),
        waitingPence: Pence.fromJson(json['waiting_pence']),
        totalPence: Pence.fromJson(json['total_pence']),
        currency: (json['currency'] as String?) ?? 'GBP',
        status: (json['status'] as String?) ?? '',
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/payments/data/receipts_repository_test.dart`
Expected: PASS (4 tests)

- [ ] **Step 5: Run the full suite and commit**

```bash
flutter test
git add app/lib/features/payments/data/receipts_repository.dart app/test/features/payments/data/receipts_repository_test.dart
git commit -m "feat: receipts repository

Money stays nullable. An uncharged ride has a null total rather than
zero, because 'not charged yet' and 'free' must not both render as
GBP 0.00.

Platform commission is deliberately not modelled. The backend withdrew
it because it let a rider back out driver earnings, and modelling it
would resurrect a field that was removed on purpose."
```

---

## What is NOT in this batch

**The Stripe SDK integration and the card screens.** `flutter_stripe` needs native
config on both platforms, and the card element belongs with the screen that shows it.
This batch builds what those screens call.

**Anything touching a card number.** There is no code path in this app that handles a
PAN, by design.

---

## Self-review

**Spec coverage.** §7.1 default-card selection and §8's Stripe section (Task 1); the
receipt half of §7.2 (Task 2).

**Placeholders:** none.

**Type consistency:** both repositories are self-contained; shared types are `ApiClient`,
`Result`, `ApiException` and `Pence`, all already on disk. `SavedCard.tryFromJson`
follows the skip-a-bad-row shape established in `vehicle_repository` and
`places_repository`.
