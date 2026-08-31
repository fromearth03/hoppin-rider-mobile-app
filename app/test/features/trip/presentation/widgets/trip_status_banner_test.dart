import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/theme/app_theme.dart';
import 'package:hoppin_rider/features/trip/data/live_trip_source.dart';
import 'package:hoppin_rider/features/trip/presentation/widgets/trip_status_banner.dart';

Widget _harness(Widget child, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('matching reads as finding a driver, not "waiting"',
      (tester) async {
    await tester.pumpWidget(
      _harness(const TripStatusBanner(status: LiveTripStatus.matching)),
    );
    expect(find.textContaining('Finding'), findsOneWidget);
  });

  testWidgets(
      'matching banner copy is distinct from the driver card\'s "Finding your driver" title',
      (tester) async {
    // Both sit on screen together while matching -- identical copy in two
    // places would read as a rendering glitch rather than one coherent state.
    await tester.pumpWidget(
      _harness(const TripStatusBanner(status: LiveTripStatus.matching)),
    );
    expect(find.text('Finding your driver'), findsNothing);
  });

  testWidgets('arriving shows "Driver is Waiting for You" per the design',
      (tester) async {
    await tester.pumpWidget(
      _harness(const TripStatusBanner(status: LiveTripStatus.arriving)),
    );
    expect(find.text('Driver is Waiting for You'), findsOneWidget);
  });

  testWidgets('started shows the active-ride banner', (tester) async {
    await tester.pumpWidget(
      _harness(const TripStatusBanner(status: LiveTripStatus.started)),
    );
    expect(find.textContaining('Active Ride'), findsOneWidget);
  });

  testWidgets('renders in dark mode', (tester) async {
    await tester.pumpWidget(_harness(
      const TripStatusBanner(status: LiveTripStatus.arriving),
      brightness: Brightness.dark,
    ));
    expect(find.text('Driver is Waiting for You'), findsOneWidget);
  });
}
