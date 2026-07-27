import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/features/history/history_screen.dart';
import 'package:hoppin_rider/theme.dart';
import 'package:hoppin_shared/hoppin_shared.dart';

void main() {
  test('themes build with both brightnesses', () {
    expect(hoppinLightTheme.colorScheme.brightness, Brightness.light);
    expect(hoppinDarkTheme.colorScheme.brightness, Brightness.dark);
  });

  testWidgets('RideRow renders a completed ride with its status pill and '
      'graceful fallbacks', (tester) async {
    final ride = Ride(
      id: 'ride-1',
      riderId: 'rider-1',
      rideCategory: 'standard',
      status: RideStatus.completed,
      createdAt: DateTime(2026, 7, 5, 17, 42),
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: hoppinLightTheme,
          home: Scaffold(body: RideRow(ride: ride)),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    // No seam data and no transaction row: the generic title, the short
    // date, the status pill — and never a crash.
    expect(find.text('Ride'), findsOneWidget);
    expect(find.text(formatShortDateTime(ride.createdAt!)), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
  });

  testWidgets('StatusBanner shows its message', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StatusBanner.error(message: 'Something failed'),
        ),
      ),
    );
    expect(find.text('Something failed'), findsOneWidget);
  });
}
