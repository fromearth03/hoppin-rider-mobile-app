@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/api/api_client.dart';
import 'package:hoppin_rider/core/result.dart';
import 'package:hoppin_rider/core/theme/app_theme.dart';
import 'package:hoppin_rider/features/booking/data/vehicle_repository.dart';
import 'package:hoppin_rider/features/history/presentation/ride_history_screen.dart';
import 'package:hoppin_rider/features/history/presentation/trip_details_screen.dart';
import 'package:hoppin_rider/features/scheduling/presentation/schedule_ride_screen.dart';
import 'package:mocktail/mocktail.dart';

class _MockApi extends Mock implements ApiClient {}

class _MockVehicleRepository extends Mock implements VehicleRepository {}

const _standard = VehicleCategory(
  id: 'a',
  name: 'Standard',
  seats: 4,
  bags: 2,
  priceMultiplier: 1.0,
);
const _estate = VehicleCategory(
  id: 'b',
  name: 'Estate',
  seats: 5,
  bags: 4,
  priceMultiplier: 1.3,
);
const _mpv = VehicleCategory(
  id: 'c',
  name: 'MPV',
  seats: 7,
  bags: 5,
  priceMultiplier: 1.5,
);
const _minibus = VehicleCategory(
  id: 'd',
  name: 'Minibus',
  seats: 8,
  bags: 6,
  priceMultiplier: 2.0,
);

/// Renders Ride History, Trip Details and Schedule Ride so they can be put
/// side by side with `docs/figma/extracted/`. See `auth_render_test.dart`
/// for why these are renders, not assertions.
void main() {
  Future<void> shoot(
    WidgetTester tester,
    Widget screen,
    String name, {
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
      home: screen,
    ));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('shots/$name.png'),
    );
  }

  // Ride history's goldens live in ride_history_render_test.dart, which
  // overrides the trip-history repository so the shots capture real list
  // states rather than a loading spinner.

  testWidgets('trip details light', (t) async {
    const rideId = 'r1';
    final api = _MockApi();
    when(() => api.get<Map<String, dynamic>>(any())).thenAnswer((_) async => const Ok({
          'ride_id': rideId,
          'ride_category': 'standard',
          'fare_pence': 1000,
          'waiting_pence': 0,
          'total_pence': 1238,
          'currency': 'GBP',
          'status': 'captured',
          'distance_miles': 4.7,
          'pickup_time': '2026-02-16T11:50:00Z',
          'dropoff_time': '2026-02-16T12:03:00Z',
        }));

    await shoot(
      t,
      ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(api)],
        child: const TripDetailsScreen(rideId: rideId),
      ),
      'trip_details_light',
    );
  });

  testWidgets('schedule ride light', (t) async {
    final repo = _MockVehicleRepository();
    when(() => repo.list()).thenAnswer(
        (_) async => const Ok([_standard, _estate, _mpv, _minibus]));

    await shoot(
      t,
      ProviderScope(
        overrides: [vehicleRepositoryProvider.overrideWithValue(repo)],
        child: const ScheduleRideScreen(),
      ),
      'schedule_ride_light',
    );
  });
}
