import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/api/api_client.dart';
import 'package:hoppin_rider/core/api/api_exception.dart';
import 'package:hoppin_rider/core/result.dart';
import 'package:hoppin_rider/features/trip/data/live_trip_source.dart';
import 'package:hoppin_rider/features/trip/data/ride_context_repository.dart';
import 'package:mocktail/mocktail.dart';

class _MockApi extends Mock implements ApiClient {}

/// A captured-shape payload per `rider_ride_detail.go`.
Map<String, dynamic> _detail({Object? driver}) => {
      'id': 'ride-7',
      'status': 'accepted',
      'ref': 'R-1042',
      'geo': {
        'pickup': {'lat': 53.0, 'lng': -2.1, 'label': 'Hanley'},
        'dropoff': {'lat': 53.1, 'lng': -2.2, 'label': 'Keele'},
        'waypoints': [
          {'lat': 53.05, 'lng': -2.15, 'label': null},
        ],
        'route': [
          {'lat': 53.0, 'lng': -2.1},
          {'lat': 53.1, 'lng': -2.2},
        ],
        'steps': [
          {'instruction': 'Turn left onto Waterloo Road', 'maneuver': 'turn-left'},
        ],
      },
      'driver': driver,
      'fare': {
        'estimate_pence': 850,
        'total_pence': null,
        'currency': 'GBP',
        'discount_pence': 0,
      },
      'timestamps': {'accepted_at': '2026-09-01T10:00:00Z'},
      'chat_unread': 2,
    };

const _george = {
  'id': 'd-1',
  'full_name': 'George Oliver',
  'avatar_url': null,
  'rating': 4.3,
  'rating_count': 1130,
  'trips_count': 1130,
  'vehicle': {
    'make': 'Toyota',
    'model': 'Prius',
    'colour': 'White',
    'plate': 'RV 20 OZT',
    'seats': 4,
    'bags': 2,
  },
  'eta_seconds': 300,
};

void main() {
  test('maps the real ride detail: driver, vehicle, route, fare', () {
    final info =
        RideContextRepository.fromRideDetail(_detail(driver: _george));

    expect(info.rideId, 'ride-7');
    expect(info.status, LiveTripStatus.accepted);
    expect(info.driver, isNotNull);
    expect(info.driver!.name, 'George Oliver');
    expect(info.driver!.rating, 4.3);
    expect(info.driver!.ratingCount, 1130);
    expect(info.driver!.tripsCompleted, 1130);
    expect(info.driver!.plate, 'RV 20 OZT');
    expect(info.driver!.vehicleType, 'White Toyota Prius');
    expect(info.driver!.seats, 4);
    expect(info.driver!.bags, 2);
    expect(info.totalPence?.value, 850);
    expect(info.waypoints.map((w) => w.label),
        ['Hanley', 'Stop 1', 'Keele']);
    expect(info.route, hasLength(2));
    expect(info.steps!.single.instruction, 'Turn left onto Waterloo Road');
    expect(info.destinationLabel, 'Keele');
  });

  test('a null driver is the matching state, never a fabricated one', () {
    final info = RideContextRepository.fromRideDetail(_detail(driver: null));

    expect(info.driver, isNull);
    expect(info.status, LiveTripStatus.accepted);
  });

  test('an unknown status degrades to matching', () {
    final json = _detail(driver: null)..['status'] = 'assigned';
    expect(RideContextRepository.fromRideDetail(json).status,
        LiveTripStatus.matching);
  });

  test('fetch calls the contract path and maps errors through', () async {
    final api = _MockApi();
    when(() => api.get<Map<String, dynamic>>('/rides/ride-7'))
        .thenAnswer((_) async => Ok(_detail(driver: _george)));

    final repo = RideContextRepository(api);
    final result = await repo.fetch('ride-7');

    expect((result as Ok<LiveTripInfo>).value.driver!.name, 'George Oliver');

    when(() => api.get<Map<String, dynamic>>('/rides/gone'))
        .thenAnswer((_) async =>
            const Err(ApiException('RIDE_NOT_FOUND', 'ride not found', 404)));
    expect((await repo.fetch('gone')) is Err, isTrue);
  });

  test('an empty ride id renders awaiting without the network', () async {
    final api = _MockApi();
    final result = await RideContextRepository(api).fetch('');

    expect((result as Ok<LiveTripInfo>).value.status, LiveTripStatus.matching);
    verifyZeroInteractions(api);
  });
}
