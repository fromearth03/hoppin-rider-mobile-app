import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_demo/hoppin_demo.dart';
import 'package:hoppin_rider/app.dart';
import 'package:hoppin_rider/features/booking/booking_builder.dart';
import 'package:hoppin_rider/features/shell/rider_shell.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

/// DEMO-01 + DEMO-05 acceptance for the rider app.
///
/// Boots the exact composition `main_demo.dart` assembles — a seeded
/// [DemoWorld] under [riderDemoOverrides] wrapping the production
/// [RiderApp] — with ZERO backend: no env config, no network, no
/// dart-defines. The demo beat under test: boot lands on the
/// production-identical login with credentials prefilled, and ONE tap on
/// Sign in puts Sophie Bell on the home screen.
void main() {
  testWidgets(
      'demo boot: prefilled production login, one tap lands on the shell',
      (tester) async {
    // Same construction as main_demo.dart, with the test-safe store.
    final world = DemoWorld.riderScenario(
      seed: DemoSeed.seed,
      store: InMemorySnapshotStore(),
    )..restoreOrSeed();

    await tester.pumpWidget(ProviderScope(
      overrides: riderDemoOverrides(world),
      child: const RiderApp(),
    ));
    await tester.pump();

    // Signed out, so the router redirected '/' -> /login. The login screen
    // is production-identical: normal branding, normal Sign in button.
    expect(find.text('Hoppin'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);

    // Prefill (DEMO-05): both fields carry the seeded rider credentials.
    // Read the controllers — the password renders obscured, never literally.
    final fields =
        tester.widgetList<TextFormField>(find.byType(TextFormField)).toList();
    expect(fields, hasLength(2));
    expect(fields[0].controller!.text, DemoSeed.riderCredentials.email);
    expect(fields[1].controller!.text, DemoSeed.riderCredentials.password);

    // ONE tap, zero typing.
    await tester.tap(find.widgetWithText(HopButton, 'Sign in'));

    // Bounded pumps (not pumpAndSettle): the Book branch watches async
    // providers (history, saved locations) served by the fakes, and the demo
    // world may hold timers that would stall settle-detection.
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }

    // The demo auth stream emitted signedIn -> router redirect -> the 4-tab
    // shell, landing on the Book branch (the old HomeScreen hub is superseded
    // by the Book tab under the 08-03 shell).
    expect(find.byType(RiderShell), findsOneWidget);
    expect(find.byType(BookingFlow), findsOneWidget);
    expect(world.signedIn, isTrue);
  });
}
