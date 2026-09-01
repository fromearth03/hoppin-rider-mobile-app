import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/api/api_client.dart';
import 'package:hoppin_rider/core/api/api_exception.dart';
import 'package:hoppin_rider/core/result.dart';
import 'package:hoppin_rider/features/notifications/data/promotions_repository.dart';
import 'package:hoppin_rider/features/notifications/domain/promotion_item.dart';
import 'package:mocktail/mocktail.dart';

class _MockApi extends Mock implements ApiClient {}

/// Shape below is the live contract, read from the Go source
/// (`lookups_handler.go` ListPromotions + `app_catalog_repo.go` PromoOffer):
/// {"promotions":[{promo_code,title,description,discount_type,discount_value,
/// max_discount_cap,min_ride_amount,new_users_only,expires_at,availed,state}]}
/// `state` is server-owned: availed > expired > active.
void main() {
  late _MockApi api;
  late PromotionsRepository repo;

  setUp(() {
    api = _MockApi();
    repo = PromotionsRepository(api);
  });

  Map<String, dynamic> row({
    String promoCode = 'FIRST10',
    String title = 'First Ride Discount',
    String state = 'active',
    bool availed = false,
    Object? expiresAt = '2026-09-02T00:00:00Z',
  }) =>
      {
        'promo_code': promoCode,
        'title': title,
        'description': "Get 10% off on your first ride with Hoppin'",
        'discount_type': 'percentage',
        'discount_value': 10.0,
        'max_discount_cap': null,
        'min_ride_amount': null,
        'new_users_only': false,
        'expires_at': expiresAt,
        'availed': availed,
        'state': state,
      };

  group('list', () {
    test('reads the wrapped shape the handler returns', () async {
      when(() => api.get<dynamic>(any()))
          .thenAnswer((_) async => Ok<dynamic>({
                'promotions': [row()],
              }));

      final items = ((await repo.list()) as Ok<List<PromotionItem>>).value;

      expect(items, hasLength(1));
      expect(items.first.id, 'FIRST10');
      expect(items.first.title, 'First Ride Discount');
      expect(items.first.status, PromotionStatus.active);
      expect(items.first.validUntil, DateTime.utc(2026, 9, 2));
    });

    test('the server-owned state drives the pill, never a client guess',
        () async {
      when(() => api.get<dynamic>(any()))
          .thenAnswer((_) async => Ok<dynamic>({
                'promotions': [
                  row(promoCode: 'A', state: 'active'),
                  row(promoCode: 'B', state: 'availed', availed: true),
                  row(promoCode: 'C', state: 'expired'),
                ],
              }));

      final items = ((await repo.list()) as Ok<List<PromotionItem>>).value;

      expect(items.map((p) => p.status), [
        PromotionStatus.active,
        PromotionStatus.availed,
        PromotionStatus.expired,
      ]);
    });

    test('an unknown state falls back to availed when the row says availed',
        () async {
      // A vocabulary the client has not seen must not silently read as
      // "Active" on a promo this rider has already spent.
      when(() => api.get<dynamic>(any()))
          .thenAnswer((_) async => Ok<dynamic>({
                'promotions': [row(state: 'something_new', availed: true)],
              }));

      final items = ((await repo.list()) as Ok<List<PromotionItem>>).value;

      expect(items.single.status, PromotionStatus.availed);
    });

    test('a missing state is derived from expiry, not assumed active',
        () async {
      when(() => api.get<dynamic>(any()))
          .thenAnswer((_) async => const Ok<dynamic>({
                'promotions': [
                  {
                    'promo_code': 'OLD',
                    'title': 'Old offer',
                    'description': 'd',
                    'expires_at': '2020-01-01T00:00:00Z',
                  },
                ],
              }));

      final items = ((await repo.list()) as Ok<List<PromotionItem>>).value;

      expect(items.single.status, PromotionStatus.expired);
    });

    test('a promo with no expiry keeps a null date rather than inventing one',
        () async {
      // The frame always draws a Valid Until line, but a fabricated date on an
      // open-ended offer is worse than no line at all.
      when(() => api.get<dynamic>(any()))
          .thenAnswer((_) async => Ok<dynamic>({
                'promotions': [row(expiresAt: null)],
              }));

      final item = ((await repo.list()) as Ok<List<PromotionItem>>).value.single;

      expect(item.validUntil, isNull);
      expect(item.status, PromotionStatus.active);
    });

    test('the Postgres text timestamp shape parses', () async {
      // expires_at::text from Postgres, not RFC3339.
      when(() => api.get<dynamic>(any()))
          .thenAnswer((_) async => Ok<dynamic>({
                'promotions': [row(expiresAt: '2026-09-02 00:00:00+00')],
              }));

      final item = ((await repo.list()) as Ok<List<PromotionItem>>).value.single;

      expect(item.validUntil?.year, 2026);
      expect(item.validUntil?.month, 9);
      expect(item.validUntil?.day, 2);
    });

    test('an unparseable expiry keeps the row with no date', () async {
      when(() => api.get<dynamic>(any()))
          .thenAnswer((_) async => Ok<dynamic>({
                'promotions': [row(expiresAt: 'whenever')],
              }));

      final item = ((await repo.list()) as Ok<List<PromotionItem>>).value.single;

      expect(item.validUntil, isNull);
    });

    test('a non-object row does not take down the list', () async {
      when(() => api.get<dynamic>(any()))
          .thenAnswer((_) async => Ok<dynamic>({
                'promotions': [
                  row(promoCode: 'A'),
                  null,
                  'not an object',
                  row(promoCode: 'B'),
                ],
              }));

      final items = ((await repo.list()) as Ok<List<PromotionItem>>).value;

      expect(items.map((p) => p.id), ['A', 'B']);
    });

    test('a row with no promo code is dropped: nothing to redeem', () async {
      when(() => api.get<dynamic>(any()))
          .thenAnswer((_) async => Ok<dynamic>({
                'promotions': [
                  {'title': 'Ghost offer', 'description': 'd'},
                  row(promoCode: 'REAL'),
                ],
              }));

      final items = ((await repo.list()) as Ok<List<PromotionItem>>).value;

      expect(items.map((p) => p.id), ['REAL']);
    });

    test('an untitled promo falls back to its code rather than a blank card',
        () async {
      // COALESCE(title,'') means the server can legitimately send an empty
      // title; a card with no heading is not renderable.
      when(() => api.get<dynamic>(any()))
          .thenAnswer((_) async => Ok<dynamic>({
                'promotions': [row(promoCode: 'SAVE20', title: '')],
              }));

      final item = ((await repo.list()) as Ok<List<PromotionItem>>).value.single;

      expect(item.title, 'SAVE20');
    });

    test('a bare array is accepted too', () async {
      when(() => api.get<dynamic>(any()))
          .thenAnswer((_) async => Ok<dynamic>([row()]));

      expect(((await repo.list()) as Ok<List<PromotionItem>>).value, hasLength(1));
    });

    test('no offers is an empty list, not an error', () async {
      when(() => api.get<dynamic>(any()))
          .thenAnswer((_) async => const Ok<dynamic>({'promotions': []}));

      expect(((await repo.list()) as Ok<List<PromotionItem>>).value, isEmpty);
    });

    test('calls the rider-facing route', () async {
      when(() => api.get<dynamic>(any()))
          .thenAnswer((_) async => const Ok<dynamic>({'promotions': []}));

      await repo.list();

      verify(() => api.get<dynamic>('/promotions')).called(1);
    });

    test('surfaces the server failure verbatim', () async {
      when(() => api.get<dynamic>(any())).thenAnswer((_) async =>
          const Err<dynamic>(ApiException('INTERNAL', 'internal server error', 500)));

      final result = await repo.list();

      expect((result as Err).error.message, 'internal server error');
    });
  });
}
