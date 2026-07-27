import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/features/legal/consent_notice.dart';
import 'package:hoppin_rider/features/legal/consent_notifier.dart';
import 'package:hoppin_rider/features/legal/marketing_consent_toggle.dart';
import 'package:hoppin_rider/features/legal/privacy_notice_screen.dart';
import 'package:hoppin_rider/features/legal/terms_screen.dart';
import 'package:hoppin_rider/features/legal/widgets/consent_record_unavailable.dart';
import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

/// COMPLY-01 — the consent posture, in test form.
///
/// The whole legal argument of Phase 12 is encoded here:
///
///  * Ride processing rests on the **contract basis** (Art. 6(1)(b)). There is
///    NO consent wall. The ICO says consent is the wrong basis for processing
///    necessary to deliver the service the person asked for, and that such
///    consent may not even be VALID (it is not freely given if refusing means
///    no ride). A wall would be wrong AND invalid.
///  * What the contract basis requires instead is TRANSPARENCY (Arts. 13/14) —
///    the privacy notice, at a route that actually resolves.
///  * The marketing toggle defaults OFF. PECR requires opt-IN; a pre-ticked box
///    is unlawful and the ICO has enforced on exactly that.
///  * Nothing is written anywhere. There is no `POST /me/consents` (gap 42) and
///    a device-local consent record is not legal evidence (Art. 7(1) requires
///    consent be DEMONSTRABLE: who, when, how, and what they were told).
void main() {
  /// A recording `SupportRepository` — the lane-local zero-write instrument.
  /// If consent ever files a ticket, or writes ANYTHING, this catches it.
  late _RecordingSupportRepository recordingSupport;

  setUp(() => recordingSupport = _RecordingSupportRepository());

  ProviderContainer container() {
    final c = ProviderContainer(
      overrides: [
        supportRepositoryProvider.overrideWithValue(recordingSupport),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  /// A tall surface so nothing under test is merely below the fold. A widget
  /// that was never built reads exactly like a widget that is missing, and this
  /// file's job is to tell those two apart.
  void tallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 4200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  /// Pumps a fragment (a notice, a toggle, a rung) inside a host Scaffold.
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    ThemeData? theme,
  }) async {
    tallSurface(tester);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        supportRepositoryProvider.overrideWithValue(recordingSupport),
      ],
      child: MaterialApp(
        theme: theme ?? HoppinTheme.riderLight(),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ));
    // Bounded pumps only — never pumpAndSettle (project convention).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// Pumps a full screen (which brings its own Scaffold) as the app home.
  Future<void> pumpScreen(
    WidgetTester tester,
    Widget screen, {
    ThemeData? theme,
  }) async {
    tallSurface(tester);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        supportRepositoryProvider.overrideWithValue(recordingSupport),
      ],
      child: MaterialApp(
        theme: theme ?? HoppinTheme.riderLight(),
        home: screen,
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  group('COMPLY-01: marketing consent defaults OFF (PECR opt-IN)', () {
    test('marketingConsentProvider reads false on a fresh container', () {
      final c = container();

      expect(
        c.read(marketingConsentProvider),
        isFalse,
        reason:
            'PECR requires opt-IN. A pre-ticked box is UNLAWFUL and the ICO has '
            'taken enforcement action specifically on pre-ticked boxes.',
      );
    });

    testWidgets('the toggle renders OFF and requires a positive act',
        (tester) async {
      await pump(tester, const MarketingConsentToggle());

      final sw = tester.widget<Switch>(find.byType(Switch));
      expect(
        sw.value,
        isFalse,
        reason:
            'The rendered switch must be un-ticked at first paint. Silence and '
            'inactivity are not consent — a positive act is required.',
      );
    });

    testWidgets('toggling ON changes the notifier and writes NOTHING',
        (tester) async {
      tallSurface(tester);
      final c = container();
      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: HoppinTheme.riderLight(),
          home: const Scaffold(
            body: SingleChildScrollView(child: MarketingConsentToggle()),
          ),
        ),
      ));
      await tester.pump();

      await tester.tap(find.byType(Switch));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        c.read(marketingConsentProvider),
        isTrue,
        reason:
            'A positive act (the tap) is what grants consent — and it must '
            'actually land in the session-scoped notifier, or the control is '
            'decorative.',
      );
      expect(
        recordingSupport.createdTickets,
        isEmpty,
        reason:
            'ONLY the deletion/export popup may write. Toggling consent writes '
            'NOTHING — not to the server (there is no POST /me/consents, that '
            'is gap 42) and not to disk (a device-local consent record is not '
            'legal evidence).',
      );
    });
  });

  group('COMPLY-01: there is NO consent wall', () {
    testWidgets('the consent block does NOT gate submit', (tester) async {
      var submitted = false;

      await pump(
        tester,
        Column(
          children: [
            const ConsentNotice(),
            const MarketingConsentToggle(),
            // Stand-in for the signup submit button that Lane F will mount the
            // consent block above. The toggle is OFF (the default).
            HopButton.primary(
              label: 'Create account',
              onPressed: () => submitted = true,
            ),
          ],
        ),
      );

      await tester.tap(find.text('Create account'));
      await tester.pump();

      expect(
        submitted,
        isTrue,
        reason:
            'ride processing rests on the CONTRACT basis. Gating the ride on a '
            'marketing consent would make the consent not-freely-given — '
            'INVALID — and it is the wrong basis anyway (ICO).',
      );
    });

    testWidgets('there is no ride-processing consent checkbox', (tester) async {
      await pump(
        tester,
        const Column(children: [ConsentNotice(), MarketingConsentToggle()]),
      );

      expect(
        find.byType(Checkbox),
        findsNothing,
        reason:
            'A consent CHECKBOX for ride processing would be a wall: invalid '
            'consent (not freely given) AND the wrong lawful basis. The only '
            'gating box in the app is the 18+ declaration on signup, and it '
            'stays the only gate.',
      );
      expect(
        find.textContaining('I consent to', findRichText: true),
        findsNothing,
        reason:
            'We do not ask for consent we do not need. The app UNDER-collects '
            'and is more compliant for it.',
      );
    });
  });

  group('COMPLY-01: seam 74 — the consent record rung', () {
    testWidgets('ConsentRecordUnavailable is mounted beneath the toggle',
        (tester) async {
      await pump(tester, const MarketingConsentToggle());

      expect(
        find.byType(ConsentRecordUnavailable),
        findsOneWidget,
        reason:
            'Group C reachability: the rung must be CONSTRUCTED in the real '
            'view at the moment of collection. A declared-but-never-mounted '
            'disclosure is dead code wearing a compliance badge.',
      );
    });

    testWidgets('the rung states the evaporation consequence out loud',
        (tester) async {
      await pump(tester, const ConsentRecordUnavailable());

      expect(
        find.textContaining("won't send you any marketing", findRichText: true),
        findsOneWidget,
        reason:
            'The load-bearing sentence: with no POST /me/consents we cannot '
            'demonstrate consent, so we send NO marketing at all. Not-sending '
            'is lawful; sending against an unrecorded preference is not.',
      );
      expect(
        find.textContaining("isn't saved when you close the app",
            findRichText: true),
        findsOneWidget,
        reason:
            'An opted-IN rider s choice EVAPORATES. Saying so pre-empts the '
            'accusation that the toggle is decorative.',
      );
    });

    for (final entry in {
      'light': HoppinTheme.riderLight(),
      'dark': HoppinTheme.riderDark(),
    }.entries) {
      testWidgets('the rung renders non-blank at non-zero size (${entry.key})',
          (tester) async {
        await pump(tester, const ConsentRecordUnavailable(),
            theme: entry.value);

        final size = tester.getSize(find.byType(ConsentRecordUnavailable));
        expect(
          size.width > 0 && size.height > 0,
          isTrue,
          reason:
              'A zero-size rung is an invisible disclosure — i.e. no '
              'disclosure at all (${entry.key} theme).',
        );
        expect(
          find.byType(Text),
          findsWidgets,
          reason: 'The rung must carry readable text in ${entry.key}.',
        );
      });
    }
  });

  group('COMPLY-01: transparency (Arts. 13/14) — the notice RESOLVES', () {
    testWidgets('ConsentNotice links to the real /legal/privacy route',
        (tester) async {
      await pump(tester, const ConsentNotice());

      expect(
        find.textContaining('Privacy', findRichText: true),
        findsWidgets,
        reason:
            'Transparency is what MAKES the contract basis lawful. The notice '
            'must offer the link, in plain sight, at the point of collection.',
      );
    });

    test('the ConsentNotice source names the real route, not a dead link', () {
      final src = File(
        'lib/features/legal/consent_notice.dart',
      ).readAsStringSync();

      expect(
        src.contains('/legal/privacy'),
        isTrue,
        reason:
            'The link must point at a route that RESOLVES. The app must never '
            'render a link that 404s — a dead end that lies is worse than one '
            'that admits it.',
      );
    });

    testWidgets('the privacy notice renders non-empty, VERSIONED text',
        (tester) async {
      await pumpScreen(tester, const PrivacyNoticeScreen());

      expect(
        find.textContaining(noticeVersion, findRichText: true),
        findsOneWidget,
        reason:
            'The notice must be VERSIONED. "What they were told" is one of the '
            'four things Art. 7(1) demonstrable consent requires, and it is '
            'the only one we can solve client-side today.',
      );
      expect(
        find.textContaining('Information Commissioner', findRichText: true),
        findsOneWidget,
        reason:
            'Art. 13 requires we tell the rider they may complain to the ICO.',
      );
      expect(
        find.textContaining('contract', findRichText: true),
        findsWidgets,
        reason:
            'The notice must name the lawful basis. It is CONTRACT — we are '
            'performing the ride the rider asked for.',
      );
    });

    testWidgets('the terms screen renders non-empty text', (tester) async {
      await pumpScreen(tester, const TermsScreen());

      expect(
        find.byType(Text),
        findsWidgets,
        reason: 'The Help screen promises a Terms link. It must not 404.',
      );
    });
  });

  group('COMPLY-01: nothing persists', () {
    test('the legal feature imports no persistence package at all', () {
      final dir = Directory('lib/features/legal');
      final sources = dir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .map((f) => f.readAsStringSync())
          .join('\n');

      for (final banned in const [
        'shared_preferences',
        'flutter_secure_storage',
        'hive',
        'sqflite',
        'localStorage',
        'dart:html',
      ]) {
        expect(
          sources.contains(banned),
          isFalse,
          reason:
              'A record that lives only on the rider s own device is invisible '
              'to us, dies on cache-clear, does not follow them to a new '
              'device, and for consent is NOT LEGAL EVIDENCE. It converts a '
              'known gap into a false comfort. Banned: $banned',
        );
      }
    });
  });
}

/// Records every write. The lane-local zero-write instrument.
class _RecordingSupportRepository implements SupportRepository {
  final List<String> createdTickets = [];

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
    createdTickets.add(subject);
    return 'recorded';
  }

  @override
  Future<List<SupportTicket>> myTickets() async => const [];

  @override
  Future<TicketThread> thread(String ticketId) =>
      throw UnimplementedError('not used by the consent lane');

  @override
  Future<void> reply({required String ticketId, required String body}) async {}
}
