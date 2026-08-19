import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/features/auth/reset_landing_screen.dart';
import 'package:hoppin_rider/features/auth/signup_eligibility_notice.dart';
import 'package:hoppin_rider/features/booking/widgets/fee_disclosure.dart';
import 'package:hoppin_rider/features/booking/widgets/matching_rung.dart';
import 'package:hoppin_rider/features/booking/widgets/multistop_unavailable_notice.dart';
import 'package:hoppin_rider/features/booking/widgets/ride_type_selector.dart';
import 'package:hoppin_rider/features/booking/widgets/service_unavailable_screen.dart';
import 'package:hoppin_rider/features/legal/widgets/consent_record_unavailable.dart';
import 'package:hoppin_rider/features/profile/personal/widgets/personal_info_unavailable.dart';
import 'package:hoppin_rider/features/promotions/widgets/promo_codes_unavailable.dart';
import 'package:hoppin_rider/features/settings/widgets/deletion_via_support_notice.dart';
import 'package:hoppin_rider/features/settings/widgets/settings_prefs_unavailable.dart';
import 'package:hoppin_rider/features/trip/widgets/call_unavailable_state.dart';
import 'package:hoppin_rider/features/trip/widgets/seam_unavailable_states.dart';
import 'package:hoppin_rider/features/trip/widgets/share_link_unavailable_state.dart';
import 'package:hoppin_rider/features/wallet/coming_soon_sheet.dart';
import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

