import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3 exports the Override type from misc.dart, not the main barrel.
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hoppin_demo/hoppin_demo.dart';
import 'package:hoppin_rider/features/auth/otp_verify_screen.dart';
import 'package:hoppin_rider/features/booking/booking_builder.dart';
import 'package:hoppin_rider/features/booking/booking_state.dart';
import 'package:hoppin_rider/features/booking/place.dart';
import 'package:hoppin_rider/features/booking/widgets/fare_panel.dart';
import 'package:hoppin_rider/features/booking/widgets/fee_disclosure.dart';
import 'package:hoppin_rider/features/booking/widgets/matching_rung.dart';
import 'package:hoppin_rider/features/booking/widgets/multistop_unavailable_notice.dart';
import 'package:hoppin_rider/features/booking/widgets/ride_type_selector.dart';
import 'package:hoppin_rider/features/booking/widgets/service_unavailable_screen.dart';
import 'package:hoppin_rider/features/trip/trip_handoff.dart';
import 'package:hoppin_rider/features/trip/widgets/seam_unavailable_states.dart';
import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

import 'support/tile_http_fakes.dart';

/// View layer (riblet testing contract, DOCS/05) for the booking riblet.
///
/// The fare-panel group pins the money moment: the GBP total as the
/// typographic hero, the estimate-range framing, the schematic journey
/// header, progressive-disclosure breakdown, and the promo code as a
/// collapsed row that never shouts at full-price customers.
///
/// The booking-flow group pins the staged matching beat (RadarPulse +
/// advancing human copy + persistent cancel), the router handover to
/// /trip/:id, the skippable cancel survey, and the designed failure state —
/// the full composition under riderDemoOverrides with bounded pumps.
void main() {
  // The Book Ride surface now mounts a real HopMap band; serve its OSM tiles
  // a 1x1 PNG from memory so the full-composition flow tests never issue tile
  // HTTP (the isolation gate forbids importing maplibre_gl into apps/rider).
  setUpAll(() => HttpOverrides.global = TileHttpOverrides());
  tearDownAll(() => HttpOverrides.global = null);

  group('FarePanel money moment', () {
    testWidgets('GBP total is the typographic hero', (tester) async {
      await tester.pumpWidget(_panelHarness(estimate: _scriptedEstimate));

      final total = formatPounds(_scriptedEstimate.estimate.total);
      expect(total, '£6.39');
      expect(find.text(total), findsOneWidget);

      final heroSize =
          tester.widget<Text>(find.text(total)).style?.fontSize ?? 0;
      final allTexts = tester.widgetList<Text>(
        find.descendant(
          of: find.byType(FarePanel),
          matching: find.byType(Text),
        ),
      );
      for (final text in allTexts) {
        if (text.data == total) continue;
        final size = text.style?.fontSize ?? 14;
        expect(
          heroSize,
          greaterThan(size),
          reason:
              '"${text.data}" ($size) must sit below the £ hero '
              '($heroSize) — the GBP figure IS the screen',
        );
      }
    });

    testWidgets('estimate-range framing present (BOOK-05)', (tester) async {
      await tester.pumpWidget(_panelHarness(estimate: _scriptedEstimate));
      // The total reads as an honest estimate that settles at drop-off, not
      // a silent fixed number (§3.4 reconciliation).
      expect(find.text('Estimated'), findsOneWidget);
      expect(
        find.text('Estimated — final fare settled at drop-off'),
        findsOneWidget,
      );
    });

    testWidgets('journey header shows the schematic route with distance and '
        'minutes', (tester) async {
      await tester.pumpWidget(_panelHarness(estimate: _scriptedEstimate));

      expect(find.text('Wolverhampton Rail Station'), findsOneWidget);
      expect(find.text('New Cross Hospital'), findsOneWidget);

      final miles = (_scriptedEstimate.distanceMeters / 1609.344)
          .toStringAsFixed(1);
      final mins = (_scriptedEstimate.durationSeconds / 60).round();
      expect(find.text('$miles mi · about $mins min'), findsOneWidget);
    });

    testWidgets('breakdown is progressive disclosure behind the chevron', (
      tester,
    ) async {
      await tester.pumpWidget(_panelHarness(estimate: _scriptedEstimate));
      final q = _scriptedEstimate.estimate;

      // Collapsed by default: no component rows shout at the rider.
      expect(find.text('Fare breakdown'), findsOneWidget);
      expect(find.text('Base fare'), findsNothing);
      expect(find.text('Distance'), findsNothing);
      expect(find.text('Time'), findsNothing);
      expect(find.text('Service fee'), findsNothing);

      await tester.tap(find.text('Fare breakdown'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Base fare'), findsOneWidget);
      expect(find.text(formatPounds(q.base)), findsOneWidget);
      expect(find.text('Distance'), findsOneWidget);
      expect(find.text(formatPounds(q.distance)), findsOneWidget);
      expect(find.text('Time'), findsOneWidget);
      expect(find.text(formatPounds(q.time)), findsOneWidget);
      expect(find.text('Service fee'), findsOneWidget);
      expect(find.text(formatPounds(q.serviceFee)), findsOneWidget);

      // This route clears the minimum — no note.
      expect(find.text('Minimum fare applied'), findsNothing);
    });

    testWidgets('minimum fare note appears when the floor kicks in', (
      tester,
    ) async {
      // A tiny hop: gross under £5.00, so the minimum floor applies.
      final short = estimateBetween(
        pickupLat: 52.5870,
        pickupLng: -2.1288,
        dropoffLat: 52.5877,
        dropoffLng: -2.1200,
      );
      expect(short.estimate.total, greaterThan(short.estimate.gross));

      await tester.pumpWidget(_panelHarness(estimate: short));
      await tester.tap(find.text('Fare breakdown'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Minimum fare applied'), findsOneWidget);
    });

    testWidgets('promo is a collapsed row: never an open field, normalises '
        'to upper-case, stages a chip', (tester) async {
      String? staged;
      await tester.pumpWidget(
        _statefulPanelHarness(
          estimate: _scriptedEstimate,
          onChanged: (code) => staged = code,
        ),
      );

      // Baymard rule: the field NEVER renders pre-opened.
      expect(find.text('Add promo code'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);

      await tester.tap(find.text('Add promo code'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(TextField), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'hoppin20');
      await tester.tap(find.text('Apply'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(staged, 'HOPPIN20');
      expect(
        find.text('HOPPIN20 · will be applied to this trip'),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsNothing);

      // Tap-to-remove takes the staged chip away again.
      await tester.tap(find.byTooltip('Remove promo code'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(staged, isNull);
      expect(find.text('Add promo code'), findsOneWidget);
    });

    testWidgets('a rejected code shows its error under the promo row', (
      tester,
    ) async {
      await tester.pumpWidget(
        _statefulPanelHarness(
          estimate: _scriptedEstimate,
          onChanged: (_) {},
          promoError: "'BOGUS99' isn't a valid promo code.",
        ),
      );

      expect(
        find.text("'BOGUS99' isn't a valid promo code."),
        findsOneWidget,
        reason: 'entry-time rejection must be visible, never silent',
      );
      final errorText = tester
          .widget<Text>(find.text("'BOGUS99' isn't a valid promo code."));
      final colors = _light.extension<HoppinColors>()!;
      expect(errorText.style?.color, colors.error);
    });
  });

  group('Booking flow', () {
    testWidgets('matching state is alive: radar, staged copy, persistent '
        'cancel', (tester) async {
      final h = await _bootFlow(tester);
      await _driveToSearching(tester, h);

      expect(find.byType(RadarPulse), findsOneWidget);
      expect(find.text('Contacting drivers nearby…'), findsOneWidget);
      expect(find.text('Usually under a minute'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      // The stage-1 line lands on the 3s wall-clock tick (threshold 2.5s);
      // the scripted ride row is not discoverable before ~3.6s, so the beat
      // is still searching.
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 250)); // switcher fade
      expect(find.text('A driver is reviewing your request…'), findsOneWidget);
      expect(find.byType(RadarPulse), findsOneWidget);
      expect(
        find.text('Cancel'),
        findsOneWidget,
        reason: 'the cancel affordance must never blink away',
      );

      await _cleanupFlow(tester, h);
    });

    testWidgets('matched navigates once to the trip and resets the booking', (
      tester,
    ) async {
      final h = await _bootFlow(tester);
      await _driveToSearching(tester, h);

      // The scripted match lands at ~4.2s; the 3s poll cadence discovers it
      // on the second poll (~6s). Bounded pumps, never settle.
      await _pumpUntilFound(tester, find.text('trip-stub'), maxPumps: 30);

      expect(find.text('trip-stub'), findsOneWidget);
      final booking = h.container.read(bookingInteractorProvider);
      expect(
        booking.phase,
        BookingPhase.idle,
        reason: 'the router resets the flow after handover',
      );
      expect(booking.estimate, isNull);

      final handoff = h.container.read(tripHandoffProvider);
      expect(
        handoff,
        isNotNull,
        reason: 'the handoff is written before matched flips',
      );
      expect(handoff!.fareTotalPounds, 6.39);

      await _cleanupFlow(tester, h);
    });

    testWidgets('search cancel is a designed exit: skippable survey, then '
        'back on the estimate', (tester) async {
      final h = await _bootFlow(tester);
      await _driveToSearching(tester, h);

      await tester.tap(find.text('Cancel'));
      await tester.pump(); // sheet route install (04-03 choreography note)
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Changed my mind'), findsOneWidget);
      expect(find.text('Waiting too long'), findsOneWidget);
      expect(find.text('Booked by mistake'), findsOneWidget);
      expect(find.text('Driver asked me to cancel'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);

      await tester.tap(find.text('Skip'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      // No dead end: places + fare intact, request ready to go again.
      expect(find.byType(RadarPulse), findsNothing);
      expect(find.text('£6.39'), findsOneWidget);
      expect(
        find.widgetWithText(HopButton, 'Confirm Booking'),
        findsOneWidget,
      );

      await _cleanupFlow(tester, h);
    });

    testWidgets('failure state explains and offers retry', (tester) async {
      // A request-time transport failure (not a dispatch-exhaustion) keeps the
      // genuine designed `failed` card + "Try again". Dispatch-exhaustion now
      // leads with the BOOK-08 retry rung instead (covered separately below).
      final h = await _bootFlow(
        tester,
        overrides: [
          ridesRepositoryProvider.overrideWithValue(_RequestErrorRepo()),
        ],
      );
      h.container.read(bookingInteractorProvider.notifier)
        ..setPickup(_railStation)
        ..setDropoff(_newCross);
      await _pumpUntilFound(tester, find.text('£6.39'));
      final confirm = find.widgetWithText(HopButton, 'Confirm Booking');
      await tester.ensureVisible(confirm);
      await tester.pump();
      await tester.tap(confirm);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));

      // The designed failure card explains and offers a retry.
      expect(find.text("We couldn't get you moving"), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);

      final tryAgain = find.text('Try again');
      await tester.ensureVisible(tryAgain);
      await tester.pump();
      await tester.tap(tryAgain);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));
      // Retry re-estimates — the failure state is navigable. Assert the
      // re-estimate landed on the interactor (the FareEstimateCard may sit
      // below the ListView cache extent after scrolling to the failure card).
      expect(
        h.container.read(bookingInteractorProvider).phase,
        BookingPhase.estimated,
        reason: 'retry re-estimates — the failure state is navigable',
      );

      await _cleanupFlow(tester, h);
    });
  });

  // ── Convergence: verify-wall + geofence pre-flight (09-05) ───────────────
  //
  // These pin the two lanes 09-05 wires onto the booking action:
  //   • AUTH-02 — an unverified Book tap (server 403 ACCOUNT_NOT_ELIGIBLE)
  //     routes to the OTP verify wall, NOT a dead-end `failed` message;
  //   • BOOK-07 — a pickup outside the service area shows the designed
  //     ServiceUnavailableScreen BEFORE any network request fires.
  // Decision A: only the booking request is blocked — the rest of the app
  // stays usable, so neither rung is a global lock.
  group('Booking convergence — verify-wall + geofence', () {
    testWidgets('403 ACCOUNT_NOT_ELIGIBLE routes to the verify wall, not a '
        'dead-end failure (AUTH-02)', (tester) async {
      final repo = _EligibilityGateRepo();
      final h = await _bootFlow(
        tester,
        overrides: [ridesRepositoryProvider.overrideWithValue(repo)],
      );
      h.container.read(bookingInteractorProvider.notifier)
        ..setPickup(_railStation)
        ..setDropoff(_newCross);
      await _pumpUntilFound(tester, find.text('£6.39'));

      final confirm = find.widgetWithText(HopButton, 'Confirm Booking');
      await tester.ensureVisible(confirm);
      await tester.pump();
      await tester.tap(confirm);
      // Route-crossing to the verify wall: pump() + 3×350ms (M3 fade).
      await tester.pump();
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 350));
      }

      // The hard wall: the OTP verify screen is shown, NOT the failure card.
      expect(find.byType(OtpVerifyScreen), findsOneWidget);
      expect(find.text("We couldn't get you moving"), findsNothing);
      expect(
        h.container.read(bookingInteractorProvider).phase,
        BookingPhase.needsVerification,
        reason: '403 is a verify gate, never a bare failure',
      );

      await _cleanupFlow(tester, h);
    });

    testWidgets('outside-area pickup shows ServiceUnavailableScreen BEFORE any '
        'request, and never dead-ends (BOOK-07)', (tester) async {
      final repo = _RecordingRequestRepo();
      final h = await _bootFlow(
        tester,
        overrides: [ridesRepositoryProvider.overrideWithValue(repo)],
      );
      // A Birmingham pickup is outside the Wolverhampton boundary.
      h.container.read(bookingInteractorProvider.notifier)
        ..setPickup(_outsidePickup)
        ..setDropoff(_newCross);
      // Wait for the estimate to land — the phase reaching `estimated` is the
      // "Confirm Booking is now enabled" signal (the CTA is always in the tree,
      // so pump on the interactor state, not the widget).
      for (var i = 0; i < 40; i++) {
        if (h.container.read(bookingInteractorProvider).phase ==
            BookingPhase.estimated) {
          break;
        }
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        h.container.read(bookingInteractorProvider).phase,
        BookingPhase.estimated,
        reason: 'estimate must land before the Book tap',
      );

      final confirm = find.widgetWithText(HopButton, 'Confirm Booking');
      await tester.ensureVisible(confirm);
      await tester.pump();
      await tester.tap(confirm);
      await tester.pump();
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 350));
      }

      // The designed outside-area state renders, and NO request was sent.
      expect(find.byType(ServiceUnavailableScreen), findsOneWidget);
      expect(
        repo.requestCount,
        0,
        reason: 'the geofence pre-flight fast-fails before the network call',
      );
      expect(
        h.container.read(bookingInteractorProvider).phase,
        BookingPhase.outsideArea,
      );

      // Not a dead end (decision A): the exit affordance returns to a usable
      // booking surface where locations can be re-picked.
      final back = find.text('Back');
      await tester.ensureVisible(back);
      await tester.pump();
      await tester.tap(back);
      await tester.pump();
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 350));
      }
      expect(find.byType(ServiceUnavailableScreen), findsNothing);

      await _cleanupFlow(tester, h);
    });
  });

  // ── Convergence (10-05): the single booking_view integration edit ────────
  //
  // These pin the three Wave-1 surfaces mounted into the booking confirm /
  // searching path by the convergence lane:
  //   • BOOK-02 — the RideTypeSelector (Lane A) is mounted pre-confirm and
  //     selecting XL re-estimates through the interactor (end-to-end);
  //   • CANCEL-01 — the FeeDisclosure (Lane D) is mounted pre-confirm and shows
  //     the stub penalty figures BEFORE the "Confirm Booking" button (§4.1);
  //   • BOOK-08 — a dispatch-exhausted state renders the MatchingRung ("finding
  //     another driver") instead of a dead-end "Try again", exit still reachable.
  group('Booking convergence — mounted selector + fee-disclosure + retry rung',
      () {
    // WAVE-0 REWRITE (2026-07-12). This test used to assert that tapping XL
    // "re-estimates with the XL vehicleCategoryId" — and it hardcoded the
    // fabricated uuid `00000000-0000-4000-8000-0000000000d2` as the expected
    // value. That uuid is not in the database. The test was green, and what it
    // was proving is that the app confidently sent the server a category id the
    // server has never seen. It encoded the bug as the contract.
    //
    // The honest contract, until `GET /vehicle-categories` (#65) ships: XL and
    // Accessibility are REAL PRODUCTS and stay VISIBLE, but they are NOT
    // BOOKABLE, because we cannot name them to the server. Accessibility makes
    // this safety-critical — a wheelchair user must get a wheelchair-accessible
    // vehicle or be told plainly they cannot book one here yet.
    testWidgets(
        'RideTypeSelector is mounted pre-confirm; XL and Accessibility are '
        'VISIBLE but NOT selectable, and the seam is disclosed (BOOK-02, #65)',
        (tester) async {
      final repo = _RecordingCategoryRepo();
      final h = await _bootFlow(
        tester,
        overrides: [ridesRepositoryProvider.overrideWithValue(repo)],
      );
      h.container.read(bookingInteractorProvider.notifier)
        ..setPickup(_railStation)
        ..setDropoff(_newCross);
      await _pumpUntilFound(tester, find.text('£6.39'),
          step: const Duration(milliseconds: 100));

      // The Lane-A selector is mounted (not the old local 4-card grid).
      expect(find.byType(RideTypeSelector), findsOneWidget);
      // The unbookable classes still RENDER — hiding them would misrepresent
      // the service; they are real products, just not orderable today.
      expect(find.text('XL'), findsOneWidget);
      expect(find.text('Accessibility'), findsOneWidget);
      // The old local grid's Estate/MPV/Minibus labels are GONE.
      expect(find.text('Estate'), findsNothing);
      expect(find.text('Minibus'), findsNothing);

      // The seam is DISCLOSED — the rider is told why, in their terms.
      // (Scoped to the ride-type disclosure: the multi-stop deferral notice,
      // seam #59, also says "coming soon" on this screen — both are correct
      // disclosures, so match the one under test rather than the phrase.)
      expect(
        find.textContaining('you can book Standard today'),
        findsOneWidget,
        reason: 'the #65 seam must disclose that XL/Accessibility cannot be '
            'booked yet — never silently accept a selection we cannot honour',
      );

      final before = repo.lastEstimateCategory;
      await tester.ensureVisible(find.text('XL'));
      await tester.pump();
      await tester.tap(find.text('XL'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // Tapping XL does NOTHING: no selection, no estimate, and above all no
      // fabricated category id sent to the server.
      expect(
        repo.lastEstimateCategory,
        before,
        reason: 'an unbookable class must not trigger an estimate — the app '
            'has no real vehicle_category_id to send and must never invent one',
      );
      expect(
        h.container.read(bookingInteractorProvider).selectedCategory,
        isNull,
        reason: 'an unbookable class must never become the selected category',
      );

      // Standard IS bookable — it carries a null id, which the server resolves
      // to its own default. The booking flow itself is not broken.
      await tester.ensureVisible(find.text('Standard'));
      await tester.pump();
      await tester.tap(find.text('Standard'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        h.container.read(bookingInteractorProvider).selectedCategory,
        isNull,
        reason: 'Standard is the server default (null id) and stays bookable',
      );

      await _cleanupFlow(tester, h);
    });

    testWidgets('FeeDisclosure is mounted pre-confirm and shows the stub '
        'penalty figures BEFORE the request button (CANCEL-01)', (tester) async {
      final h = await _bootFlow(tester);
      h.container.read(bookingInteractorProvider.notifier)
        ..setPickup(_railStation)
        ..setDropoff(_newCross);
      await _pumpUntilFound(tester, find.text('£6.39'),
          step: const Duration(milliseconds: 100));

      // The pre-booking fee disclosure surface is mounted with real figures.
      expect(find.byType(FeeDisclosure), findsOneWidget);
      // The number is the point — always shown (never a hidden "coming soon").
      expect(find.text('Free to cancel for 2 min, then £5.00'), findsOneWidget);

      // It sits BEFORE the "Confirm Booking" CTA (Scope Lock §4.1 — displayed
      // before booking): the disclosure's vertical position precedes the CTA.
      final disclosureY =
          tester.getTopLeft(find.byType(FeeDisclosure)).dy;
      final confirmY = tester
          .getTopLeft(find.widgetWithText(HopButton, 'Confirm Booking'))
          .dy;
      expect(disclosureY, lessThan(confirmY),
          reason: 'fee disclosure must render before the request button');

      await _cleanupFlow(tester, h);
    });

    testWidgets('dispatch-exhausted renders the MatchingRung retry state, not '
        'a dead-end "Try again"; a manual exit stays reachable (BOOK-08)',
        (tester) async {
      final h = await _bootFlow(
        tester,
        overrides: [
          ridesRepositoryProvider.overrideWithValue(_NoDriversRepo()),
        ],
      );
      h.container.read(bookingInteractorProvider.notifier)
        ..setPickup(_railStation)
        ..setDropoff(_newCross);
      await _pumpUntilFound(tester, find.text('£6.39'));
      final confirm = find.widgetWithText(HopButton, 'Confirm Booking');
      await tester.ensureVisible(confirm);
      await tester.pump();
      await tester.tap(confirm);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(RadarPulse), findsOneWidget);

      // The first poll (3s) discovers the server-side cancellation — the
      // dispatch-exhausted branch now leads with the retry rung, not the
      // terminal "Try again" failure card.
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.byType(MatchingRung), findsOneWidget);
      expect(find.text('Finding you another driver…'), findsOneWidget);
      // Never a dead-end terminal message on this branch.
      expect(find.text("We couldn't get you moving"), findsNothing);

      // The manual exit ("Cancel search") is reachable — the rider is never
      // trapped under the retry (decision 5).
      final exit = find.text('Cancel search');
      expect(exit, findsOneWidget);
      await tester.ensureVisible(exit);
      await tester.pump();
      await tester.tap(exit);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(MatchingRung), findsNothing);

      await _cleanupFlow(tester, h);
    });
  });

  // ── Wave 0: the two booking-surface disclosures are actually REACHABLE ────
  //
  // PromoUnavailableState (#46) and MultiStopUnavailableNotice (SL-11 / #59)
  // were both registered as designed unavailable-states and constructed by
  // ZERO production files — the ledger claimed disclosure, the rider saw
  // nothing. These pump the REAL booking view with the seam in its live
  // (null / absent) shape and assert the disclosure is on screen.
  group('Wave-0 seam disclosures mounted on their real degrade branches', () {
    testWidgets('#46: a promo staged against the LIVE seam (isPromoValid → '
        'null) mounts the designed "code saved" disclosure — the staged chip '
        'alone would read as a validation that never happened', (tester) async {
      final h = await _bootFlow(
        tester,
        overrides: [
          ridesRepositoryProvider.overrideWithValue(_LivePromoSeamRepo()),
        ],
      );
      h.container.read(bookingInteractorProvider.notifier)
        ..setPickup(_railStation)
        ..setDropoff(_newCross);
      await _pumpUntilFound(tester, find.text('£6.39'),
          step: const Duration(milliseconds: 100));

      // Nothing staged yet → nothing to disclose.
      expect(find.byType(PromoUnavailableState), findsNothing,
          reason: 'the disclosure must not pre-empt a promo entry');

      final addPromo = find.text('Add promo code');
      await tester.ensureVisible(addPromo);
      await tester.pump();
      await tester.tap(addPromo);
      await tester.pump(const Duration(milliseconds: 200));

      await tester.enterText(find.byType(TextField), 'hoppin20');
      await tester.tap(find.text('Apply'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));

      // The seam answered NOTHING, so the interactor staged the code without
      // any check. That fact is now on screen.
      expect(
        h.container.read(bookingInteractorProvider).promoUnvalidated,
        isTrue,
        reason: 'the live seam answers null — the code is staged UNVALIDATED',
      );
      final notice = find.byType(PromoUnavailableState);
      await tester.ensureVisible(notice);
      await tester.pump();
      expect(notice, findsOneWidget,
          reason: 'the rider must be told the code was only SAVED, not '
              'validated — never left to infer a tick from the staged chip');
      expect(tester.getSize(notice).height, greaterThan(0),
          reason: 'the disclosure is a real, visible surface');
      // The staging behaviour itself is untouched.
      expect(
        h.container.read(bookingInteractorProvider).pendingPromoCode,
        'HOPPIN20',
        reason: 'disclosing must not stop the code being staged for the match',
      );

      await _cleanupFlow(tester, h);
    });

    testWidgets('#46: a promo the seam DEFINITIVELY validated (demo, true) '
        'shows NO disclosure — the staged chip is honest there',
        (tester) async {
      final h = await _bootFlow(tester); // demo repo: isPromoValid → true
      h.container.read(bookingInteractorProvider.notifier)
        ..setPickup(_railStation)
        ..setDropoff(_newCross);
      await _pumpUntilFound(tester, find.text('£6.39'),
          step: const Duration(milliseconds: 100));

      final addPromo = find.text('Add promo code');
      await tester.ensureVisible(addPromo);
      await tester.pump();
      await tester.tap(addPromo);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.enterText(find.byType(TextField), DemoSeed.promoCode);
      await tester.tap(find.text('Apply'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        h.container.read(bookingInteractorProvider).promoUnvalidated,
        isFalse,
        reason: 'a definitive `true` really WAS a validation — nothing to '
            'disclose, and the flag must not be pinned on',
      );
      expect(find.byType(PromoUnavailableState), findsNothing,
          reason: 'the disclosure is driven by the REAL seam answer, never by '
              'a debug flag or an unconditional mount');

      await _cleanupFlow(tester, h);
    });

    testWidgets('SL-11 (#59): the multi-stop deferral is DISCLOSED where a '
        'rider reaches for "add stop" — under the From/To pair, not silently '
        'absent', (tester) async {
      final h = await _bootFlow(tester);
      await tester.pump(const Duration(milliseconds: 100));

      final notice = find.byType(MultiStopUnavailableNotice);
      expect(notice, findsOneWidget,
          reason: 'multi-stop is deferred (no waypoint contract) — the rider '
              'must be told it is coming, not left reading its absence as '
              '"this app cannot do it"');
      expect(tester.getSize(notice).height, greaterThan(0),
          reason: 'the disclosure is a real, visible surface');

      // It sits with the From/To pair (where the affordance would be), ABOVE
      // the Ride Type section — i.e. where a rider actually looks for it.
      final locationsY = tester.getBottomLeft(find.byType(LocationField)).dy;
      final noticeY = tester.getTopLeft(notice).dy;
      final rideTypeY = tester.getTopLeft(find.byType(RideTypeSelector)).dy;
      expect(noticeY, greaterThanOrEqualTo(locationsY),
          reason: 'the deferral belongs with the stop fields it is about');
      expect(noticeY, lessThan(rideTypeY),
          reason: 'it must precede Ride Type — the "add stop" moment comes '
              'before choosing a vehicle');

      // It is a disclosure marker, never a live waypoint editor.
      expect(find.text('Add stop'), findsNothing,
          reason: 'no fake affordance the backend cannot honour');

      await _cleanupFlow(tester, h);
    });
  });
}

/// The LIVE promo seam shape: `isPromoValid` answers `null` (no pre-ride
/// promo endpoint exists — gap #46), so a staged code is NEVER validated at
/// entry time. The exact branch the designed `PromoUnavailableState` discloses.
class _LivePromoSeamRepo implements RidesRepository {
  @override
  Future<bool?> isPromoValid(String promoCode) async => null;

  @override
  Future<FareEstimate> estimate({
    required double pickupLat,
    required double pickupLng,
    required double dropoffLat,
    required double dropoffLng,
    String? vehicleCategoryId,
  }) async {
    return estimateBetween(
      pickupLat: pickupLat,
      pickupLng: pickupLng,
      dropoffLat: dropoffLat,
      dropoffLng: dropoffLng,
    );
  }

  @override
  Future<List<Ride>> history({int limit = 50}) async => const <Ride>[];

  @override

  // In-area so the confirm-pickup geofence passes.
  @override
  Future<bool?> isServiceable(double lat, double lng) async => true;
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Records the vehicleCategoryId threaded into the most recent estimate so the
/// BOOK-02 selector→re-estimate wiring can be asserted end-to-end.
class _RecordingCategoryRepo implements RidesRepository {
  String? lastEstimateCategory;

  @override
  Future<FareEstimate> estimate({
    required double pickupLat,
    required double pickupLng,
    required double dropoffLat,
    required double dropoffLng,
    String? vehicleCategoryId,
  }) async {
    lastEstimateCategory = vehicleCategoryId;
    return estimateBetween(
      pickupLat: pickupLat,
      pickupLng: pickupLng,
      dropoffLat: dropoffLat,
      dropoffLng: dropoffLng,
    );
  }

  @override
  Future<List<Ride>> history({int limit = 50}) async => const <Ride>[];

  @override
  Future<String> requestRide({
    required double pickupLat,
    required double pickupLng,
    required double dropoffLat,
    required double dropoffLng,
    String? vehicleCategoryId,
  }) async =>
      'req-1';

  @override

  // In-area so the confirm-pickup geofence passes.
  @override
  Future<bool?> isServiceable(double lat, double lng) async => true;
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// One ThemeData reused across every pump — a fresh instance restarts
// AnimatedTheme + Material implicit animations (04-02 test-harness trap).
final _light = HoppinTheme.riderLight();

/// The scripted Rail Station → New Cross quote (£6.39) — the same maths as
/// the demo world.
final _scriptedEstimate = estimateBetween(
  pickupLat: 52.5877,
  pickupLng: -2.1200,
  dropoffLat: 52.6046,
  dropoffLng: -2.0930,
);

Widget _panelHarness({
  required FareEstimate estimate,
  String? pendingPromoCode,
  ValueChanged<String?>? onPromoChanged,
}) {
  return MaterialApp(
    theme: _light,
    home: Scaffold(
      body: SingleChildScrollView(
        child: FarePanel(
          estimate: estimate,
          pickupLabel: 'Wolverhampton Rail Station',
          destinationLabel: 'New Cross Hospital',
          pendingPromoCode: pendingPromoCode,
          onPromoChanged: onPromoChanged,
        ),
      ),
    ),
  );
}

/// Echoes the panel's promo events back into its own prop — the same wiring
/// the booking view gives it against the interactor.
Widget _statefulPanelHarness({
  required FareEstimate estimate,
  required ValueChanged<String?> onChanged,
  String? promoError,
}) {
  String? pending;
  return MaterialApp(
    theme: _light,
    home: Scaffold(
      body: StatefulBuilder(
        builder: (context, setState) => SingleChildScrollView(
          child: FarePanel(
            estimate: estimate,
            pickupLabel: 'Wolverhampton Rail Station',
            destinationLabel: 'New Cross Hospital',
            pendingPromoCode: pending,
            promoError: promoError,
            onPromoChanged: (code) {
              onChanged(code);
              setState(() => pending = code);
            },
          ),
        ),
      ),
    ),
  );
}

// ── Full-composition flow harness ─────────────────────────────────────────

const _railStation = Place(
  label: 'Wolverhampton Rail Station',
  lat: 52.5877,
  lng: -2.1200,
);
const _newCross = Place(
  label: 'New Cross Hospital',
  lat: 52.6046,
  lng: -2.0930,
);
// Birmingham city centre — outside the Wolverhampton licensing boundary but
// close enough for a normal fare estimate, so the client geofence pre-flight
// fast-fails at the Book tap (not at estimate time).
const _outsidePickup = Place(
  label: 'Birmingham City Centre',
  lat: 52.4796,
  lng: -1.9026,
);

class _FlowHarness {
  _FlowHarness({required this.world, required this.container});

  final DemoWorld world;
  final ProviderContainer container;
}

/// Pumps the booking riblet entry at /book inside a minimal test router —
/// stub leaf routes let the router handover be asserted without the full
/// app shell.
Future<_FlowHarness> _bootFlow(
  WidgetTester tester, {
  List<Override>? overrides,
}) async {
  final world = DemoWorld.riderScenario(
    seed: DemoSeed.seed,
    store: InMemorySnapshotStore(),
  )..restoreOrSeed();
  final container = ProviderContainer(
    overrides: overrides ?? riderDemoOverrides(world),
  );

  final router = GoRouter(
    initialLocation: '/book',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: Text('home-stub')),
      ),
      GoRoute(path: '/book', builder: (_, _) => const BookingFlow()),
      GoRoute(
        path: '/trip/:id',
        builder: (_, _) => const Scaffold(body: Text('trip-stub')),
      ),
    ],
  );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(theme: _light, routerConfig: router),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));

  return _FlowHarness(world: world, container: container);
}

