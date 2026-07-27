import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hoppin_rider/features/promotions/promotions_screen.dart';
import 'package:hoppin_rider/features/promotions/widgets/ad_banner_card.dart';
import 'package:hoppin_rider/features/promotions/widgets/promo_codes_unavailable.dart';
import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

/// ACCT-04 — the promotions centre. The phase's most instructive screen,
/// because it is HALF-REAL and the split is structural:
///
///   * Campaigns  → `GET /ads` is genuinely BOUND, and had ZERO UI until now.
///                  Real loading / error / empty rungs. Impression + click.
///   * Your codes → `GET /me/promos` DOES NOT EXIST (gap #72 / SL-13). The
///                  section is a permanent seam and says so.
///
/// The negative assertions are the load-bearing ones:
///   * the Figma frame's three codes — WELCOME20 / REFER100 / Weekend Special —
///     are INVENTED. REFER100 doubly so: referrals are the owner's sole PARKED
///     feature, and drawing it would resurrect a killed scope item.
///   * ZERO clipboard writes. A Copy button that copies a code we made up is
///     the Wave-0 share-sheet bug reincarnated (it copied a sentence containing
///     no link and toasted "Link copied").
///   * NEVER "you have no promo codes". That asserts EMPTINESS. The truth is
///     IGNORANCE — we cannot LIST them. Phase 11 already named this quiet lie.
///   * a hostile `target_url` renders the ad card NON-TAPPABLE. Not a broken
///     link, not a swallowed navigation. `Ad.targetUrl` is a server-controlled,
///     admin-editable field with zero validation (gap #36) — every tap goes
///     through `isAllowlistedPushTarget()`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> clipboardCalls;

  setUp(() {
    clipboardCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clipboardCalls.add(call);
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  /// Bounded settle — never `pumpAndSettle` (project convention).
  Future<void> pumpBounded(WidgetTester tester, {int times = 5}) async {
    for (var i = 0; i < times; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Ad ad(
    String id, {
    String? title,
    String? body,
    String? imageUrl,
    String? targetUrl,
  }) =>
      Ad(
        id: id,
        title: title ?? 'Campaign $id',
        body: body,
        imageUrl: imageUrl,
        targetUrl: targetUrl,
      );

  /// The routes an allowlisted ad target may reach, plus a landing stub so a
  /// real navigation is observable.
  GoRouter routerFor(Widget home) => GoRouter(
        initialLocation: '/profile/promotions',
        routes: [
          GoRoute(path: '/profile/promotions', builder: (_, _) => home),
          GoRoute(
            path: '/history',
            builder: (_, _) => const Scaffold(body: Text('history-stub')),
          ),
          GoRoute(
            path: '/support',
            builder: (_, _) => const Scaffold(body: Text('support-stub')),
          ),
        ],
      );

  Future<_Fakes> pumpPromotions(
    WidgetTester tester, {
    List<Ad>? ads,
    bool throwOnLoad = false,
    bool hang = false,
    ThemeData? theme,
    List<PromoOffer>? offers,
  }) async {
    final fakeAds = _RecordingAdsRepository(
      ads: ads ?? const <Ad>[],
      throwOnLoad: throwOnLoad,
      hang: hang,
    );
    final fakeSupport = _RecordingSupportRepository();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        adsRepositoryProvider.overrideWithValue(fakeAds),
        supportRepositoryProvider.overrideWithValue(fakeSupport),
        // The CATALOGUE half (`GET /promotions`). Defaults to empty so the
        // existing assertions see the screen they were written against.
        ridesRepositoryProvider
            .overrideWithValue(_CatalogueRidesRepository(offers ?? const [])),
      ],
      child: MaterialApp.router(
        theme: theme ?? HoppinTheme.riderLight(),
        routerConfig: routerFor(const PromotionsScreen()),
      ),
    ));
    await pumpBounded(tester);

    return _Fakes(fakeAds, fakeSupport);
  }

  /// Drives every control the screen renders, so "nothing happened" is an
  /// assertion about the whole surface rather than about one button.
  Future<void> driveEveryControl(WidgetTester tester) async {
    for (final type in [HopButton, HopCard, InkWell, TextButton, IconButton]) {
      final finder = find.byType(type);
      final count = finder.evaluate().length;
      for (var i = 0; i < count; i++) {
        await tester.tap(find.byType(type).at(i), warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 50));
      }
    }
    await pumpBounded(tester);
  }

  group('ACCT-04 — the BOUND half: campaigns from GET /ads', () {
    testWidgets('renders a card per ad with its real title and body',
        (tester) async {
      await pumpPromotions(tester, ads: [
        ad('a1', title: '20% off airport runs', body: 'Weekdays before 9am'),
        ad('a2', title: 'Evening fares fixed', body: 'After 8pm, all week'),
      ]);

      expect(find.byType(AdBannerCard), findsNWidgets(2),
          reason: 'GET /ads is BOUND and has had zero UI since it shipped — '
              'this lane is the first thing that renders it');
      expect(find.text('20% off airport runs'), findsOneWidget,
          reason: 'the card shows the REAL server title, not a mockup string');
      expect(find.text('Weekdays before 9am'), findsOneWidget,
          reason: 'the card shows the REAL server body');
      expect(find.text('Evening fares fixed'), findsOneWidget);
    });

    testWidgets('reports an impression exactly ONCE per ad, not per rebuild',
        (tester) async {
      final fakes = await pumpPromotions(tester, ads: [
        ad('a1'),
        ad('a2'),
      ]);

      // Force extra frames — a `build`-time impression would multiply here.
      await pumpBounded(tester, times: 10);
      await tester.pump(const Duration(milliseconds: 500));

      expect(fakes.ads.impressions, ['a1', 'a2'],
          reason: 'impression is a one-shot per ad. Firing it from build() '
              'would inflate the admin reach metric with every rebuild — a '
              'quiet data lie, and the metric feeds real ad billing');
    });

    testWidgets('an unresolved feed renders a LOADER, not a blank screen',
        (tester) async {
      await pumpPromotions(tester, hang: true);

      expect(find.byType(CircularProgressIndicator), findsOneWidget,
          reason: 'a pending BOUND call has an honest loading rung');
      expect(find.byType(AdBannerCard), findsNothing,
          reason: 'nothing is rendered before the feed resolves');
    });

    testWidgets('a throwing feed renders an ERROR rung — not a crash, not a '
        'blank', (tester) async {
      await pumpPromotions(tester, throwOnLoad: true);

      expect(tester.takeException(), isNull,
          reason: 'a failing BOUND call must degrade, never crash the screen');
      expect(find.textContaining("couldn't load"), findsOneWidget,
          reason: 'the error rung tells the rider the campaigns failed to '
              'load — a blank section would be indistinguishable from "none"');
      expect(find.byType(PromoCodesUnavailable), findsOneWidget,
          reason: 'the SEAMED half is unaffected by the BOUND half failing — '
              'the two sections are structurally independent');
    });

    testWidgets('a failed feed does NOT leave the rider on a spinner forever',
        (tester) async {
      await pumpPromotions(tester, throwOnLoad: true);
      await pumpBounded(tester, times: 20);

      expect(find.byType(CircularProgressIndicator), findsNothing,
          reason: 'Riverpod 3 delivers a failed FutureProvider as '
              'AsyncLoading(error: …) — isLoading is STILL true while the '
              'error rides along, so an AsyncValue.when ladder routes it to '
              'the LOADING branch and spins forever on a dead endpoint. The '
              'rider would watch a spinner that never resolves and never learn '
              'the call failed. hasError must be asked FIRST');
    });

    testWidgets('an EMPTY feed says "no campaigns" — and that is HONEST here',
        (tester) async {
      await pumpPromotions(tester, ads: const []);

      expect(find.byType(AdBannerCard), findsNothing);
      expect(find.textContaining('No campaigns'), findsOneWidget,
          reason: 'we genuinely CAN list campaigns — the endpoint answered [] '
              '— so asserting emptiness is a FACT here. This is exactly why '
              'the same sentence must NOT be reused for the codes section, '
              'where it would be a lie (#72: we cannot list them at all)');
    });
  });

  group('ACCT-04 — SECURITY: every ad target goes through the allowlist (#36)',
      () {
    // `Ad.targetUrl` is a server-controlled, admin-editable field with ZERO
    // validation anywhere in the app (DOCS/06 #36: "a bare model field with
    // zero validation"). Without the allowlist, an admin-console typo — or an
    // admin-console compromise — is an open redirect / scheme injection
    // straight into the rider app.
    for (final hostile in const [
      'https://evil.example',
      'http://evil.example',
      'javascript:alert(1)',
      '//evil.example',
      '../../admin',
      'mailto:x@y.z',
      'tel:+441234',
    ]) {
      testWidgets('a hostile target_url ($hostile) renders a NON-TAPPABLE card',
          (tester) async {
        final fakes =
            await pumpPromotions(tester, ads: [ad('a1', targetUrl: hostile)]);

        final card = tester.widget<HopCard>(
          find.descendant(
            of: find.byType(AdBannerCard),
            matching: find.byType(HopCard),
          ),
        );
        expect(card.onTap, isNull,
            reason: 'a non-allowlisted target means the ad is NOT A LINK, so '
                'the card is NOT A TAP TARGET. onTap: null — never a no-op '
                'callback (which still ripples and still lies), never a '
                'swallowed navigation, never a toast');

        await tester.tap(find.byType(AdBannerCard), warnIfMissed: false);
        await pumpBounded(tester);

        expect(fakes.ads.clicks, isEmpty,
            reason: 'a hostile target must never reach reportClick — and it '
                'must never navigate');
      });
    }

    // The positive control. A test that only proves rejection would also pass
    // on a screen where NOTHING is ever tappable.
    testWidgets('an ALLOWLISTED in-app target IS tappable, clicks once, and '
        'navigates', (tester) async {
      final fakes =
          await pumpPromotions(tester, ads: [ad('a1', targetUrl: '/history')]);

      final card = tester.widget<HopCard>(
        find.descendant(
          of: find.byType(AdBannerCard),
          matching: find.byType(HopCard),
        ),
      );
      expect(card.onTap, isNotNull,
          reason: 'positive control: the allowlist admits real in-app paths, '
              'so a legitimate campaign genuinely works');

      await tester.tap(find.byType(AdBannerCard));
      await pumpBounded(tester, times: 12);

      expect(fakes.ads.clicks, ['a1'],
          reason: 'a real tap on a real target reports exactly one click');
      expect(find.text('history-stub'), findsOneWidget,
          reason: 'and it actually navigates to the allowlisted route');
    });

    testWidgets('a NULL target_url renders a non-tappable card', (tester) async {
      final fakes = await pumpPromotions(tester, ads: [ad('a1')]);

      final card = tester.widget<HopCard>(
        find.descendant(
          of: find.byType(AdBannerCard),
          matching: find.byType(HopCard),
        ),
      );
      expect(card.onTap, isNull,
          reason: 'no target means no link — an informational banner, not a '
              'dead tap target');

      await tester.tap(find.byType(AdBannerCard), warnIfMissed: false);
      await pumpBounded(tester);
      expect(fakes.ads.clicks, isEmpty,
          reason: 'nothing to click through to');
    });
  });

  group('ACCT-04 — the SEAMED half: the #72 promo-codes rung', () {
    testWidgets('CONSTRUCTS PromoCodesUnavailable on the real screen '
        '(Group C reachability)', (tester) async {
      await pumpPromotions(tester, ads: [ad('a1')]);

      expect(find.byType(PromoCodesUnavailable), findsOneWidget,
          reason: 'the #72 rung must be CONSTRUCTED on the real codes section '
              'of the real view. A declared-but-never-mounted disclosure is '
              'dead code wearing a compliance badge');
      final size = tester.getSize(find.byType(PromoCodesUnavailable));
      expect(size.height, greaterThan(24),
          reason: 'the rung is a real-sized designed surface, not a blank');
      expect(size.width, greaterThan(24),
          reason: 'Group C pumps non-zero width AND height');
    });

    testWidgets('the rung is present even when the BOUND half has campaigns',
        (tester) async {
      await pumpPromotions(tester, ads: [ad('a1'), ad('a2')]);

      expect(find.byType(PromoCodesUnavailable), findsOneWidget,
          reason: 'campaigns loading successfully does not make the rider\'s '
              'CODES listable. The seam is permanent until GET /me/promos '
              'exists — the two halves are independent');
    });

    testWidgets('the rung is present when the BOUND half is EMPTY',
        (tester) async {
      await pumpPromotions(tester, ads: const []);

      expect(find.byType(PromoCodesUnavailable), findsOneWidget);
    });

    testWidgets('it discloses IGNORANCE, never EMPTINESS', (tester) async {
      await pumpPromotions(tester, ads: [ad('a1')]);

      expect(find.textContaining('You have no promo codes'), findsNothing,
          reason: 'we do not KNOW that they have none — we cannot LIST them. '
              'PromoCodesUnavailable says the second thing. Asserting '
              'emptiness when the truth is ignorance is precisely the quiet '
              'lie Phase 11 deleted from the notification centre');
      expect(find.textContaining('no promo codes'), findsNothing,
          reason: 'same lie, any casing/phrasing');
      expect(find.textContaining("can't list"), findsOneWidget,
          reason: 'the rung states the actual truth: we cannot LIST them yet');
    });

    testWidgets('it FORWARDS the rider to where a code genuinely works',
        (tester) async {
      await pumpPromotions(tester, ads: [ad('a1')]);

      expect(find.textContaining('when you book'), findsOneWidget,
          reason: 'POST /rides/:id/promo is BOUND — codes really do work, we '
              'just cannot LIST them. A disclosure that strands the rider is '
              'only half-honest (the CallUnavailableState precedent)');
    });

    testWidgets('there is NO pre-ride "validate code" control', (tester) async {
      await pumpPromotions(tester, ads: [ad('a1')]);

      for (final forbidden in ['Validate', 'Check code', 'Apply code']) {
        expect(find.textContaining(forbidden), findsNothing,
            reason: 'POST /rides/:id/promo NEEDS A RIDE. There is no pre-ride '
                'validation endpoint (that is the pre-existing seam #46). A '
                'validate button here would be a BRAND-NEW LIE, minted by the '
                'phase whose entire purpose is to stop lying');
      }
    });
  });

  group('ACCT-04 — the Figma fabrications that must NEVER ship', () {
    testWidgets('the three invented codes appear NOWHERE', (tester) async {
      await pumpPromotions(tester, ads: [ad('a1'), ad('a2')]);

      expect(find.textContaining('WELCOME20'), findsNothing,
          reason: 'invented by the Figma frame — there is no GET /me/promos, '
              'so no code the app renders could be real');
      expect(find.textContaining('REFER100'), findsNothing,
          reason: 'invented AND doubly forbidden: REFERRALS ARE THE OWNER\'S '
              'SOLE PARKED FEATURE. Drawing a referral code would resurrect a '
              'killed scope item on a screen with no endpoint to back it');
      expect(find.textContaining('Weekend Special'), findsNothing,
          reason: 'invented by the Figma frame');
      expect(find.textContaining('Valid until'), findsNothing,
          reason: 'the frame\'s expiry dates are invented too — there is no '
              'code to have an expiry');
    });

    testWidgets('there is NO Copy button anywhere on the screen',
        (tester) async {
      await pumpPromotions(tester, ads: [ad('a1')]);

      expect(find.textContaining('Copy'), findsNothing,
          reason: 'there is nothing true to copy');
    });

    testWidgets('driving EVERY control writes NOTHING to the clipboard',
        (tester) async {
      await pumpPromotions(tester, ads: [
        ad('a1', targetUrl: '/support'),
        ad('a2'),
      ]);

      await driveEveryControl(tester);

      expect(clipboardCalls, isEmpty,
          reason: 'there are no real promo codes (#72) — a Copy button that '
              'copies an invented code is the Wave-0 share bug reincarnated '
              '(it copied a sentence containing no link and toasted '
              '"Link copied")');
    });

    testWidgets('driving EVERY control files ZERO support tickets',
        (tester) async {
      final fakes = await pumpPromotions(tester, ads: [ad('a1'), ad('a2')]);

      await driveEveryControl(tester);

      expect(fakes.support.tickets, isEmpty,
          reason: 'the promotions centre opens no tickets — nothing on this '
              'screen may silently write to a server the rider did not ask to '
              'write to');
    });
  });

  group('ACCT-04 — both themes', () {
    testWidgets('the half-real screen renders in the dark theme',
        (tester) async {
      await pumpPromotions(
        tester,
        ads: [ad('a1', body: 'dark body', targetUrl: '/history')],
        theme: HoppinTheme.riderDark(),
      );

      expect(find.byType(AdBannerCard), findsOneWidget,
          reason: 'the BOUND half renders in dark');
      expect(find.byType(PromoCodesUnavailable), findsOneWidget,
          reason: 'the SEAMED half renders in dark — both themes ship');
    });

    testWidgets('an ad with no image_url degrades to a token card, never a '
        'broken-image glyph', (tester) async {
      await pumpPromotions(tester, ads: [ad('a1', title: 'No image here')]);

      expect(tester.takeException(), isNull,
          reason: 'a missing image_url is the common case, not an error');
      expect(find.text('No image here'), findsOneWidget,
          reason: 'the card still carries its real title');
    });
  });
}

