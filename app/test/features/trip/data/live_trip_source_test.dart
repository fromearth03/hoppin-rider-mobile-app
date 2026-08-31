import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/features/trip/data/live_trip_source.dart';

void main() {
  group('TripDriver.tryFromJson', () {
    test('parses a full driver row', () {
      final driver = TripDriver.tryFromJson({
        'name': 'George',
        'rating': 4.3,
        'rating_count': 113,
        'trips_completed': 1130,
        'plate': 'RV 20 OZT',
        'vehicle_type': 'White Prius',
        'seats': 4,
        'bags': 2,
      });

      expect(driver, isNotNull);
      expect(driver!.name, 'George');
      expect(driver.rating, 4.3);
      expect(driver.ratingCount, 113);
      expect(driver.tripsCompleted, 1130);
      expect(driver.plate, 'RV 20 OZT');
      expect(driver.vehicleType, 'White Prius');
      expect(driver.seats, 4);
      expect(driver.bags, 2);
    });

    test('never fabricates a rating: a new driver with no rating stays null',
        () {
      final driver = TripDriver.tryFromJson({
        'name': 'New Driver',
        'rating': null,
        'rating_count': 0,
        'trips_completed': 0,
        'plate': 'AB 12 CDE',
        'vehicle_type': 'Blue Civic',
        'seats': 4,
        'bags': 2,
      });

      expect(driver, isNotNull);
      expect(driver!.rating, isNull);
      expect(driver.hasRating, isFalse);
    });

    test('a row with no usable name returns null rather than a blank driver',
        () {
      final driver = TripDriver.tryFromJson({
        'name': '',
        'plate': 'AB 12 CDE',
      });
      expect(driver, isNull);
    });
  });

  group('TripStep.tryFromJson', () {
    test('parses maneuver and instruction', () {
      final step = TripStep.tryFromJson({
        'maneuver': 'turn-left',
        'instruction': 'Take left after 1.5 mi',
      });
      expect(step, isNotNull);
      expect(step!.maneuver, 'turn-left');
      expect(step.instruction, 'Take left after 1.5 mi');
    });

    test('a step with no instruction returns null', () {
      final step = TripStep.tryFromJson({'maneuver': 'turn-left'});
      expect(step, isNull);
    });
  });

  group('LiveTripInfo.fromJson', () {
    test('driver is null while matching -- a normal state, not an error', () {
      final info = LiveTripInfo.fromJson({
        'id': 'ride-1',
        'status': 'matching',
        'driver': null,
      });

      expect(info.status, LiveTripStatus.matching);
      expect(info.driver, isNull);
    });

    test('geo.steps null outside driving states is treated as "no data", not empty',
        () {
      final info = LiveTripInfo.fromJson({
        'id': 'ride-1',
        'status': 'matching',
        'steps': null,
      });
      expect(info.steps, isNull);
    });

    test('geo.steps as an empty list means "no turns remain" and is kept distinct from null',
        () {
      final info = LiveTripInfo.fromJson({
        'id': 'ride-1',
        'status': 'started',
        'steps': <Object?>[],
      });
      expect(info.steps, isNotNull);
      expect(info.steps, isEmpty);
    });

    test('parses fare breakdown and cancellation policy', () {
      final info = LiveTripInfo.fromJson({
        'id': 'ride-1',
        'status': 'arriving',
        'base_fare_pence': 500,
        'surge_multiplier': 1.5,
        'surge_pence': 386,
        'total_pence': 886,
        'currency': 'GBP',
        'cancellation_policy': 'Free within 2 minutes of assignment.',
      });

      expect(info.baseFarePence?.value, 500);
      expect(info.surgeMultiplier, 1.5);
      expect(info.surgePence?.value, 386);
      expect(info.totalPence?.value, 886);
      expect(info.cancellationPolicy, 'Free within 2 minutes of assignment.');
    });

    test('unknown status strings degrade to matching rather than throwing',
        () {
      final info = LiveTripInfo.fromJson({
        'id': 'ride-1',
        'status': 'some-future-state',
      });
      expect(info.status, LiveTripStatus.matching);
    });
  });

  group('LiveTripSource', () {
    test(
        'is an explicit placeholder: no GET /rides/:id repository exists yet, '
        'so it returns an honest awaiting-match state by default', () async {
      const source = LiveTripSource();
      final result = await source.watch('ride-1').first;

      expect(result.status, LiveTripStatus.matching);
      expect(result.driver, isNull);
    });
  });
}
