import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/api/api_client.dart';
import 'package:hoppin_rider/core/api/api_exception.dart';
import 'package:hoppin_rider/core/money.dart';
import 'package:hoppin_rider/core/result.dart';
import 'package:hoppin_rider/features/history/data/trip_history_repository.dart';
import 'package:mocktail/mocktail.dart';

class _MockApi extends Mock implements ApiClient {}

/// One well-formed row, matching `rider_trips_read.go` exactly.
Map<String, dynamic> _trip({
  String id = 'r1',
  String status = 'completed',
  Object? totalPence = 386,
  Object? driver = _absent,
  Object? cancelledBy,
}) =>
    {
      'id': id,
      'ref': 'R-1042',
      'status': status,
      'ride_category': 'standard',
      'vehicle_category': {
        'id': 'vc1',
        'name': 'Saloon',
        'seats': 4,
        'bags': 2,
      },
      'pickup_label': 'Wolverhampton City Centre',
      'dropoff_label': 'Wolverhampton Railway Station',
      'requested_at': '2026-02-16T11:50:00Z',
      'pickup_time': '2026-02-16T11:50:00Z',
      'dropoff_time': '2026-02-16T12:10:00Z',
      'total_pence': totalPence,
      'currency': 'GBP',
      'driver': identical(driver, _absent)
          ? {
              'id': 'd1',
              'full_name': 'Sam Driver',
              'avatar_url': null,
              'rating': 4.3,
              'rating_count': 113,
            }
          : driver,
      'my_rating': null,
      'cancelled_by': cancelledBy,
    };

const _absent = Object();

