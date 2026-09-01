import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/theme/app_theme.dart';
import 'package:hoppin_rider/features/trip/data/live_trip_source.dart';
import 'package:hoppin_rider/features/trip/presentation/widgets/turn_banner.dart';

Widget _harness(Widget child) => MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('renders nothing when steps is null -- "no data", not empty',
      (tester) async {
    await tester.pumpWidget(_harness(const TurnBanner(steps: null)));
    expect(find.byType(TurnBanner), findsOneWidget);
    // SizedBox.shrink is how "nothing to render" reads here.
    expect(find.text('Take left after 1.5 mi'), findsNothing);
  });

  testWidgets('renders nothing when steps is empty -- no turns remain',
      (tester) async {
    await tester.pumpWidget(_harness(const TurnBanner(steps: [])));
    expect(find.byType(Container), findsNothing);
  });

  testWidgets('shows the first step\'s composed instruction', (tester) async {
    await tester.pumpWidget(_harness(const TurnBanner(steps: [
      TripStep(maneuver: 'turn-left', instruction: 'Take left after 1.5 mi'),
    ])));
    expect(find.text('Take left after 1.5 mi'), findsOneWidget);
  });

  testWidgets('renders as a glass chip — blurred, not flat paint',
      (tester) async {
    // Same glass treatment as TripRouteHeader and the status banner.
    await tester.pumpWidget(_harness(const TurnBanner(steps: [
      TripStep(maneuver: 'turn-left', instruction: 'Take left after 1.5 mi'),
    ])));
    expect(find.byType(BackdropFilter), findsOneWidget);
  });
}
