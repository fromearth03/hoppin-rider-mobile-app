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
