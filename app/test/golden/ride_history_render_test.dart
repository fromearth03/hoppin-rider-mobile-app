@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hoppin_rider/core/money.dart';
import 'package:hoppin_rider/core/result.dart';
import 'package:hoppin_rider/core/theme/app_theme.dart';
import 'package:hoppin_rider/features/history/data/trip_history_repository.dart';
import 'package:hoppin_rider/features/history/presentation/ride_history_screen.dart';
import 'package:mocktail/mocktail.dart';

class _MockRepo extends Mock implements TripHistoryRepository {}

/// Renders Ride History to PNGs so they can be put side by side with
/// `docs/figma/extracted/Ride History.png`.
///
/// Not assertions — a widget test proves behaviour and nothing here proves
/// appearance, which is exactly why screens drift from the design. Run with
/// `flutter test test/golden/ride_history_render_test.dart --run-skipped
/// --update-goldens` and look at the output.
///
/// Shot names are prefixed `ride_history_list_` rather than `ride_history_`:
/// `history_and_schedule_render_test.dart` and `narrow_account_render_test.dart`
/// already write `ride_history_light`/`ride_history_narrow`, and they build the
/// screen with no repository override, so they now capture its loading state.
/// A distinct prefix keeps whichever file runs last from silently deciding what
/// those PNGs contain.
void main() {
  /// The frame's own sample rows: three days, four trips, the last day
  /// carrying two cards.
  TripHistoryItem trip(String id, DateTime at) => TripHistoryItem(
        id: id,
        ref: 'R-1042',
        status: 'completed',
        rideCategory: 'standard',
        vehicleCategory: null,
        pickupLabel: 'Wolverhampton City Centre',
        dropoffLabel: 'Wolverhampton Railway Station',
        requestedAt: at,
        pickupTime: at,
        dropoffTime: null,
        totalPence: const Pence(386),
        currency: 'GBP',
        driver: const TripDriver(
          id: 'd1',
          fullName: 'Sam Driver',
          avatarUrl: null,
          rating: 4.3,
          ratingCount: 113,
        ),
        myRating: null,
        cancelledBy: null,
      );

  /// A local-time constructor: the screen renders in the rider's zone, so
  /// building fixtures in local time keeps the shot stable on any machine.
  DateTime at(int day, int hour, int minute) =>
      DateTime(2026, 2, day, hour, minute);

  late _MockRepo repo;

  setUp(() {
    repo = _MockRepo();
    when(() => repo.myTrips(
          limit: any(named: 'limit'),
          cursor: any(named: 'cursor'),
          status: any(named: 'status'),
          from: any(named: 'from'),
          to: any(named: 'to'),
        )).thenAnswer((_) async => Ok(TripHistoryPage(
          trips: [
            trip('r1', at(16, 11, 50)),
            trip('r2', at(14, 11, 50)),
            trip('r3', at(13, 11, 50)),
            trip('r4', at(13, 11, 50)),
          ],
          nextCursor: null,
          hasMore: false,
        )));
  });

  Future<void> shoot(
    WidgetTester tester,
    String name, {
    Brightness brightness = Brightness.light,
    // The Figma frame is 430x932. A 320-wide render is not a Figma frame — it
    // exists purely to surface the class of bug a squeezed flexible child
    // produces, which only shows up under narrower constraints.
    double width = 430,
    TripHistoryPage? page,
  }) async {
    if (page != null) {
      when(() => repo.myTrips(
            limit: any(named: 'limit'),
            cursor: any(named: 'cursor'),
            status: any(named: 'status'),
            from: any(named: 'from'),
            to: any(named: 'to'),
          )).thenAnswer((_) async => Ok(page));
    }

    tester.view.physicalSize = Size(width, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [tripHistoryRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          theme:
              brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
          routerConfig: GoRouter(
            initialLocation: '/ride-history',
            routes: [
              GoRoute(
                path: '/ride-history',
                builder: (_, __) => const RideHistoryScreen(),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('shots/$name.png'),
    );
  }

  testWidgets('ride history light', (t) async {
    await shoot(t, 'ride_history_list_light');
  });

  testWidgets('ride history dark', (t) async {
    await shoot(t, 'ride_history_list_dark', brightness: Brightness.dark);
  });

  testWidgets('ride history narrow', (t) async {
    await shoot(t, 'ride_history_list_narrow', width: 320);
  });

  /// The states the frame does not draw but the endpoint really returns: a
  /// cancelled trip, a trip with no driver, and one never charged.
  testWidgets('ride history mixed states', (t) async {
    await shoot(
      t,
      'ride_history_list_mixed',
      page: TripHistoryPage(
        trips: [
          trip('r1', at(16, 11, 50)),
          TripHistoryItem(
            id: 'r2',
            ref: null,
            status: 'cancelled',
            rideCategory: 'standard',
            vehicleCategory: null,
            pickupLabel: 'Wolverhampton City Centre',
            dropoffLabel: 'Wolverhampton Railway Station',
            requestedAt: at(15, 9, 5),
            pickupTime: null,
            dropoffTime: null,
            totalPence: null,
            currency: 'GBP',
            driver: null,
            myRating: null,
            cancelledBy: 'rider',
          ),
          TripHistoryItem(
            id: 'r3',
            ref: null,
            status: 'completed',
            rideCategory: 'standard',
            vehicleCategory: null,
            pickupLabel: 'Wolverhampton City Centre',
            dropoffLabel: 'Wolverhampton Railway Station',
            requestedAt: at(14, 18, 30),
            pickupTime: at(14, 18, 30),
            dropoffTime: null,
            totalPence: const Pence(1250),
            currency: 'GBP',
            driver: const TripDriver(
              id: 'd2',
              fullName: 'New Driver',
              avatarUrl: null,
              rating: null,
              ratingCount: 0,
            ),
            myRating: null,
            cancelledBy: null,
          ),
        ],
        nextCursor: null,
        hasMore: false,
      ),
    );
  });

  testWidgets('ride history empty', (t) async {
    await shoot(
      t,
      'ride_history_list_empty',
      page: const TripHistoryPage(trips: [], nextCursor: null, hasMore: false),
    );
  });
}
