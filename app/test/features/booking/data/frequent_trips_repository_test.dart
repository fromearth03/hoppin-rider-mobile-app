import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/features/booking/data/frequent_trips_repository.dart';

void main() {
  Map<String, dynamic> row({
    Object? pickupLabel = 'Home',
    Object? dropoffLabel = 'Office',
  }) =>
      {
        'pickup_lat': 52.5851,
        'pickup_lng': -2.1281,
        'dropoff_lat': 52.5912,
        'dropoff_lng': -2.1104,
        'pickup_label': pickupLabel,
        'dropoff_label': dropoffLabel,
        'trip_count': 7,
        'last_taken_at': '2026-09-01T08:12:00Z',
        'vehicle_category_id': 'cat-1',
      };

  test('parses a repeated journey', () {
    final trip = FrequentTrip.tryFromJson(row())!;

    expect(trip.tripCount, 7);
    expect(trip.fromLabel, 'Home');
    expect(trip.toLabel, 'Office');
    expect(trip.vehicleCategoryId, 'cat-1');
    expect(trip.lastTakenAt, isNotNull);
  });

  test('falls back to coordinates for a trip booked before labels existed', () {
    // Rides taken before pickup_label/dropoff_label were written have no
    // address at all. Showing a blank row would be worse than showing where
    // the trip actually goes.
    final trip =
        FrequentTrip.tryFromJson(row(pickupLabel: null, dropoffLabel: '  '))!;

    expect(trip.fromLabel, '52.5851, -2.1281');
    expect(trip.toLabel, '52.5912, -2.1104');
  });

  test('drops a row with no usable coordinates', () {
    final broken = row()..['dropoff_lat'] = null;

    expect(FrequentTrip.tryFromJson(broken), isNull);
  });
}
