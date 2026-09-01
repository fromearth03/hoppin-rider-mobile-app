@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hoppin_rider/core/geo.dart';
import 'package:hoppin_rider/core/money.dart';
import 'package:hoppin_rider/core/result.dart';
import 'package:hoppin_rider/core/theme/app_theme.dart';
import 'package:hoppin_rider/features/auth/presentation/expired_link_screen.dart';
import 'package:hoppin_rider/features/auth/presentation/link_sent_screen.dart';
import 'package:hoppin_rider/features/booking/data/fare_repository.dart';
import 'package:hoppin_rider/features/booking/data/places_repository.dart';
import 'package:hoppin_rider/features/booking/data/saved_locations_repository.dart';
import 'package:hoppin_rider/features/booking/data/vehicle_repository.dart';
import 'package:hoppin_rider/features/booking/presentation/fare_confirm_screen.dart';
import 'package:hoppin_rider/features/booking/presentation/route_entry_screen.dart';
import 'package:hoppin_rider/features/booking/presentation/saved_places_screen.dart';
import 'package:hoppin_rider/features/chat/data/chat_repository.dart';
import 'package:hoppin_rider/features/chat/presentation/chat_screen.dart';
import 'package:hoppin_rider/features/trip/data/live_trip_source.dart';
import 'package:hoppin_rider/features/trip/presentation/live_trip_screen.dart';
import 'package:mocktail/mocktail.dart';

class _MockFareRepository extends Mock implements FareRepository {}

class _MockSavedRepo extends Mock implements SavedLocationsRepository {}

class _MockPlacesRepo extends Mock implements PlacesRepository {}

class _MockChat extends Mock implements ChatRepository {}

const _pickup = LatLng(52.586, -2.128);
const _dropoff = LatLng(52.593, -2.110);

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
  seats: 4,
  bags: 4,
  priceMultiplier: 1.3,
);

FareEstimate _estimate(int totalPence, int durationSeconds) => FareEstimate(
      totalPence: Pence(totalPence),
      currency: 'GBP',
      distanceMeters: 4000,
      durationSeconds: durationSeconds,
      legs: const [],
      isMultiStop: false,
      stopsCount: 0,
      route: null,
      discountPence: Pence.zero,
      discountPct: 0,
      discountKnown: true,
      etaSource: 'model',
    );

/// Renders the fidelity-pass screens to PNGs so they can be put side by side
/// with `docs/figma/extracted/`. See `auth_render_test.dart` for why these
/// are renders, not assertions.
void main() {
  Future<void> shoot(
    WidgetTester tester,
    Widget screen,
    String name, {
    Brightness brightness = Brightness.light,
  }) async {
    // The Figma frames are 430x932.
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

  setUpAll(() {
    registerFallbackValue(_pickup);
  });

  testWidgets('fare confirm light', (t) async {
    final repo = _MockFareRepository();
    when(() => repo.estimate(
          pickup: any(named: 'pickup'),
          dropoff: any(named: 'dropoff'),
          vehicleCategoryId: any(named: 'vehicleCategoryId'),
          waypoints: any(named: 'waypoints'),
        )).thenAnswer((invocation) async {
      final id = invocation.namedArguments[#vehicleCategoryId] as String;
      return Ok(id == 'a' ? _estimate(2500, 300) : _estimate(1975, 720));
    });

    await shoot(
      t,
      ProviderScope(
        overrides: [fareRepositoryProvider.overrideWithValue(repo)],
        child: FareConfirmScreen(
          pickup: _pickup,
          dropoff: _dropoff,
          categories: const [_standard, _estate],
        ),
      ),
      'fare_confirm_light',
    );
  });

  testWidgets('live trip light', (t) async {
    t.view.physicalSize = const Size(430, 932);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);

    await t.pumpWidget(
      ProviderScope(
        overrides: [
          liveTripInfoProvider('r1').overrideWith(
            (ref) => Stream.value(LiveTripInfo(
              rideId: 'r1',
              status: LiveTripStatus.arriving,
              driver: const TripDriver(
                name: 'George',
                rating: 4.3,
                ratingCount: 113,
                tripsCompleted: 40,
                plate: 'AB12 CDE',
                vehicleType: 'Standard',
                seats: 4,
                bags: 2,
              ),
              baseFarePence: const Pence(2500),
              surgeMultiplier: null,
              surgePence: null,
              totalPence: const Pence(2500),
              currency: 'GBP',
              cancellationPolicy: null,
              waypoints: const [],
              route: null,
              steps: null,
              destinationLabel: null,
            )),
          ),
        ],
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          routerConfig: GoRouter(
            initialLocation: '/trip',
            routes: [
              GoRoute(
                path: '/trip',
                builder: (_, __) => const LiveTripScreen(rideId: 'r1'),
              ),
              GoRoute(
                path: '/chat',
                builder: (_, __) => const Scaffold(body: Text('chat')),
              ),
              GoRoute(
                path: '/safety',
                builder: (_, __) => const Scaffold(body: Text('safety')),
              ),
            ],
          ),
        ),
      ),
    );
    await t.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('shots/live_trip_light.png'),
    );
  });

  testWidgets('saved places light', (t) async {
    final repo = _MockSavedRepo();
    when(() => repo.list()).thenAnswer((_) async => const Ok([
          SavedLocation(id: '1', label: 'Home', lat: 51.5, lng: -0.1),
          SavedLocation(id: '2', label: 'Work', lat: 51.51, lng: -0.11),
        ]));

    await shoot(
      t,
      ProviderScope(
        overrides: [savedLocationsRepositoryProvider.overrideWithValue(repo)],
        child: const SavedPlacesScreen(),
      ),
      'saved_places_light',
    );
  });

  testWidgets('link sent light', (t) async {
    await shoot(
      t,
      const LinkSentScreen(email: 'ali.asghar123@gmail.com'),
      'link_sent_light',
    );
  });

  testWidgets('expired link light', (t) async {
    await shoot(t, const ExpiredLinkScreen(), 'expired_link_light');
  });

  testWidgets('route entry light', (t) async {
    final placesRepo = _MockPlacesRepo();
    when(() => placesRepo.search(any())).thenAnswer((_) async => const Ok([]));

    await shoot(
      t,
      ProviderScope(
        overrides: [placesRepositoryProvider.overrideWithValue(placesRepo)],
        child: const RouteEntryScreen(),
      ),
      'route_entry_light',
    );
  });

  testWidgets('chat light 2', (t) async {
    final repo = _MockChat();
    final now = DateTime(2026, 8, 31, 12);

    when(() => repo.messages(any(), since: any(named: 'since')))
        .thenAnswer((_) async => Ok([
              RideMessage(
                id: '1',
                body: "Lorem Ipsum has been the industry's standard dummy",
                senderRole: 'driver',
                createdAt: now,
                status: null,
                replyToId: null,
                replyToPreview: null,
              ),
              RideMessage(
                id: '2',
                body: "Lorem Ipsum has been the industry's standard dummy",
                senderRole: 'rider',
                createdAt: now.add(const Duration(minutes: 1)),
                status: 'read',
                replyToId: null,
                replyToPreview: null,
              ),
            ]));

    t.view.physicalSize = const Size(430, 932);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);

    await t.pumpWidget(
      ProviderScope(
        overrides: [chatRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          home: const ChatScreen(rideId: 'r1', driverName: 'George'),
        ),
      ),
    );
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('shots/chat_light_2.png'),
    );
  });
}