/// Places chosen programmatically (the picker flow has its own screen),
/// estimate landed, request tapped — the matching beat on screen.
Future<void> _driveToSearching(WidgetTester tester, _FlowHarness h) async {
  h.container.read(bookingInteractorProvider.notifier)
    ..setPickup(_railStation)
    ..setDropoff(_newCross);
  // The FareEstimateCard total is the "estimated & ready" signal; the CTA is
  // the Figma "Confirm Booking" HopButton — below the fold in the tall Book
  // composition, so scroll it into view before tapping.
  await _pumpUntilFound(
    tester,
    find.text('£6.39'),
    step: const Duration(milliseconds: 100),
  );
  final confirm = find.widgetWithText(HopButton, 'Confirm Booking');
  await tester.ensureVisible(confirm);
  await tester.pump();
  await tester.tap(confirm);
  await _pumpUntilFound(
    tester,
    find.byType(RadarPulse),
    step: const Duration(milliseconds: 100),
  );
}

/// Bounded pump-until (never pumpAndSettle — the radar loop and the demo
/// world hold live tickers that stall settle detection).
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

/// Unmounts the tree (disposing the riblet's timers via the container), then
/// quiets the world so no scripted timer trips the pending-timer invariant —
/// inside the test body, because flutter_test's !timersPending check runs
/// BEFORE addTearDown callbacks.
Future<void> _cleanupFlow(WidgetTester tester, _FlowHarness h) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
  h.container.dispose();
  h.world.reset();
}

