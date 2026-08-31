import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hoppin_rider/core/api/api_exception.dart';
import 'package:hoppin_rider/core/money.dart';
import 'package:hoppin_rider/core/result.dart';
import 'package:hoppin_rider/core/theme/app_theme.dart';
import 'package:hoppin_rider/features/history/data/trip_history_repository.dart';
import 'package:hoppin_rider/features/history/presentation/ride_history_screen.dart';
import 'package:intl/intl.dart';
import 'package:mocktail/mocktail.dart';

class _MockRepo extends Mock implements TripHistoryRepository {}

TripHistoryItem _trip({
  String id = 'r1',
  String status = 'completed',
  String? pickup = 'Wolverhampton City Centre',
  String? dropoff = 'Wolverhampton Railway Station',
  Pence? total = const Pence(386),
  DateTime? at,
  TripDriver? driver = const TripDriver(
    id: 'd1',
    fullName: 'Sam Driver',
    avatarUrl: null,
    rating: 4.3,
    ratingCount: 113,
  ),
  String? cancelledBy,
}) =>
    TripHistoryItem(
      id: id,
      ref: 'R-1042',
      status: status,
      rideCategory: 'standard',
      vehicleCategory: null,
      pickupLabel: pickup,
      dropoffLabel: dropoff,
      requestedAt: at ?? DateTime.utc(2026, 2, 16, 11, 50),
      pickupTime: at ?? DateTime.utc(2026, 2, 16, 11, 50),
      dropoffTime: null,
      totalPence: total,
      currency: 'GBP',
      driver: driver,
      myRating: null,
      cancelledBy: cancelledBy,
    );

