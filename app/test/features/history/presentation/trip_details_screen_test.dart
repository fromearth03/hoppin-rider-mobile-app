import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/api/api_client.dart';
import 'package:hoppin_rider/core/api/api_exception.dart';
import 'package:hoppin_rider/core/result.dart';
import 'package:hoppin_rider/core/theme/app_theme.dart';
import 'package:hoppin_rider/features/history/presentation/trip_details_screen.dart';
import 'package:mocktail/mocktail.dart';

class _MockApi extends Mock implements ApiClient {}

Widget _harness(
  ApiClient api, {
  String rideId = 'r1',
  Brightness brightness = Brightness.light,
}) =>
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(api),
      ],
      child: MaterialApp(
        theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
        home: TripDetailsScreen(rideId: rideId),
      ),
    );

void main() {
  late _MockApi api;

  setUp(() {
    api = _MockApi();
  });

  testWidgets('an empty ride id never hits the network', (tester) async {
    await tester.pumpWidget(_harness(api, rideId: ''));
    await tester.pumpAndSettle();

    verifyZeroInteractions(api);
    expect(find.text('This ride could not be found.'), findsOneWidget);
  });

  testWidgets('shows a loading indicator while the receipt is in flight',
      (tester) async {
    final completer = Completer<Ok<Map<String, dynamic>>>();
    when(() => api.get<Map<String, dynamic>>(any()))
        .thenAnswer((_) => completer.future);

    await tester.pumpWidget(_harness(api));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Resolve so nothing is left pending when the test tears down.
    completer.complete(
        const Ok({'ride_id': 'r1', 'currency': 'GBP', 'status': 'captured'}));
    await tester.pumpAndSettle();
  });

  testWidgets('shows the server error message on failure', (tester) async {
    when(() => api.get<Map<String, dynamic>>(any())).thenAnswer((_) async =>
        const Err(ApiException('RIDE_NOT_FOUND', 'That trip no longer exists.', 404)));

    await tester.pumpWidget(_harness(api));
    await tester.pumpAndSettle();

    expect(find.text('That trip no longer exists.'), findsOneWidget);
  });

  testWidgets('renders total, distance and duration for a charged trip',
      (tester) async {
    when(() => api.get<Map<String, dynamic>>(any())).thenAnswer((_) async => const Ok({
          'ride_id': 'r1',
          'ride_category': 'Standard',
          'fare_pence': 1238,
          'waiting_pence': 0,
          'total_pence': 1238,
          'currency': 'GBP',
          'status': 'captured',
          'distance_miles': 4.7,
          'pickup_time': '2026-08-31T09:00:00Z',
          'dropoff_time': '2026-08-31T09:20:00Z',
        }));

    await tester.pumpWidget(_harness(api));
    await tester.pumpAndSettle();

    expect(find.text('£12.38'), findsWidgets);
    expect(find.textContaining('4.7'), findsOneWidget);
    // 20 minute journey computed from pickup/dropoff.
    expect(find.textContaining('20 min'), findsOneWidget);
  });

  testWidgets('a null total is shown as an honest not-charged state, never £0.00',
      (tester) async {
    when(() => api.get<Map<String, dynamic>>(any())).thenAnswer((_) async => const Ok({
          'ride_id': 'r1',
          'fare_pence': null,
          'waiting_pence': null,
          'total_pence': null,
          'currency': 'GBP',
          'status': 'pending',
        }));

    await tester.pumpWidget(_harness(api));
    await tester.pumpAndSettle();

    expect(find.text('£0.00'), findsNothing);
    expect(find.textContaining('Not yet charged'), findsWidgets);
  });

  testWidgets('a waiting charge line appears only when it is non-zero',
      (tester) async {
    when(() => api.get<Map<String, dynamic>>(any())).thenAnswer((_) async => const Ok({
          'ride_id': 'r1',
          'fare_pence': 1000,
          'waiting_pence': 250,
          'total_pence': 1250,
          'currency': 'GBP',
          'status': 'captured',
        }));

    await tester.pumpWidget(_harness(api));
    await tester.pumpAndSettle();

    expect(find.textContaining('Waiting'), findsOneWidget);
    expect(find.text('£2.50'), findsOneWidget);
  });

  testWidgets('no fare breakdown is fabricated - the receipt endpoint has none',
      (tester) async {
    when(() => api.get<Map<String, dynamic>>(any())).thenAnswer((_) async => const Ok({
          'ride_id': 'r1',
          'fare_pence': 1000,
          'waiting_pence': 0,
          'total_pence': 1000,
          'currency': 'GBP',
          'status': 'captured',
        }));

    await tester.pumpWidget(_harness(api));
    await tester.pumpAndSettle();

    expect(find.textContaining('Base Fare'), findsNothing);
    expect(find.textContaining('Surge'), findsNothing);
  });

  testWidgets('does not crash when timestamps are null', (tester) async {
    when(() => api.get<Map<String, dynamic>>(any())).thenAnswer((_) async => const Ok({
          'ride_id': 'r1',
          'fare_pence': 500,
          'total_pence': 500,
          'currency': 'GBP',
          'status': 'captured',
        }));

    await tester.pumpWidget(_harness(api));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('£5.00'), findsWidgets);
  });

  testWidgets('renders in dark mode', (tester) async {
    when(() => api.get<Map<String, dynamic>>(any())).thenAnswer((_) async => const Ok({
          'ride_id': 'r1',
          'fare_pence': 500,
          'total_pence': 500,
          'currency': 'GBP',
          'status': 'captured',
        }));

    await tester.pumpWidget(_harness(api, brightness: Brightness.dark));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('£5.00'), findsWidgets);
  });
}