/// Drives the real "No drivers accepted" branch: after the request, the
/// only unseen ride in history is a server-side cancellation — exactly the
/// dispatch-exhausted shape the id-diff poll reacts to.
class _NoDriversRepo implements RidesRepository {
  bool _requested = false;

  @override
  Future<FareEstimate> estimate({
    required double pickupLat,
    required double pickupLng,
    required double dropoffLat,
    required double dropoffLng,
    String? vehicleCategoryId,
  }) async {
    return estimateBetween(
      pickupLat: pickupLat,
      pickupLng: pickupLng,
      dropoffLat: dropoffLat,
      dropoffLng: dropoffLng,
    );
  }

  @override
  Future<String> requestRide({
    required double pickupLat,
    required double pickupLng,
    required double dropoffLat,
    required double dropoffLng,
    String? vehicleCategoryId,
  }) async {
    _requested = true;
    return 'req-1';
  }

  @override
  Future<List<Ride>> history({int limit = 50}) async => _requested
      ? const [
          Ride(
            id: 'ride-cancelled',
            riderId: 'rider-x',
            status: RideStatus.cancelled,
          ),
        ]
      : const <Ride>[];

  @override

  // In-area so the confirm-pickup geofence passes.
  @override
  Future<bool?> isServiceable(double lat, double lng) async => true;
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Estimate succeeds, but the request itself throws a transport-level failure
/// (not an ApiException) — the genuine designed `failed` card path, distinct
/// from dispatch-exhaustion (which now leads with the BOOK-08 retry rung).
class _RequestErrorRepo implements RidesRepository {
  @override
  Future<FareEstimate> estimate({
    required double pickupLat,
    required double pickupLng,
    required double dropoffLat,
    required double dropoffLng,
    String? vehicleCategoryId,
  }) async {
    return estimateBetween(
      pickupLat: pickupLat,
      pickupLng: pickupLng,
      dropoffLat: dropoffLat,
      dropoffLng: dropoffLng,
    );
  }