/// The screen is routed, not pushed bare: tapping a card navigates with
/// go_router, so the harness gives it a real router to navigate in.
Widget _harness(
  _MockRepo repo, {
  Brightness brightness = Brightness.light,
  List<String>? visited,
}) =>
    ProviderScope(
      overrides: [
        tripHistoryRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp.router(
        theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
        routerConfig: GoRouter(
          initialLocation: '/ride-history',
          routes: [
            GoRoute(
              path: '/ride-history',
              builder: (_, __) => const RideHistoryScreen(),
            ),
            GoRoute(
              path: '/trip-details',
              builder: (_, state) {
                visited?.add(state.uri.toString());
                return const Scaffold(body: Text('trip details'));
              },
            ),
          ],
        ),
      ),
    );

void _answer(_MockRepo repo, List<TripHistoryItem> trips,
    {bool hasMore = false, String? cursor}) {
  when(() => repo.myTrips(
        limit: any(named: 'limit'),
        cursor: any(named: 'cursor'),
        status: any(named: 'status'),
        from: any(named: 'from'),
        to: any(named: 'to'),
      )).thenAnswer((_) async => Ok(TripHistoryPage(
        trips: trips,
        nextCursor: cursor,
        hasMore: hasMore,
      )));
}

void main() {
  late _MockRepo repo;

  setUp(() => repo = _MockRepo());

  testWidgets('shows the Ride History title with a back arrow', (tester) async {
    _answer(repo, [_trip()]);

    await tester.pumpWidget(_harness(repo));
    await tester.pumpAndSettle();

    expect(find.text('Ride History'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
  });

  testWidgets('renders a trip card with pickup, dropoff, fare and time',
      (tester) async {
    _answer(repo, [_trip()]);

    await tester.pumpWidget(_harness(repo));
    await tester.pumpAndSettle();

    expect(find.text('Wolverhampton City Centre'), findsOneWidget);
    expect(find.text('Wolverhampton Railway Station'), findsOneWidget);
    expect(find.text('£3.86'), findsOneWidget);
    // The card renders the time in the RIDER's zone, so asserting the literal
    // UTC hour would only pass on a machine set to UTC. Assert the shape the
    // frame shows ("11:50 AM") against the same local conversion the screen
    // does, which holds in every zone.
    expect(
      find.text(DateFormat('h:mm a')
          .format(DateTime.utc(2026, 2, 16, 11, 50).toLocal())),
      findsOneWidget,
    );
  });

  testWidgets('groups trips under a date header per the frame', (tester) async {
    _answer(repo, [
      _trip(id: 'a', at: DateTime.utc(2026, 2, 16, 11, 50)),
      _trip(id: 'b', at: DateTime.utc(2026, 2, 14, 9, 5)),
      _trip(id: 'c', at: DateTime.utc(2026, 2, 14, 18, 30)),
    ]);

    await tester.pumpWidget(_harness(repo));
    await tester.pumpAndSettle();

    // "16 Feb" style, one header per distinct day - not one per trip.
    expect(find.text('16 Feb'), findsOneWidget);
    expect(find.text('14 Feb'), findsOneWidget);
  });

  testWidgets('shows the driver rating with its count', (tester) async {
    _answer(repo, [_trip()]);

    await tester.pumpWidget(_harness(repo));
    await tester.pumpAndSettle();

    expect(find.text('4.3 (113)'), findsOneWidget);
    expect(find.byIcon(Icons.star), findsOneWidget);
  });

  testWidgets('fabricates no rating when there is no driver', (tester) async {
    _answer(repo, [_trip(driver: null)]);

    await tester.pumpWidget(_harness(repo));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.star), findsNothing);
    expect(find.textContaining('('), findsNothing);
  });

  testWidgets('fabricates no rating when the driver has never been rated',
      (tester) async {
    _answer(repo, [
      _trip(
          driver: const TripDriver(
        id: 'd1',
        fullName: 'New Driver',
        avatarUrl: null,
        rating: null,
        ratingCount: 0,
      )),
    ]);

    await tester.pumpWidget(_harness(repo));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.star), findsNothing);
    expect(find.text('0.0 (0)'), findsNothing);
  });

  testWidgets('a cancelled trip says so instead of showing a rating',
      (tester) async {
    _answer(repo, [
      _trip(status: 'cancelled', cancelledBy: 'rider', driver: null),
    ]);

    await tester.pumpWidget(_harness(repo));
    await tester.pumpAndSettle();

    expect(find.text('Cancelled'), findsOneWidget);
    expect(find.byIcon(Icons.star), findsNothing);
  });

  testWidgets('an uncharged trip does not print £0.00', (tester) async {
    _answer(repo, [_trip(total: null)]);

    await tester.pumpWidget(_harness(repo));
    await tester.pumpAndSettle();

    expect(find.text('£0.00'), findsNothing);
  });

  testWidgets('tapping a card opens that trip in trip details', (tester) async {
    final visited = <String>[];
    _answer(repo, [_trip(id: 'ride-77')]);

    await tester.pumpWidget(_harness(repo, visited: visited));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Wolverhampton City Centre'));
    await tester.pumpAndSettle();

    expect(visited, ['/trip-details?ride=ride-77']);
  });

  testWidgets('an empty history says so without fabricating rows',
      (tester) async {
    _answer(repo, []);

    await tester.pumpWidget(_harness(repo));
    await tester.pumpAndSettle();

    expect(find.textContaining('Wolverhampton'), findsNothing);
    expect(find.textContaining('No rides yet'), findsOneWidget);
  });

  testWidgets('a failure shows the server copy verbatim', (tester) async {
    when(() => repo.myTrips(
          limit: any(named: 'limit'),
          cursor: any(named: 'cursor'),
          status: any(named: 'status'),
          from: any(named: 'from'),
          to: any(named: 'to'),
        )).thenAnswer((_) async => Err<TripHistoryPage>(
        const ApiException('INTERNAL', 'History is briefly unavailable.', 500)));

    await tester.pumpWidget(_harness(repo));
    await tester.pumpAndSettle();

    expect(find.text('History is briefly unavailable.'), findsOneWidget);
  });

  testWidgets('renders in dark mode', (tester) async {
    _answer(repo, [_trip()]);

    await tester.pumpWidget(_harness(repo, brightness: Brightness.dark));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Wolverhampton City Centre'), findsOneWidget);
  });

  testWidgets('does not overflow at 320 wide', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    _answer(repo, [
      _trip(
        pickup: 'Wolverhampton City Centre Bus Interchange Stand F',
        dropoff: 'Wolverhampton Railway Station Main Entrance',
      ),
    ]);

    await tester.pumpWidget(_harness(repo));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
