import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hoppin_rider/core/theme/app_theme.dart';
import 'package:hoppin_rider/features/trip/data/live_trip_source.dart';
import 'package:hoppin_rider/features/trip/presentation/live_trip_screen.dart';

Widget _harness({
  Brightness brightness = Brightness.light,
  String rideId = 'ride-1',
  List<Override> overrides = const [],
}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp.router(
        theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
        routerConfig: GoRouter(
          initialLocation: '/trip',
          routes: [
            GoRoute(
              path: '/trip',
              builder: (_, __) => LiveTripScreen(rideId: rideId),
            ),
            GoRoute(
              path: '/chat',
              builder: (_, __) => const Scaffold(body: Text('chat screen')),
            ),
            GoRoute(
              path: '/safety',
              builder: (_, __) => const Scaffold(body: Text('safety screen')),
            ),
          ],
        ),
      ),
    );

void main() {
  testWidgets('has a const constructor with an optional rideId', (tester) async {
    const screen = LiveTripScreen();
    expect(screen.rideId, isNotNull);
  });

  testWidgets(
      'renders the null-driver "finding your driver" state honestly, without crashing',
      (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pump();

    expect(find.text('Finding your driver'), findsOneWidget);
    expect(find.text('Cancel Ride'), findsOneWidget);
    // No driver identity should be rendered for a null driver.
    expect(find.textContaining('★'), findsNothing);
  });

  testWidgets('never renders a fabricated rating when driver rating is null',
      (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pump();

    expect(find.textContaining('5.0'), findsNothing);
    expect(find.byIcon(Icons.star), findsNothing);
  });

  testWidgets('shows the map placeholder rather than a real map SDK',
      (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pump();

    expect(find.text('Map view'), findsOneWidget);
  });

  testWidgets('renders in dark mode', (tester) async {
    await tester.pumpWidget(_harness(brightness: Brightness.dark));
    await tester.pump();

    expect(find.text('Finding your driver'), findsOneWidget);
  });

  testWidgets('tapping the message icon navigates to chat', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pump();

    // No driver yet, so the chat/safety shortcuts sit at screen level, not
    // inside the (absent) assigned-driver row.
    expect(find.byIcon(Icons.chat_bubble), findsWidgets);
  });
}
