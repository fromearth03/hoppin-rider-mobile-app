import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hoppin_rider/features/comms/url_launcher_gateway.dart';
import 'package:hoppin_rider/features/trip/call_screen.dart';
import 'package:hoppin_rider/features/trip/widgets/call_unavailable_state.dart';
import 'package:hoppin_rider/features/trip/widgets/seam_unavailable_states.dart';
import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

/// COMMS-02 acceptance — the masked-call surface on the DISCLOSED seam #45.
///
/// The requirement is not "a call screen exists". The requirement is that the
/// app **NEVER DIALS**: no `tel:`, no SDK, no launch of any kind. There is no
/// masked-number field on any ride payload and no `POST /rides/:id/call`
/// proxy, so a dial could only ever reach a driver's PERSONAL number — the
/// exact exposure COMMS-02 exists to prevent, and a Scope-Lock hard
/// prohibition.
///
/// So the zero-dials property is asserted MECHANICALLY here, by injecting a
/// recording [UrlLauncher] and driving every interactive element on the
/// screen. Intent is not a control; a recorder is.
void main() {
  const info = RideDriverInfo(
    fullName: 'Gurpreet Singh',
    rating: 4.9,
    ratingCount: 12,
    tripsCount: 1480,
    vehicleMake: 'Toyota',
    vehicleModel: 'Prius',
    vehicleColour: 'Silver',
    plate: 'BK72 WNH',
    etaSeconds: 120,
    originLabel: 'Wolverhampton Rail Station',
    destinationLabel: 'New Cross Hospital',
  );

  /// Bounded settle — never pumpAndSettle (project convention).
  Future<void> pumpBounded(WidgetTester tester, {int times = 4}) async {
    for (var i = 0; i < times; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Boots the REAL call screen over a scripted driver seam and a recording
  /// launcher. [driver] == null exercises the #5 degrade branch.
  Future<_Harness> boot(
    WidgetTester tester, {
    RideDriverInfo? driver = info,
    ThemeData? theme,
  }) async {
    final launcher = _RecordingUrlLauncher();
    final router = GoRouter(
      initialLocation: '/trip/r-1/call',
      routes: [
        GoRoute(
          path: '/trip/:id/call',
          builder: (context, state) =>
              CallScreen(rideId: state.pathParameters['id']!),
        ),
        GoRoute(
          path: '/trip/:id/chat',
          builder: (context, state) =>
              const Scaffold(body: Text('CHAT ROUTE')),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ridesRepositoryProvider.overrideWithValue(_DriverSeamRepo(driver)),
          urlLauncherProvider.overrideWithValue(launcher),
        ],
        child: MaterialApp.router(
          theme: theme ?? HoppinTheme.riderLight(),
          routerConfig: router,
        ),
      ),
    );
    await pumpBounded(tester);
    return _Harness(launcher, router);
  }

  group('COMMS-02 — the inert masked-call surface (seam #45)', () {
    testWidgets('renders the driver identity from the #5 seam', (tester) async {
      await boot(tester);

      expect(find.text('Gurpreet Singh'), findsOneWidget,
          reason: 'the call frame leads with the driver identity (Figma)');
      expect(find.textContaining('4.9'), findsWidgets,
          reason: 'the Figma call frame shows the driver rating');
    });

    testWidgets('degrades to DriverUnavailableCard when the #5 seam is null '
        'and fabricates NOTHING', (tester) async {
      await boot(tester, driver: null);

      expect(find.byType(DriverUnavailableCard), findsOneWidget,
          reason: 'driver identity degrades on seam #5, exactly as the trip '
              'screen does — the call screen never invents a driver');
      expect(find.text('Gurpreet Singh'), findsNothing,
          reason: 'no fabricated identity may leak onto the null branch');
    });

    testWidgets('CONSTRUCTS the #45 unavailable rung on the real screen '
        '(Group C reachability)', (tester) async {
      await boot(tester);

      expect(find.byType(CallUnavailableState), findsOneWidget,
          reason: 'the #45 disclosure must be MOUNTED on the real view — a '
              'declared-but-never-constructed widget is dead code wearing a '
              'compliance badge');
      final size = tester.getSize(find.byType(CallUnavailableState));
      expect(size.height, greaterThan(48),
          reason: 'the rung is a real-sized designed surface, not a blank');
    });

    testWidgets('discloses honestly — it never claims the call is connecting',
        (tester) async {
      await boot(tester);

      expect(find.textContaining('not live yet'), findsWidgets,
          reason: 'the screen plainly states masked calling is not live yet');
      expect(find.text('Calling….'), findsNothing,
          reason: 'the Figma "Calling…." status line would be a LIE — nothing '
              'is being called');
    });

    testWidgets('offers "Open chat" as the working alternative and routes to '
        '/trip/:id/chat', (tester) async {
      final h = await boot(tester);

      final chatAction = find.text('Open chat');
      expect(chatAction, findsOneWidget,
          reason: 'chat is the BOUND comms surface — the seam must hand the '
              'rider a working alternative, not a dead end');
      await tester.ensureVisible(chatAction);
      await pumpBounded(tester);
      await tester.tap(chatAction);
      await pumpBounded(tester);

      // The load-bearing assertion: the rider actually ARRIVES at the chat.
      // That is the property this test exists to defend — the #45 seam must
      // hand them a comms surface that works, not a dead end.
      expect(find.text('CHAT ROUTE'), findsOneWidget,
          reason: 'the alternative must actually navigate to the chat route');

      // There WAS a second assertion here, on
      // `router.currentConfiguration.uri`, and it was the wrong instrument.
      //
      // Chat is now PUSHED rather than `go`-ne to, so that the rider can come
      // BACK to the call surface they opened it from (`go` replaces the route,
      // which leaves `canPop()` false and strands them — the same defect that
      // left the SOS screen with no exit). Under a push, go_router stacks the
      // chat PAGE over the current one, and in THIS harness — which declares
      // `/trip/:id/call` and `/trip/:id/chat` as flat SIBLINGS rather than the
      // real app's nested tree — `currentConfiguration` keeps reporting the
      // base route even though the chat is on screen and visible above it.
      //
      // So the probe was not measuring "did the rider reach chat?" It was
      // measuring "did we navigate the way this fake router happens to model
      // it." The app's own router is the source of truth for that, and
      // `router_reachability_test.dart` already asks it. Asserting on a
      // hand-built router's internals is how a test comes to prove only that
      // its own router works — the exact trap this project has been bitten by
      // before.
    });

    testWidgets('renders all THREE Figma layouts: calling / ringing / '
        'connected', (tester) async {
      await boot(tester);

      for (final phase in CallFramePhase.values) {
        expect(
          find.byWidgetPredicate(
            (w) => w is CallScreen,
          ),
          findsOneWidget,
          reason: 'the screen hosts the frame switcher',
        );
        // Each frame is a renderable state of the screen, driven by the
        // (inert) frame selector — this is Figma layout fidelity, not a call.
        await tester.tap(find.byKey(Key('call.frame.${phase.name}')));
        await pumpBounded(tester);
        expect(find.byKey(Key('call.frame.body.${phase.name}')), findsOneWidget,
            reason: 'the ${phase.name} frame layout must be renderable');
      }
    });

    testWidgets('the connected frame timer is INERT layout — it never ticks a '
        'fake call duration', (tester) async {
      await boot(tester);

      await tester.tap(find.byKey(const Key('call.frame.connected')));
      await pumpBounded(tester);

      final before = tester
          .widget<Text>(find.byKey(const Key('call.connected.timer')))
          .data;
      // Five seconds of real pumped time. A fake Timer.periodic would move it.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      final after = tester
          .widget<Text>(find.byKey(const Key('call.connected.timer')))
          .data;

      expect(after, before,
          reason: 'the Figma 00:01 is INERT LAYOUT. A running clock would be '
              'a counterfeit call duration — there is no call.');
    });

    // 🔴 THE ZERO-DIALS ASSERTION. This is the requirement.
    testWidgets('the app NEVER dials — every interactive element is driven and '
        'the recording launcher sees ZERO launches', (tester) async {
      final h = await boot(tester);

      // Drive EVERY tappable on the screen, in every frame.
      for (final phase in CallFramePhase.values) {
        await tester.tap(find.byKey(Key('call.frame.${phase.name}')));
        await pumpBounded(tester);
        for (final finder in [
          find.byKey(const Key('call.action.hangup')),
          find.byKey(const Key('call.action.mute')),
          find.byKey(const Key('call.action.speaker')),
        ]) {
          if (finder.evaluate().isNotEmpty) {
            await tester.tap(finder, warnIfMissed: false);
            await pumpBounded(tester);
          }
        }
      }

      expect(h.launcher.calls, isEmpty,
          reason: 'the app must NEVER dial a real number: there is no masked '
              'proxy (#45), so any launch could only reach the driver\'s '
              'PERSONAL number — the exact exposure COMMS-02 prevents');
    });

    testWidgets('renders in the dark theme without raw colours failing',
        (tester) async {
      await boot(tester, theme: HoppinTheme.riderDark());

      expect(find.byType(CallUnavailableState), findsOneWidget,
          reason: 'both themes ship — the rung renders in dark too');
    });
  });
}

class _Harness {
  _Harness(this.launcher, this.router);

  final _RecordingUrlLauncher launcher;
  final GoRouter router;
}

/// The instrument that turns "we never dial" from an intention into an
/// assertion. Every launch attempt is recorded and NONE is expected.
class _RecordingUrlLauncher implements UrlLauncher {
  final List<Uri> calls = <Uri>[];

  @override
  Future<bool> launch(Uri uri) async {
    calls.add(uri);
    return true;
  }
}

/// The #5 driver-identity seam, scripted. `null` is the LIVE shape.
class _DriverSeamRepo implements RidesRepository {
  _DriverSeamRepo(this.driver);

  final RideDriverInfo? driver;

  @override
  Future<RideDriverInfo?> driverInfo(String rideId) async => driver;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
