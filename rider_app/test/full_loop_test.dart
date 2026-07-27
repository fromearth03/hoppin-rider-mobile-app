import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_demo/hoppin_demo.dart';
import 'package:hoppin_rider/app.dart';
import 'package:hoppin_rider/features/booking/booking_builder.dart';
import 'package:hoppin_rider/features/history/history_screen.dart';
import 'package:hoppin_rider/features/shell/rider_shell.dart';
import 'package:hoppin_rider/features/trip/map/map_builder.dart';
import 'package:hoppin_rider/features/trip/map/map_interactor.dart';
import 'package:hoppin_rider/features/trip/map/map_state.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

import 'support/tile_http_fakes.dart';

/// RIDER-01 acceptance: the FULL rider loop plays green in ONE automated
/// test on the exact composition `main_demo.dart` assembles — a seeded
/// [DemoWorld] under [riderDemoOverrides] wrapping the production
/// [RiderApp], zero backend, bounded pumps only (~210s of scripted time).
///
/// The beats map 1:1 onto the requirement text:
/// login → home → book → estimate (£6.39, Fixed price) → HOPPIN20 →
/// request → staged matching → matched (BK72 WNH, ticking ETA) → arriving →
/// meet → on-road strip with word waypoints → completion bloom → rating →
/// receipt with the promo negative line → history top row.
void main() {
  // The Book Ride surface mounts a real HopMap band; serve its OSM tiles a
  // 1x1 PNG from memory so the full loop never issues tile HTTP.
  setUpAll(() => HttpOverrides.global = TileHttpOverrides());
  tearDownAll(() => HttpOverrides.global = null);

  testWidgets('full rider loop: login through history on demo data',
      (tester) async {
    // Same construction as main_demo.dart, with the test-safe store.
    final world = DemoWorld.riderScenario(
      seed: DemoSeed.seed,
      store: InMemorySnapshotStore(),
    )..restoreOrSeed();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        ...riderDemoOverrides(world),
        // Pin the map riblet to the hidden rung: this loop proves the trip
        // CONTENT beats in the map-less layout (MAP-03's live-mode rung) —
        // map-mode composition is proven in
        // test/features/trip/map/map_view_test.dart.
        mapInteractorProvider.overrideWith2((_) => _HiddenMapStub()),
      ],
      child: const RiderApp(),
    ));
    await tester.pump();

    // ── Beat 1: prefilled production login, ONE tap → the shell's Book tab
    // (the old HomeScreen hub is superseded by the Book tab under the 08-03
    // shell — sign-in lands straight on the booking surface).
    expect(find.text('Sign in'), findsOneWidget);
    await tester.tap(find.widgetWithText(HopButton, 'Sign in'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(find.byType(RiderShell), findsOneWidget);
    expect(find.byType(BookingFlow), findsOneWidget);

    // ── Beat 2: book a ride — the Book tab IS the booking surface, no hub
    // pill to open it any more.
    expect(find.text('Choose a pickup and destination to see your fare.'),
        findsOneWidget);

    await tester.tap(find.text('Choose pickup'));
    await _settleRoute(tester);
    await tester.scrollUntilVisible(
        find.text('Wolverhampton Rail Station'), 120,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Wolverhampton Rail Station'));
    await _settleRoute(tester);

    await tester.tap(find.text('Choose destination'));
    await _settleRoute(tester);
    await tester.scrollUntilVisible(find.text('New Cross Hospital'), 120,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('New Cross Hospital'));
    await _settleRoute(tester);

    // ── Beat 3: the fare-estimate money moment ──────────────────────────
    await _pumpUntilFound(tester, find.text('£6.39'),
        maxPumps: 10, step: const Duration(milliseconds: 300));
    expect(find.text('£6.39'), findsOneWidget,
        reason: 'the FareEstimateCard total: scripted route prices at £6.39');

    // ── Beat 4: stage HOPPIN20 through the collapsed promo row ──────────
    // ensureVisible (not a bare scrollUntilVisible+tap): the shell's bottom
    // nav overlays the last ~56px of the branch viewport, so the promo row
    // must be lifted clear of it before the tap can land.
    await tester.scrollUntilVisible(find.text('Add promo code'), 120,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.text('Add promo code'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Add promo code'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byType(TextField), 'HOPPIN20');
    await tester.tap(find.text('Apply'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('HOPPIN20 · will be applied to this trip'),
        findsOneWidget);

    // ── Beat 5: request → the staged matching beat ──────────────────────
    // The Figma CTA is the "Confirm Booking" HopButton (was "Request ride").
    final confirm = find.widgetWithText(HopButton, 'Confirm Booking');
    await tester.scrollUntilVisible(confirm, 120,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(confirm);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(confirm);
    await _settleRoute(tester);
    expect(find.byType(RadarPulse), findsOneWidget,
        reason: 'the 4.2s scripted wait must never be a lone spinner');
    expect(find.text('Contacting drivers nearby…'), findsOneWidget);

    // Wall-clock staged copy advances at 2.5s.
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('A driver is reviewing your request…'), findsOneWidget);

    // ── Beat 6: matched → the plate-first identity card + ticking ETA ───
    // Match at 4.2s; the booking id-diff poll discovers it at ~6s and the
    // navigation host hands over to /trip/:id.
    await _pumpUntilFound(tester, find.text('BK72 WNH'),
        maxPumps: 12, step: const Duration(seconds: 1));
    expect(find.text('Gurpreet is on the way'), findsOneWidget);
    expect(find.text('BK72 WNH'), findsOneWidget);

    final etaFinder = find.byWidgetPredicate((w) =>
        w is Text && w.data != null && RegExp(r'^\d+:\d\d$').hasMatch(w.data!));
    expect(etaFinder, findsOneWidget,
        reason: 'the mm:ss ETA hero must be on screen');
    final etaBefore = tester.widget<Text>(etaFinder).data!;
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    final etaAfter = tester.widget<Text>(etaFinder).data!;
    expect(etaAfter, isNot(etaBefore),
        reason: 'the ETA hero visibly ticks across two 1s pumps');

    // ── Beat 7: ETA floors → arriving → meet → on-road strip ────────────
    await _pumpUntilFound(tester, find.text('Arriving now'),
        maxPumps: 130, step: const Duration(seconds: 1));
    await _pumpUntilFound(tester, find.text('Gurpreet is here'),
        maxPumps: 12, step: const Duration(seconds: 1));
    await _pumpUntilFound(
        tester, find.text('On your way to New Cross Hospital'),
        maxPumps: 12, step: const Duration(seconds: 1));
    expect(find.byType(RouteStrip), findsOneWidget,
        reason: 'the map-less centrepiece fills through the trip');

    // ~40s in: the journey narrates itself in Wolverhampton words.
    await _pumpUntilFound(tester, find.text('Along Wednesfield Road'),
        maxPumps: 45, step: const Duration(seconds: 1));

    // ── Beat 8: completion bloom → paid line → rating sheet ─────────────
    // The scripted in-trip window is 75s; the waypoint beat above returns
    // as soon as the word lands (~22s in), so budget the full remainder.
    await _pumpUntilFound(
        tester, find.text("You've arrived at New Cross Hospital"),
        maxPumps: 90, step: const Duration(seconds: 1));
    expect(find.textContaining('· paid'), findsOneWidget,
        reason: 'money reassurance rides the completion moment');

    // The sheet slides up AFTER the moment (~1.2s beat), never over it.
    final ratingTitle = find.text('How was your trip with Gurpreet?');
    await _pumpUntilFound(tester, ratingTitle,
        maxPumps: 10, step: const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byIcon(Icons.star_border).at(4)); // 5 stars
    await tester.pump(const Duration(milliseconds: 200));
    await tester.ensureVisible(find.text('Submit rating'));
    await tester.tap(find.text('Submit rating'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Thanks for the feedback!'), findsOneWidget);
    expect(world.eventLog.any((e) => e.contains('rideRated')), isTrue);

    // Let the snack clear before driving on.
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 400));

    // ── Beat 9: the receipt — the promo is VISIBLE right here ───────────
    await tester.ensureVisible(find.text('View receipt'));
    await tester.tap(find.text('View receipt'));
    await _settleRoute(tester);
    await _pumpUntilFound(tester, find.text('Fare'),
        maxPumps: 8, step: const Duration(milliseconds: 300));

    expect(find.text('£6.39'), findsOneWidget,
        reason: 'fare = the pre-discount estimate, unchanged by the promo');
    expect(find.text('Promo applied'), findsOneWidget);
    expect(find.text('−£1.28'), findsOneWidget,
        reason: 'HOPPIN20 renders as a pence-exact negative line');
    expect(find.text('£5.11'), findsOneWidget,
        reason: 'the bold total is the discounted charge');
    final strip = tester.widget<RouteStrip>(find.byType(RouteStrip));
    expect(strip.complete, isTrue,
        reason: 'the completed strip reappears for continuity');
    expect(strip.destinationLabel, 'New Cross Hospital');

    // ── Beat 10: history — the ride lands on top with its price ─────────
    await tester.scrollUntilVisible(find.text('Done'), 120,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.text('Done'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('Done'));
    await _settleRoute(tester);
    // 'Done' fires TripNavIntent.home → the Book tab under the shell.
    expect(find.byType(RiderShell), findsOneWidget);
    expect(find.byType(BookingFlow), findsOneWidget);

    // History is now a bottom-nav tab — reach it through the real HopBottomNav
    // (its History glyph), not the old HomeScreen "See all" affordance.
    await tester.tap(find.descendant(
      of: find.byKey(RiderShellKeys.bottomNav),
      matching: find.byIcon(HopBottomNav.defaultItems[1].icon),
    ));
    await _settleRoute(tester);
    expect(find.byType(HistoryScreen), findsOneWidget);
    final firstRow = find.byType(RideRow).first;
    expect(
        find.descendant(
            of: firstRow, matching: find.text('New Cross Hospital')),
        findsOneWidget,
        reason: 'the just-completed ride sits at the top of history');
    expect(find.descendant(of: firstRow, matching: find.text('£5.11')),
        findsOneWidget,
        reason: 'the row carries the discounted price actually charged');
    expect(find.descendant(of: firstRow, matching: find.text('Completed')),
        findsOneWidget);

    // Teardown: unmount the app, then reset the world INSIDE the test body
    // so no scripted timer outlives the run (flutter_test invariant).
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    world.reset();
  });
}

/// Settles a route transition with bounded pumps: this Flutter's M3 default
/// page transition (FadeForwards) runs 800ms, so a lone 400ms pump leaves
/// the barrier of the outgoing route eating taps mid-flight.
Future<void> _settleRoute(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 350));
  }
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxPumps = 40,
  Duration step = const Duration(milliseconds: 500),
}) async {
  for (var i = 0; i < maxPumps; i++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(step);
  }
  fail('Timed out waiting for $finder after $maxPumps pumps');
}

/// A map riblet pinned to the hidden rung — no seam poll, no timers.
class _HiddenMapStub extends MapInteractor {
  _HiddenMapStub() : super('stub');

  @override
  MapState build() => const MapState();
}
