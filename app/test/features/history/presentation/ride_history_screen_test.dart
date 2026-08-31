import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/theme/app_theme.dart';
import 'package:hoppin_rider/features/history/presentation/ride_history_screen.dart';

Widget _harness({Brightness brightness = Brightness.light}) => ProviderScope(
      child: MaterialApp(
        theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
        home: const RideHistoryScreen(),
      ),
    );

void main() {
  // There is no list-rides call anywhere in the repository layer -
  // GET /api/v1/rides is recorded in the design docs as a milestone 2
  // contract with no endpoint wired yet. This screen must not fabricate a
  // ride list to fill the design; it must say plainly that history is coming.

  testWidgets('shows the Ride History title with a back arrow', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    expect(find.text('Ride History'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
  });

  testWidgets('does not fabricate any ride rows', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    // The design's sample data - must never appear as if it were real.
    expect(find.textContaining('Wolverhampton'), findsNothing);
    expect(find.textContaining('£ 03.86'), findsNothing);
  });

  testWidgets('explains history arrives in a future milestone', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    expect(find.textContaining('coming soon'), findsOneWidget);
  });

  testWidgets('renders in dark mode', (tester) async {
    await tester.pumpWidget(_harness(brightness: Brightness.dark));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Ride History'), findsOneWidget);
  });
}
