import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/features/comms/url_launcher_gateway.dart';
import 'package:hoppin_rider/features/trip/share_trip_sheet.dart';
import 'package:hoppin_rider/features/trip/widgets/share_link_unavailable_state.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

/// SAFETY-02 acceptance — the share sheet on the DISCLOSED seam #57.
///
/// Wave 0 deleted a "Link copied" snackbar that copied a sentence with NO URL
/// in it. The designed sheet must not reintroduce that lie in a prettier
/// frame. No endpoint issues or revokes a tokenised public tracking URL
/// (#57 / SL-8), so:
///   * NO url may be rendered — not `https://hopp.in/track/DRV-992`, not any;
///   * NOTHING may be written to the clipboard;
///   * the four Figma share targets render (fidelity) but are DISABLED — there
///     is no link to share, and that IS the seam;
///   * the Figma promise "Link expires when trip ends" is rewritten — the
///     backend cannot keep it (Ismail's ruling: truth wins, keep the layout);
///   * a REVOKE control renders (Scope Lock mandates it; the Figma omits it).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Bounded settle — never pumpAndSettle (project convention).
  Future<void> pumpBounded(WidgetTester tester, {int times = 5}) async {
    for (var i = 0; i < times; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  late List<MethodCall> clipboardCalls;
  late _RecordingUrlLauncher launcher;

  setUp(() {
    clipboardCalls = <MethodCall>[];
    launcher = _RecordingUrlLauncher();
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

  /// Presents the REAL sheet through its REAL entry point — the reachability
  /// contract Group C checks (the `show<Name>` idiom).
  Future<void> openSheet(WidgetTester tester, {ThemeData? theme}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [urlLauncherProvider.overrideWithValue(launcher)],
        child: MaterialApp(
          theme: theme ?? HoppinTheme.riderLight(),
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () =>
                      showShareTripSheet(context, rideId: 'r-1'),
                  child: const Text('OPEN'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('OPEN'));
    await pumpBounded(tester);
  }

  group('SAFETY-02 — the share sheet + revoke control (seam #57)', () {
    testWidgets('showShareTripSheet presents the Figma "Share Trip" sheet',
        (tester) async {
      await openSheet(tester);

      expect(find.byType(HopSheet), findsOneWidget,
          reason: 'the sheet is reachable via its real show<Name> entry point');
      expect(find.text('Share Trip'), findsOneWidget,
          reason: 'Figma title fidelity');
      expect(find.textContaining('Share your live trip location'),
          findsOneWidget,
          reason: 'Figma supporting line fidelity');
    });

    testWidgets('CONSTRUCTS the #57 rung in the Link-field slot '
        '(Group C reachability)', (tester) async {
      await openSheet(tester);

      expect(find.byType(ShareLinkUnavailableState), findsOneWidget,
          reason: 'the #57 disclosure must be MOUNTED where the link would be '
              '— a declared-but-never-constructed widget is dead code');
      final size = tester.getSize(find.byType(ShareLinkUnavailableState));
      expect(size.height, greaterThan(24),
          reason: 'the rung is a real-sized designed surface, not a blank');
    });

    // 🔴 NO FABRICATED URL. The whole point of the seam.
    testWidgets('renders NO url — not hopp.in, not any http', (tester) async {
      await openSheet(tester);

      expect(find.textContaining('hopp.in'), findsNothing,
          reason: 'the Figma link https://hopp.in/track/DRV-992 is a MOCKUP. '
              'No endpoint mints a tracking token (#57) — rendering it would '
              'be the deleted "Link copied" lie in a prettier frame');
      expect(find.textContaining('http'), findsNothing,
          reason: 'no URL of any shape may be fabricated');
      expect(find.textContaining('DRV-992'), findsNothing,
          reason: 'the Figma placeholder id must never ship');
    });

    // 🔴 NO CLIPBOARD WRITE. Wave 0 deleted the "Link copied" snackbar.
    testWidgets('writes NOTHING to the clipboard and shows no "Link copied"',
        (tester) async {
      await openSheet(tester);

      // Drive the Copy target — it is disabled, so nothing may happen.
      await tester.tap(find.text('Copy'), warnIfMissed: false);
      await pumpBounded(tester);

      expect(clipboardCalls, isEmpty,
          reason: 'there is no link to copy — a clipboard write here could '
              'only carry a fabrication');
      expect(find.text('Link copied'), findsNothing,
          reason: 'the Wave-0 lie must not return');
    });

    testWidgets('the four Figma targets RENDER but are DISABLED on the seam',
        (tester) async {
      await openSheet(tester);

      for (final target in ['WhatsApp', 'SMS', 'Email', 'Copy']) {
        expect(find.text(target), findsOneWidget,
            reason: '$target renders at Figma fidelity');
        final button = tester.widget<ShareTargetButton>(
          find.ancestor(
            of: find.text(target),
            matching: find.byType(ShareTargetButton),
          ),
        );
        expect(button.onPressed, isNull,
            reason: '$target must be DISABLED — there is no link to share, '
                'and that IS the seam');
      }
    });

    testWidgets('driving every target launches NOTHING', (tester) async {
      await openSheet(tester);

      for (final target in ['WhatsApp', 'SMS', 'Email', 'Copy']) {
        await tester.tap(find.text(target), warnIfMissed: false);
        await pumpBounded(tester);
      }

      expect(launcher.calls, isEmpty,
          reason: 'the share targets do not go through the launcher today — '
              'there is nothing to launch. The launcher is wired at body-swap '
              'time when #57 ships.');
    });

    testWidgets('the REVOKE control renders (Scope Lock mandates it; the Figma '
        'omits it) and is on the rung too', (tester) async {
      await openSheet(tester);

      final revoke = find.byKey(const Key('share.revoke'));
      expect(revoke, findsOneWidget,
          reason: 'ROADMAP success criterion 6: "UI + revoke control on a '
              'seam" — the control must exist even though the Figma frame '
              'never drew one');
      final button = tester.widget<ShareTargetButton>(revoke);
      expect(button.onPressed, isNull,
          reason: 'there is no link to revoke yet — the revoke control is on '
              'the same #57 seam, disclosed not faked');
    });

    testWidgets('the expiry copy is disclosed as FUTURE behaviour, never '
        'asserted as current fact', (tester) async {
      await openSheet(tester);

      expect(find.text('Link expires when trip ends.'), findsNothing,
          reason: 'the backend cannot keep that promise — there is no link and '
              'no expiry. Truth wins, keep the layout.');
      expect(find.textContaining('will expire'), findsOneWidget,
          reason: 'the note survives as the disclosed FUTURE behaviour');
    });

    testWidgets('Done dismisses the sheet', (tester) async {
      await openSheet(tester);

      expect(find.text('Done'), findsOneWidget);
      await tester.ensureVisible(find.text('Done'));
      await pumpBounded(tester);
      await tester.tap(find.text('Done'));
      // Bounded settle across the modal's dismiss animation — never
      // pumpAndSettle (project convention).
      await pumpBounded(tester, times: 12);

      expect(find.byType(HopSheet), findsNothing,
          reason: 'Done closes the sheet (Figma)');
    });

    testWidgets('renders in the dark theme', (tester) async {
      await openSheet(tester, theme: HoppinTheme.riderDark());

      expect(find.byType(ShareLinkUnavailableState), findsOneWidget,
          reason: 'both themes ship — the rung renders in dark too');
    });
  });
}

/// Records any launch attempt so "nothing is launched" is an assertion.
class _RecordingUrlLauncher implements UrlLauncher {
  final List<Uri> calls = <Uri>[];

  @override
  Future<bool> launch(Uri uri) async {
    calls.add(uri);
    return true;
  }
}
