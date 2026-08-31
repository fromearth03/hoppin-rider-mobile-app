@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/api/api_client.dart';
import 'package:hoppin_rider/core/money.dart';
import 'package:hoppin_rider/core/result.dart';
import 'package:hoppin_rider/core/theme/app_theme.dart';
import 'package:hoppin_rider/features/auth/application/auth_controller.dart';
import 'package:hoppin_rider/features/auth/data/profile_repository.dart';
import 'package:hoppin_rider/features/auth/domain/auth_state.dart';
import 'package:hoppin_rider/features/booking/data/vehicle_repository.dart';
import 'package:hoppin_rider/features/history/presentation/ride_history_screen.dart';
import 'package:hoppin_rider/features/history/presentation/trip_details_screen.dart';
import 'package:hoppin_rider/features/payments/data/receipts_repository.dart';
import 'package:hoppin_rider/features/payments/presentation/ride_complete_screen.dart';
import 'package:hoppin_rider/features/scheduling/presentation/schedule_ride_screen.dart';
import 'package:hoppin_rider/shared/nav/app_drawer.dart';
import 'package:mocktail/mocktail.dart';

class _MockAuthController extends Mock implements AuthController {}

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

/// Narrow-width (320px) renders of the screens under audit.
///
/// The card-number defect that slipped past a prior "matches the design"
/// pass only showed up when an unconstrained sibling crushed a flexible one
/// — a class of bug that a single 430px render can hide if there happens to
/// be just enough width. Rendering the same screens at 320px is a cheap way
/// to surface that failure mode. See `auth_render_test.dart` for why these
/// are renders, not assertions.
void main() {
  late _MockAuthController authController;

  const profile = RiderProfile(
    fullName: 'Taimoor',
    phoneNumber: '+44 123 567 8910',
    email: 'taimoor@example.com',
    avatarUrl: null,
    dateOfBirth: '1995-04-12',
    rating: 4.31,
    ratingCount: 150,
  );

  setUp(() {
    authController = _MockAuthController();
    when(() => authController.state).thenReturn(
        const AuthSnapshot(status: AuthStatus.signedIn, profile: profile));
    when(() => authController.addListener(any(),
            fireImmediately: any(named: 'fireImmediately')))
        .thenAnswer((invocation) {
      final listener = invocation.positionalArguments[0]
          as void Function(AuthSnapshot);
      final fire =
          invocation.namedArguments[#fireImmediately] as bool? ?? true;
      if (fire) listener(authController.state);
      return () {};
    });
  });

  Future<void> shoot(
    WidgetTester tester,
    Widget screen,
    String name,
  ) async {
    tester.view.physicalSize = const Size(320, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: screen,
    ));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('shots/$name.png'),
    );
  }

  testWidgets('drawer narrow', (t) async {
    final key = GlobalKey<ScaffoldState>();
    await shoot(
      t,
      ProviderScope(
        overrides: [authControllerProvider.overrideWith((_) => authController)],
        child: Scaffold(
          key: key,
          drawer: const AppDrawer(),
          body: Builder(builder: (context) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              Scaffold.of(context).openDrawer();
            });
            return const SizedBox.shrink();
          }),
        ),
      ),
      'drawer_narrow',
    );
  });

  testWidgets('ride history narrow', (t) async {
    await shoot(t, const RideHistoryScreen(), 'ride_history_narrow');
  });

  testWidgets('trip details narrow', (t) async {
    const rideId = 'r1';
    final api = _MockApi();
    when(() => api.get<Map<String, dynamic>>(any())).thenAnswer((_) async => const Ok({
          'ride_id': rideId,
          'ride_category': 'standard',
          'fare_pence': 1000,
          'waiting_pence': 250,
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
      'trip_details_narrow',
    );
  });

  testWidgets('ride complete narrow', (t) async {
    const rideId = 'r1';
    final receipt = Receipt(
      rideId: rideId,
      rideCategory: 'standard',
      farePence: const Pence(1405),
      waitingPence: const Pence(305),
      totalPence: const Pence(500),
      currency: 'GBP',
      status: 'captured',
      distanceMiles: 4.7,
      pickupTime: DateTime.utc(2026, 8, 31, 9, 0),
      dropoffTime: DateTime.utc(2026, 8, 31, 9, 13),
      providerPaymentId: 'pi_123',
    );

    await shoot(
      t,
      ProviderScope(
        overrides: [
          rideReceiptProvider(rideId)
              .overrideWith((ref) => Future.value(receipt)),
        ],
        child: const RideCompleteScreen(rideId: rideId),
      ),
      'ride_complete_narrow',
    );
  });

  testWidgets('schedule ride narrow', (t) async {
    final repo = _MockVehicleRepository();
    when(() => repo.list()).thenAnswer(
        (_) async => const Ok([_standard, _estate, _mpv, _minibus]));

    await shoot(
      t,
      ProviderScope(
        overrides: [vehicleRepositoryProvider.overrideWithValue(repo)],
        child: const ScheduleRideScreen(),
      ),
      'schedule_ride_narrow',
    );
  });
}
