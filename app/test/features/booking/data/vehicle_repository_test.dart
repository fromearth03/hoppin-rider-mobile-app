import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/api/api_client.dart';
import 'package:hoppin_rider/core/api/api_exception.dart';
import 'package:hoppin_rider/core/result.dart';
import 'package:hoppin_rider/features/booking/data/vehicle_repository.dart';
import 'package:mocktail/mocktail.dart';

class _MockApi extends Mock implements ApiClient {}

void main() {
  late _MockApi api;
  late VehicleRepository repo;

  setUp(() {
    api = _MockApi();
    repo = VehicleRepository(api);
  });

  group('VehicleCategory.fromJson', () {
    test('reads exactly the five fields the API sends', () {
      final v = VehicleCategory.fromJson(const {
        'id': 'abc-123',
        'name': 'Standard',
        'seats': 4,
        'bags': 2,
        'price_multiplier': 1.0,
      });

      expect(v.id, 'abc-123');
      expect(v.name, 'Standard');
      expect(v.seats, 4);
      expect(v.bags, 2);
      expect(v.priceMultiplier, 1.0);
    });

    test('a multiplier sent as an int still reads as a double', () {
      // JSON has one number type; 1 and 1.0 both arrive for a x1 category.
      final v = VehicleCategory.fromJson(const {
        'id': 'a', 'name': 'Standard', 'seats': 4, 'bags': 2,
        'price_multiplier': 1,
      });
      expect(v.priceMultiplier, 1.0);
    });

    test('zero seats or bags means the row is not rendered, not "0 Seats"', () {
      // The API COALESCEs both to 0 when a category has neither configured.
      final v = VehicleCategory.fromJson(const {
        'id': 'a', 'name': 'Odd', 'seats': 0, 'bags': 0,
        'price_multiplier': 1.0,
      });
      expect(v.hasCapacity, isFalse);
    });
  });

  group('list', () {
    test('preserves the order the API returned', () async {
      // The API orders by price_multiplier then name â€” cheapest first. The
      // client must not re-sort; doing so would reorder the picker.
      when(() => api.get<Map<String, dynamic>>(any()))
          .thenAnswer((_) async => const Ok({
                'vehicle_types': [
                  {'id': 'c', 'name': 'MiniCar', 'seats': 4, 'bags': 2,
                   'price_multiplier': 0.9},
                  {'id': 'a', 'name': 'Standard', 'seats': 4, 'bags': 2,
                   'price_multiplier': 1.0},
                  {'id': 'b', 'name': 'Estate', 'seats': 5, 'bags': 4,
                   'price_multiplier': 1.3},
                ],
              }));

      final result = await repo.list();

      final names =
          (result as Ok<List<VehicleCategory>>).value.map((v) => v.name);
      expect(names, ['MiniCar', 'Standard', 'Estate']);
    });

    test('skips a row with no id rather than losing the whole list',
        () async {
      // The id is sent to /rides/estimate and /rides/request, so a category
      // without one cannot be booked - it would render as a tappable card
      // that fails at the last step. One bad row from the admin panel should
      // cost that category, not the entire picker.
      when(() => api.get<Map<String, dynamic>>(any()))
          .thenAnswer((_) async => const Ok({
                'vehicle_types': [
                  {'id': 'a', 'name': 'Standard', 'seats': 4, 'bags': 2,
                   'price_multiplier': 1.0},
                  {'name': 'Broken', 'seats': 4, 'bags': 2,
                   'price_multiplier': 1.0},
                  {'id': '', 'name': 'AlsoBroken', 'seats': 4, 'bags': 2,
                   'price_multiplier': 1.0},
                  {'id': 'b', 'name': 'Estate', 'seats': 5, 'bags': 4,
                   'price_multiplier': 1.3},
                ],
              }));

      final result = await repo.list();
      final names =
          (result as Ok<List<VehicleCategory>>).value.map((v) => v.name);

      expect(names, ['Standard', 'Estate']);
    });

    test('an empty catalogue is a success, not an error', () async {
      when(() => api.get<Map<String, dynamic>>(any()))
          .thenAnswer((_) async => const Ok({'vehicle_types': []}));

      final result = await repo.list();

      expect(result, isA<Ok<List<VehicleCategory>>>());
      expect((result as Ok<List<VehicleCategory>>).value, isEmpty);
    });

    test('passes the error through untouched', () async {
      when(() => api.get<Map<String, dynamic>>(any())).thenAnswer(
          (_) async => Err(ApiException('INTERNAL', 'boom', 500)));

      final result = await repo.list();

      expect((result as Err).error.code, 'INTERNAL');
    });
  });
}