  @override
  Future<List<Ride>> history({int limit = 50}) async => const <Ride>[];

  @override
  Future<String> requestRide({
    required double pickupLat,
    required double pickupLng,
    required double dropoffLat,
    required double dropoffLng,
    String? vehicleCategoryId,
  }) async {
    throw Exception('network down');
  }

  // In-area, so the confirm-pickup server geofence passes and the test reaches
  // its real subject — the throwing requestRide above.
  @override
  Future<bool?> isServiceable(double lat, double lng) async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The booking guard's live shape: estimate succeeds, but the request is
/// rejected with `403 ACCOUNT_NOT_ELIGIBLE` (unverified / under-18 / inactive)
/// — the server-authoritative verify gate the wall mirrors.
class _EligibilityGateRepo implements RidesRepository {
  @override
  Future<FareEstimate> estimate({
    required double pickupLat,
    required double pickupLng,
    required double dropoffLat,
    required double dropoffLng,
    String? vehicleCategoryId,
  }) async {
    return estimateBetween(
      pickupLat: pickupLat,
      pickupLng: pickupLng,
      dropoffLat: dropoffLat,
      dropoffLng: dropoffLng,
    );
  }

  @override
  Future<List<Ride>> history({int limit = 50}) async => const <Ride>[];

  @override
  Future<String> requestRide({
    required double pickupLat,
    required double pickupLng,
    required double dropoffLat,
    required double dropoffLng,
    String? vehicleCategoryId,
  }) async {
    throw const ApiException(
      statusCode: 403,
      message: 'You need to verify your account before booking.',
      code: 'ACCOUNT_NOT_ELIGIBLE',
    );
  }

  // In-area, so the geofence passes and the request reaches its 403 subject.
  @override
  Future<bool?> isServiceable(double lat, double lng) async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Records whether `requestRide` was ever called — proves the geofence
/// pre-flight fast-fails before the network for an outside-area pickup.
class _RecordingRequestRepo implements RidesRepository {
  int requestCount = 0;

  @override
  Future<FareEstimate> estimate({
    required double pickupLat,
    required double pickupLng,
    required double dropoffLat,
    required double dropoffLng,
    String? vehicleCategoryId,
  }) async {
    return estimateBetween(
      pickupLat: pickupLat,
      pickupLng: pickupLng,
      dropoffLat: dropoffLat,
      dropoffLng: dropoffLng,
    );
  }

  @override
  Future<List<Ride>> history({int limit = 50}) async => const <Ride>[];

  @override
  Future<String> requestRide({
    required double pickupLat,
    required double pickupLng,
    required double dropoffLat,
    required double dropoffLng,
    String? vehicleCategoryId,
  }) async {
    requestCount++;
    return 'req-1';
  }

  @override

  // In-area so the confirm-pickup geofence passes.
  @override
  Future<bool?> isServiceable(double lat, double lng) async => true;
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