void main() {
  late _MockApi api;
  late TripHistoryRepository repo;

  setUp(() {
    api = _MockApi();
    repo = TripHistoryRepository(api);
  });

  void answer(Object? body) {
    when(() => api.get<dynamic>(any(), query: any(named: 'query')))
        .thenAnswer((_) async => Ok<dynamic>(body));
  }

  group('the trips envelope', () {
    test('reads trips, has_more and next_cursor', () async {
      answer({
        'trips': [_trip()],
        'has_more': true,
        'next_cursor': '2026-02-16T11:50:00Z',
      });

      final page = ((await repo.myTrips()) as Ok<TripHistoryPage>).value;

      expect(page.trips, hasLength(1));
      expect(page.hasMore, isTrue);
      expect(page.nextCursor, '2026-02-16T11:50:00Z');
    });

    test('a page with no cursor is the last page', () async {
      answer({'trips': <dynamic>[], 'has_more': false, 'next_cursor': null});

      final page = ((await repo.myTrips()) as Ok<TripHistoryPage>).value;

      expect(page.trips, isEmpty);
      expect(page.hasMore, isFalse);
      expect(page.nextCursor, isNull);
    });

    test('has_more is false when the server omits it', () async {
      // Defensive: a truncated envelope must not make the list page forever.
      answer({'trips': <dynamic>[]});

      final page = ((await repo.myTrips()) as Ok<TripHistoryPage>).value;

      expect(page.hasMore, isFalse);
    });

    test('surfaces a server failure rather than an empty history', () async {
      when(() => api.get<dynamic>(any(), query: any(named: 'query')))
          .thenAnswer((_) async =>
              Err<dynamic>(const ApiException('INTERNAL', 'server error', 500)));

      final result = await repo.myTrips();

      expect((result as Err).error.code, 'INTERNAL',
          reason: 'an empty list would tell the rider they never travelled');
    });
  });

  group('crash safety at the JSON boundary', () {
    test('non-object rows do not take down the history list', () async {
      // List.cast() is lazy in Dart: it throws when map pulls the bad element,
      // escaping a method whose signature promises a Result.
      answer({
        'trips': [_trip(id: 'r1'), null, 'not an object', _trip(id: 'r2')],
      });

      final page = ((await repo.myTrips()) as Ok<TripHistoryPage>).value;

      expect(page.trips.map((t) => t.id), ['r1', 'r2']);
    });

    test('a row with no id is dropped, not rendered', () async {
      // Without an id the card cannot open trip details, so it is a dead row.
      final idless = _trip()..remove('id');
      answer({
        'trips': [idless, _trip(id: 'r2')],
      });

      final page = ((await repo.myTrips()) as Ok<TripHistoryPage>).value;

      expect(page.trips.map((t) => t.id), ['r2']);
    });

    test('a trips key that is not a list reads as empty, not a crash',
        () async {
      answer({'trips': 'nonsense'});

      final result = await repo.myTrips();

      expect((result as Ok<TripHistoryPage>).value.trips, isEmpty);
    });
  });

  group('money', () {
    test('total_pence reads as Pence, never a double', () async {
      answer({
        'trips': [_trip(totalPence: 386)],
      });

      final trip = ((await repo.myTrips()) as Ok<TripHistoryPage>).value.trips.single;

      expect(trip.totalPence, const Pence(386));
      expect(trip.currency, 'GBP');
    });

    test('a null total stays null so it never prints as £0.00', () async {
      // "Not charged yet" and "free" are different things.
      answer({
        'trips': [_trip(totalPence: null)],
      });

      final trip = ((await repo.myTrips()) as Ok<TripHistoryPage>).value.trips.single;

      expect(trip.totalPence, isNull);
    });
  });

  group('driver and rating', () {
    test('reads the driver with their rating and count', () async {
      answer({
        'trips': [_trip()],
      });

      final trip = ((await repo.myTrips()) as Ok<TripHistoryPage>).value.trips.single;

      expect(trip.driver!.fullName, 'Sam Driver');
      expect(trip.driver!.rating, 4.3);
      expect(trip.driver!.ratingCount, 113);
    });

    test('a null driver stays null - no fabricated name', () async {
      answer({
        'trips': [_trip(driver: null)],
      });

      final trip = ((await repo.myTrips()) as Ok<TripHistoryPage>).value.trips.single;

      expect(trip.driver, isNull);
    });

    test('an unrated driver has a null rating, not 0', () async {
      // The backend comment is explicit: a missing rating renders "—", never
      // "0 stars".
      answer({
        'trips': [
          _trip(driver: {
            'id': 'd1',
            'full_name': 'New Driver',
            'avatar_url': null,
            'rating': null,
            'rating_count': 0,
          }),
        ],
      });

      final trip = ((await repo.myTrips()) as Ok<TripHistoryPage>).value.trips.single;

      expect(trip.driver!.rating, isNull);
      expect(trip.driver!.ratingCount, 0);
    });
  });

  group('status', () {
    test('a cancelled trip carries who cancelled it', () async {
      answer({
        'trips': [_trip(status: 'cancelled', cancelledBy: 'driver')],
      });

      final trip = ((await repo.myTrips()) as Ok<TripHistoryPage>).value.trips.single;

      expect(trip.isCancelled, isTrue);
      expect(trip.cancelledBy, 'driver');
    });

    test('a completed trip is not cancelled and attributes nobody', () async {
      answer({
        'trips': [_trip()],
      });

      final trip = ((await repo.myTrips()) as Ok<TripHistoryPage>).value.trips.single;

      expect(trip.isCancelled, isFalse);
      expect(trip.cancelledBy, isNull);
    });
  });

  group('query parameters the endpoint actually supports', () {
    test('sends no filter params on a bare first page', () async {
      answer({'trips': <dynamic>[]});

      await repo.myTrips();

      final captured = verify(() => api.get<dynamic>('/rides',
          query: captureAny(named: 'query'))).captured.single as Map;

      expect(captured.containsKey('cursor'), isFalse);
      expect(captured.containsKey('status'), isFalse);
      expect(captured['limit'], 20);
    });

    test('pages with the cursor the previous page returned', () async {
      answer({'trips': <dynamic>[]});

      await repo.myTrips(cursor: '2026-02-16T11:50:00Z');

      final captured = verify(() => api.get<dynamic>('/rides',
          query: captureAny(named: 'query'))).captured.single as Map;

      expect(captured['cursor'], '2026-02-16T11:50:00Z');
    });

    test('sends from/to for a month filter - the server does the filtering',
        () async {
      answer({'trips': <dynamic>[]});

      await repo.myTrips(
        from: DateTime.utc(2026, 2, 1),
        to: DateTime.utc(2026, 2, 28, 23, 59, 59),
      );

      final captured = verify(() => api.get<dynamic>('/rides',
          query: captureAny(named: 'query'))).captured.single as Map;

      expect(captured['from'], startsWith('2026-02-01T00:00:00'));
      expect(captured['to'], startsWith('2026-02-28T23:59:59'));
    });

    test('clamps limit to the 50 the handler caps at', () async {
      answer({'trips': <dynamic>[]});

      await repo.myTrips(limit: 500);

      final captured = verify(() => api.get<dynamic>('/rides',
          query: captureAny(named: 'query'))).captured.single as Map;

      expect(captured['limit'], 50);
    });
  });
}