/// DS-04 group C — every seam's consumer renders a DESIGNED unavailable-state
/// (never a blank over `null`).
///
/// For each `kSeamRegistry` entry's `unavailableWidget`, this pumps the widget
/// the consuming view renders in its seam-returns-null configuration and
/// asserts a designed element is on screen AND the surface is not an empty /
/// zero-size box. This is the "blank over null is a defect" enforcement that
/// the source/ledger halves (groups A/B in hoppin_shared) cannot see.
///
/// Every RIDER entry in `kSeamRegistry` must name a widget with a builder
/// below, and — since Wave 0 — that widget must also be CONSTRUCTED by a real
/// view (the reachability check). The builder map and the registry are asserted
/// to cover each other exactly: no gaps, no orphans.
void main() {
  Widget host(Widget child) => MaterialApp(
    theme: HoppinTheme.riderLight(),
    home: Scaffold(
      body: Center(
        child: Padding(padding: const EdgeInsets.all(16), child: child),
      ),
    ),
  );

  /// Bounded settle — never pumpAndSettle (project convention).
  Future<void> pumpBounded(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// The designed fallback widget each registry `unavailableWidget` names.
  /// Every SEAMED feature MUST ship one — a missing entry here fails the test,
  /// enforcing the "designed unavailable-state widget per seam" DoD.
  final builders = <String, Widget Function()>{
    // #5 driver-info. WAVE-0 CORRECTION: this used to build `MatchedDriverCard`
    // with a FABRICATED driver (name, 4.9★, plate) — i.e. the test that claimed
    // to prove "#5 degrades honestly when the seam is null" was pumping a fake
    // identity and asserting the fake rendered. The real null-branch rung is
    // DriverUnavailableCard (trip_screen.dart:526,552), which fabricates
    // nothing.
    'DriverUnavailableCard': () => const DriverUnavailableCard(),
    'PromoUnavailableState': () => const PromoUnavailableState(),
    'RouteOnlyMapState': () => const RouteOnlyMapState(),
    // ── Phase-9 view/gateway/data seam unavailable-states ────────────────
    // Stripe add-card GATED → the designed "coming soon" sheet content.
    'ComingSoonSheet': () => const ComingSoonSheet(),
    // Geofence outside-area → the designed "not in your area yet" screen.
    'ServiceUnavailableScreen': () => ServiceUnavailableScreen(onExit: () {}),
    // 18+/SL-5 MISSING-BE → the designed on-device eligibility disclosure.
    'SignupEligibilityNotice': () => const SignupEligibilityNotice(),
    // Reset #49 GATED → the honest "reset link unavailable" landing.
    'ResetLandingScreen': () => const ResetLandingScreen(),
    // ── Phase-10 view seams ──────────────────────────────────────────────
    // SL-1 ride-type MISSING-BE → the static disclosed selector IS the seam.
    'RideTypeSelector': () =>
        RideTypeSelector(selectedCategory: null, onSelect: (_) {}),
    // SL-11 multi-stop MISSING-BE → the designed deferred disclosure state.
    'MultiStopUnavailableNotice': () => const MultiStopUnavailableNotice(),
    // SL-9 fee disclosure MISSING-BE → renders the stub FIGURES (not a blank
    // "coming soon" rung); a dedicated test below asserts the figure is shown.
    'FeeDisclosure': () => const FeeDisclosure(),
    // BOOK-08 auto-retry SEAMED → the "finding another driver" retry rung.
    'MatchingRung': () => MatchingRung(onExit: () {}),
    // ── Phase-11 view seams ──────────────────────────────────────────────
    // #45 voice MISSING-BE → the inert call surface's honest rung, which also
    // routes the rider to chat (BOUND) so the disclosure is not a dead end.
    'CallUnavailableState': () => CallUnavailableState(onOpenChat: () {}),
    // #57 share MISSING-BE → the rung that renders WHERE the link would be.
    // Never a fabricated URL.
    'ShareLinkUnavailableState': () => const ShareLinkUnavailableState(),
    // ── Phase 12 (#70–#74) ────────────────────────────────────────────────
    // These five widgets SHIPPED, and none of them was registered. Every group
    // below is a loop over the registry, so five unregistered seams contributed
    // zero iterations: the checks did not fail, THEY DID NOT RUN. The suite was
    // green over five features it was not watching.

    // #70 → the profile read is not readable. Save is inert; the rung's exit to
    // /support is the ONE live control (Art. 16 rectification, by hand).
    'PersonalInfoUnavailable': () => const PersonalInfoUnavailable(),
    // #71 → no prefs endpoint. ONE rung for the whole screen, not one per
    // switch: eight identical rungs is noise, and noise is how a disclosure
    // gets ignored.
    'SettingsPrefsUnavailable': () => const SettingsPrefsUnavailable(),
    // #72 → we cannot LIST the rider's codes. Never "you have none" — asserting
    // emptiness when the truth is ignorance is the lie this milestone deletes.
    'PromoCodesUnavailable': () => const PromoCodesUnavailable(),
    // #73 → `DELETE /me` does not exist, but the ACTION IS BOUND: a real ticket,
    // a real human, a real one-month clock. The only seam where the rider's need
    // is genuinely met. Do not make it inert for consistency.
    'DeletionViaSupportNotice': () => const DeletionViaSupportNotice(),
    // #74 → consent cannot be DEMONSTRATED (Art. 7(1)), so no marketing is sent
    // and the app says so. Mounted at BOTH collection (signup) and withdrawal
    // (settings) — Art. 7(3) wants withdrawal as easy as giving.
    'ConsentRecordUnavailable': () => const ConsentRecordUnavailable(),
  };

  // Group C is app-local: apps/rider cannot import apps/driver, so it asserts
  // over the disclosures the RIDER OWES. The driver app runs the mirror-image
  // test over its own.
  //
  // v3.0 PHASE-0: a seam is one gap with N per-surface disclosures, so this now
  // asks "does this app cover every disclosure it OWES?" rather than "does it
  // cover every seam it OWNS?" — the question that should always have been
  // asked. A gap can strand BOTH surfaces (#41, #17 do), and each owes its own
  // honest state in its own voice.
  final riderOwed = seamDisclosuresFor(SeamApp.rider).toList();

  test('every RIDER disclosure names a fallback widget with a builder', () {
    for (final owed in riderOwed) {
      expect(
        builders.containsKey(owed.disclosure.unavailableWidget),
        isTrue,
        reason:
            'seam #${owed.entry.gap} (${owed.entry.feature}) owes the rider a '
            'disclosure named "${owed.disclosure.unavailableWidget}" but group '
            'C has no builder for it — every SEAMED feature must ship a '
            'designed unavailable-state widget (the DS-04 DoD).',
      );
    }
  });

  test('group C has no builders for disclosures this app does not owe', () {
    // The inverse direction: a stale builder for a widget no disclosure names
    // is dead weight that makes coverage look bigger than it is.
    final named = riderOwed.map((o) => o.disclosure.unavailableWidget).toSet();
    expect(
      builders.keys.toSet().difference(named),
      isEmpty,
      reason:
          'group C builds widgets that no RIDER disclosure names. Either the '
          'registry entry was removed (delete the builder) or the disclosure '
          'belongs to another surface (check its SeamDisclosure.app).',
    );
  });

  // THE REACHABILITY CHECK — the one that was missing, and the reason four
  // "disclosures" were dead code while the gate stayed green.
  //
  // Group C used to construct the fallback widget ITSELF and assert it rendered
  // in a bare harness. That proves a widget CAN render; it proves nothing about
  // whether any screen EVER MOUNTS IT. RouteOnlyMapState, PromoUnavailableState,
  // SignupEligibilityNotice and MultiStopUnavailableNotice all passed that check
  // while being referenced by ZERO production files — the user saw nothing, the
  // ledger claimed disclosure, and the suite was green.
  //
  // A widget that is declared but never constructed is not a disclosure. It is
  // dead code wearing a compliance badge.
  test('every RIDER disclosure widget is CONSTRUCTED in a real view', () {
    final libDir = Directory('lib');
    final sources = libDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .map((f) => (path: f.path, text: f.readAsStringSync()))
        .toList();

    final orphans = <String>[];

    for (final name
        in riderOwed.map((o) => o.disclosure.unavailableWidget).toSet()) {
      // Where is it declared? (Excluded from the mount search — a class
      // referencing its own name is not a mount.)
      final declaring = sources.where(
        (s) => RegExp('class\\s+$name\\b').hasMatch(s.text),
      );
      expect(
        declaring,
        isNotEmpty,
        reason: '"$name" is named by a seam but declared nowhere in lib/',
      );
      final declPath = declaring.first.path;

      // Is it reachable from anywhere else? Two legitimate mount shapes:
      //   1. constructed directly           — `Name(` / `const Name(`
      //   2. presented via its show-helper  — `showName(context)`, the modal
      //      idiom (e.g. `showComingSoonSheet` presents `ComingSoonSheet`).
      // Accepting (2) matters: without it the check would push a developer to
      // inline a constructor purely to satisfy the test, which is exactly the
      // kind of test-shaped damage that makes people distrust the instrument.
      final ctor = RegExp('(?<![\\w.])$name\\s*\\(');
      final showHelper = RegExp('(?<![\\w.])show$name\\s*\\(');
      final mounted = sources.any(
        (s) =>
            s.path != declPath &&
            (ctor.hasMatch(s.text) || showHelper.hasMatch(s.text)),
      );
      if (!mounted) orphans.add(name);
    }

    expect(
      orphans,
      isEmpty,
      reason:
          'These designed unavailable-states are DECLARED BUT NEVER '
          'CONSTRUCTED by any view — so the seam discloses nothing and the '
          'user sees nothing, while the registry and the ledger both claim it '
          'degrades honestly. Mount each on its real null branch (or, if the '
          'seam genuinely has no surface, remove the entry and say so in the '
          'ledger):\n  ${orphans.join('\n  ')}',
    );
  });

  // One widget test per DISTINCT fallback widget named by a RIDER disclosure.
  final distinctWidgets = riderOwed
      .map((o) => o.disclosure.unavailableWidget)
      .toSet();

  for (final name in distinctWidgets) {
    testWidgets('$name renders a designed non-blank unavailable-state', (
      tester,
    ) async {
      final build = builders[name];
      expect(build, isNotNull, reason: 'no builder registered for "$name"');

      await tester.pumpWidget(host(build!()));
      await pumpBounded(tester);

      // (1) A designed element renders — the widget itself is on screen.
      final finder = find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == name,
      );
      expect(
        finder,
        findsOneWidget,
        reason: '"$name" must render its designed surface',
      );

      // (2) It renders visible text (typography-led design) — proof it is not
      //     an empty pane. Every fallback here is a headline + supporting line.
      expect(
        find.byType(Text),
        findsWidgets,
        reason: '"$name" must render designed copy, not a blank box',
      );

      // (3) The rendered surface has real size — NOT a collapsed / shrunk box.
      final size = tester.getSize(finder.first);
      expect(
        size.width,
        greaterThan(0),
        reason: '"$name" must not collapse to zero width (blank over null)',
      );
      expect(
        size.height,
        greaterThan(0),
        reason: '"$name" must not collapse to zero height (blank over null)',
      );
    });
  }

  // SL-9 is the ONE seam whose designed state must render the real (stub)
  // FIGURE, not a blank "coming soon" rung (Scope Lock §4.1 hard MUST). Assert
  // the penalty figure is on screen — the disclosure discloses the number.
  testWidgets('FeeDisclosure (SL-9) renders the stub penalty FIGURE, not a '
      'blank "coming soon" rung', (tester) async {
    await tester.pumpWidget(host(const FeeDisclosure()));
    await pumpBounded(tester);

    // The number is the point — the £5.00 stub penalty is visible up front.
    expect(
      find.textContaining('£5.00'),
      findsWidgets,
      reason:
          'the fee disclosure must show the penalty figure, never hide '
          'it behind a "coming soon" state',
    );
    expect(
      find.textContaining('2 min'),
      findsWidgets,
      reason: 'the free-cancel window figure must be shown too',
    );
  });
}