/// The two fakes a test drives.
class _Fakes {
  _Fakes(this.ads, this.support);

  final _RecordingAdsRepository ads;
  final _RecordingSupportRepository support;
}

/// Records every engagement call so "exactly one impression" and "zero clicks"
/// are assertions, not hopes.
class _RecordingAdsRepository implements AdsRepository {
  _RecordingAdsRepository({
    required this.ads,
    this.throwOnLoad = false,
    this.hang = false,
  });

  final List<Ad> ads;
  final bool throwOnLoad;
  final bool hang;

  final List<String> impressions = <String>[];
  final List<String> clicks = <String>[];

  @override
  Future<List<Ad>> activeAds() {
    if (hang) return Completer<List<Ad>>().future;
    if (throwOnLoad) return Future.error(Exception('ads are down'));
    return Future.value(ads);
  }

  @override
  Future<void> reportImpression(String adId) async => impressions.add(adId);

  @override
  Future<void> reportClick(String adId) async => clicks.add(adId);
}

/// The promotions centre must open no tickets. This makes that an assertion.
/// Serves the CATALOGUE half (`GET /promotions`). Everything else throws — no
/// other ride-service call belongs on this screen, and a silent stub would hide
/// it if one appeared.
class _CatalogueRidesRepository implements RidesRepository {
  _CatalogueRidesRepository(this._offers);

  final List<PromoOffer> _offers;

  @override
  Future<List<PromoOffer>> promotions() async => _offers;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
        'the promotions screen must not call ${invocation.memberName}',
      );
}

class _RecordingSupportRepository implements SupportRepository {
  final List<String> tickets = <String>[];

  @override
  Future<String> createTicket({
    required String subject,
    String? category,
    String? typeCode,
    String? priority,
    String? rideId,
    String? body,
    List<String>? tags,
  }) async {
    tickets.add(subject);
    return 't-1';
  }

  @override
  Future<List<SupportTicket>> myTickets() async => const [];

  @override
  Future<TicketThread> thread(String ticketId) =>
      throw UnimplementedError('not used by the promotions centre');

  @override
  Future<void> reply({required String ticketId, required String body}) async {}
}
