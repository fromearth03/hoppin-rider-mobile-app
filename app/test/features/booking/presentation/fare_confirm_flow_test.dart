import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hoppin_rider/core/api/api_exception.dart';
import 'package:hoppin_rider/core/geo.dart';
import 'package:hoppin_rider/core/money.dart';
import 'package:hoppin_rider/core/result.dart';
import 'package:hoppin_rider/core/theme/app_theme.dart';
import 'package:hoppin_rider/features/booking/data/booking_repository.dart';
import 'package:hoppin_rider/features/booking/data/fare_repository.dart';
import 'package:hoppin_rider/features/booking/data/vehicle_repository.dart';
import 'package:hoppin_rider/features/booking/presentation/fare_confirm_flow.dart';
import 'package:hoppin_rider/features/booking/presentation/home_screen.dart';
import 'package:hoppin_rider/features/booking/presentation/route_entry_screen.dart';
import 'package:hoppin_rider/features/booking/presentation/widgets/vehicle_card.dart';
import 'package:hoppin_rider/shared/nav/app_router.dart';
import 'package:mocktail/mocktail.dart';

class _MockFares extends Mock implements FareRepository {}

class _MockBooking extends Mock implements BookingRepository {}

const _standard = VehicleCategory(
  id: 'a',
  name: 'Standard',
  seats: 4,
  bags: 2,
  priceMultiplier: 1.0,
);

const _route = ChosenRoute(
  pickup: RoutePoint('Hanley', LatLng(53.0235, -2.1774)),
  dropoff: RoutePoint('Keele', LatLng(53.0044, -2.2734)),
);

const _estimate = FareEstimate(
  totalPence: Pence(2500),
  currency: 'GBP',
  distanceMeters: 8000,
  durationSeconds: 900,
  legs: [],
  isMultiStop: false,
  stopsCount: 0,
  route: null,
  discountPence: Pence.zero,
  discountPct: 0,
  discountKnown: true,
  etaSource: 'osrm',
);

void main() {
  setUpAll(() {
    registerFallbackValue(const LatLng(0, 0));
  });

  late _MockFares fares;
  late _MockBooking booking;
  String? location;

  Widget harness() {
    final router = GoRouter(
      initialLocation: AppRoutes.fareConfirm,
      routes: [
        GoRoute(
          path: AppRoutes.fareConfirm,
          builder: (_, __) => const FareConfirmFlow(route: _route),
        ),
        GoRoute(
          path: AppRoutes.liveTrip,
          builder: (_, state) {
            location = state.uri.toString();
            return const Scaffold(body: Text('live trip'));
          },
        ),
      ],
    );
    return ProviderScope(
      overrides: [
        vehicleCategoriesProvider.overrideWith((ref) async => [_standard]),
        fareRepositoryProvider.overrideWithValue(fares),
        bookingRepositoryProvider.overrideWithValue(booking),
      ],
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    );
  }

  setUp(() {
    fares = _MockFares();
    booking = _MockBooking();
    location = null;
    when(() => fares.estimate(
          pickup: any(named: 'pickup'),
          dropoff: any(named: 'dropoff'),
          vehicleCategoryId: any(named: 'vehicleCategoryId'),
          waypoints: any(named: 'waypoints'),
        )).thenAnswer((_) async => const Ok(_estimate));
  });

  testWidgets('quotes the fetched categories for the chosen route',
      (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(find.byType(VehicleCard), findsOneWidget);
    final captured = verify(() => fares.estimate(
          pickup: captureAny(named: 'pickup'),
          dropoff: any(named: 'dropoff'),
          vehicleCategoryId: any(named: 'vehicleCategoryId'),
          waypoints: any(named: 'waypoints'),
        )).captured;
    expect((captured.single as LatLng).lat, _route.pickup.position.lat);
  });

  testWidgets('confirm books the ride and lands on the live trip',
      (tester) async {
    when(() => booking.request(
          pickup: any(named: 'pickup'),
          dropoff: any(named: 'dropoff'),
          vehicleCategoryId: any(named: 'vehicleCategoryId'),
          waypoints: any(named: 'waypoints'),
          estimatePence: any(named: 'estimatePence'),
          estimateDistanceMeters: any(named: 'estimateDistanceMeters'),
          estimateDurationSeconds: any(named: 'estimateDurationSeconds'),
        )).thenAnswer((_) async => const Ok(BookingRequest('req-42')));

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(VehicleCard));
    await tester.pumpAndSettle();
    // Open the collapsible sheet fully, then scroll ITS list (the
    // vehicle grid is also a Scrollable, so target the sheet's own).
    await tester.drag(
        find.text('Ride Details'), const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Confirm Booking'), 80,
        scrollable: find
            .descendant(
                of: find.byType(DraggableScrollableSheet),
                matching: find.byType(Scrollable))
            .first);
    await tester.tap(find.text('Confirm Booking'));
    await tester.pumpAndSettle();

    expect(find.text('live trip'), findsOneWidget);
    // The returned id IS the ride id (the server creates the ride at
    // booking), so the trip screen binds to it directly.
    expect(location, contains('ride=req-42'));
    verify(() => booking.request(
          pickup: any(named: 'pickup'),
          dropoff: any(named: 'dropoff'),
          vehicleCategoryId: 'a',
          waypoints: any(named: 'waypoints'),
          estimatePence: any(named: 'estimatePence'),
          estimateDistanceMeters: any(named: 'estimateDistanceMeters'),
          estimateDurationSeconds: any(named: 'estimateDurationSeconds'),
        )).called(1);
  });

  testWidgets('a booking failure surfaces the server message and stays put',
      (tester) async {
    when(() => booking.request(
          pickup: any(named: 'pickup'),
          dropoff: any(named: 'dropoff'),
          vehicleCategoryId: any(named: 'vehicleCategoryId'),
          waypoints: any(named: 'waypoints'),
          estimatePence: any(named: 'estimatePence'),
          estimateDistanceMeters: any(named: 'estimateDistanceMeters'),
          estimateDurationSeconds: any(named: 'estimateDurationSeconds'),
        )).thenAnswer((_) async => const Err(
          ApiException('NO_PAYMENT_METHOD', 'Add a payment card first.', 402),
        ));

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(VehicleCard));
    await tester.pumpAndSettle();
    // Open the collapsible sheet fully, then scroll ITS list (the
    // vehicle grid is also a Scrollable, so target the sheet's own).
    await tester.drag(
        find.text('Ride Details'), const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Confirm Booking'), 80,
        scrollable: find
            .descendant(
                of: find.byType(DraggableScrollableSheet),
                matching: find.byType(Scrollable))
            .first);
    await tester.tap(find.text('Confirm Booking'));
    await tester.pumpAndSettle();

    expect(find.text('live trip'), findsNothing);
    expect(find.textContaining('card'), findsWidgets);
  });
}
