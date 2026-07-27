import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/features/location/location_providers.dart';
import 'package:hoppin_rider/features/location/location_service.dart';
import 'package:hoppin_rider/features/safety/safety_screen.dart';
import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

/// SAFETY-01 — SOS + GPS.
///
/// 🔴 The sharpest test in this file (and in the phase) is the FIRST one:
/// **location failure DEGRADES the SOS payload; it must NEVER block the alarm.**
/// A safety feature that fails closed on a denied permission is worse than one
/// that sends an imprecise alert.
///
/// The other three: coordinates ARE attached when available (the Figma modal
/// promises "will immediately send your location" — that promise must be true),
/// the SOS still logs on a cancelled trip (`rideId: null`), and the OS
/// permission dance never gates the panic path.

/// A scriptable [LocationService] double: answer, refuse, or hang.
class _ScriptedLocationService implements LocationService {
  _ScriptedLocationService({
    this.fix,
    this.hang = false,
    this.granted = true,
  });

  /// The coordinates a successful read yields. Null = "no fix available".
  final ({double lat, double lng})? fix;

  /// When true the read never completes (until the caller's own bound fires).
  final bool hang;

  /// Whether the OS has already granted permission.
  final bool granted;

  int reads = 0;
  int permissionPrompts = 0;

  @override
  Future<LocationPermissionResult> requestPermission() async {
    // If this EVER increments on the SOS path, the OS dialog is standing
    // between a frightened rider and the alarm. That is the defect.
    permissionPrompts++;
    return granted
        ? LocationPermissionResult.granted
        : LocationPermissionResult.denied;
  }

  @override
  Future<bool> hasPermission() async => granted;

  @override
  Future<({double lat, double lng})?> currentPosition({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    reads++;
    if (!granted) return null; // short-circuits — never prompts
    if (hang) {
      // The real impl bounds this internally; the double emulates the *result*
      // of that bound (null at the deadline) so the widget test stays fast.
      await Future<void>.delayed(timeout);
      return null;
    }
    return fix;
  }
}

/// Records every `raiseSos` argument set so the test can assert on the payload
/// the rider's panic actually produced.
class _RecordingSafetyRepository implements SafetyRepository {
  final calls = <({String? rideId, double? lat, double? lng, String? note})>[];

  @override
  Future<String> raiseSos({
    String? rideId,
    double? lat,
    double? lng,
    String? note,
    String? liveShareUrl,
  }) async {
    calls.add((rideId: rideId, lat: lat, lng: lng, note: note));
    return 'c4000000-0000-4000-8000-000000000001';
  }

  @override
  Future<List<SosEvent>> myEvents() async => const [];
}

Future<void> _pumpSafety(
  WidgetTester tester, {
  required _ScriptedLocationService location,
  required _RecordingSafetyRepository safety,
  String? rideId,
  ThemeData? theme,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        locationServiceProvider.overrideWithValue(location),
        safetyRepositoryProvider.overrideWithValue(safety),
      ],
      child: MaterialApp(
        theme: theme ?? HoppinTheme.riderLight(),
        home: SafetyScreen(rideId: rideId),
      ),
    ),
  );
  // Bounded pumps only — never pumpAndSettle.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// Opens the confirm modal and taps through to the raise, pumping only until
/// the SOS has actually been recorded.
///
/// Bounded pumps — never `pumpAndSettle`. It stops the moment the raise lands
/// so the confirmation snackbar has not yet auto-dismissed: what the rider is
/// TOLD about their location is part of the contract, so the test must still be
/// able to see it.
Future<void> _raiseSos(
  WidgetTester tester,
  _RecordingSafetyRepository safety,
) async {
  await tester.tap(find.byKey(const Key('sos_raise_button')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));

  expect(find.text('Trigger Emergency Alert?'), findsOneWidget,
      reason: 'the Figma SOS confirm frame must be what a rider sees');

  await tester.tap(find.byKey(const Key('sos_confirm_button')));
  await tester.pump();

  // Worst case is the 5s location bound. Anything beyond ~7s means the alarm
  // is hanging — which is exactly the defect these tests exist to catch.
  for (var i = 0; i < 14 && safety.calls.isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 500));
  }
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets(
      '🔴 DEGRADE-NOT-BLOCK: the SOS STILL FIRES when location is '
      'unavailable — lat/lng null, and the rider is TOLD', (tester) async {
    // Location hangs past its bound and resolves to no fix — the worst case:
    // denied / timed out / the browser simply never answered.
    final location = _ScriptedLocationService(hang: true);
    final safety = _RecordingSafetyRepository();

    await _pumpSafety(
      tester,
      location: location,
      safety: safety,
      rideId: 'ride-1',
    );
    await _raiseSos(tester, safety);

    expect(safety.calls, hasLength(1),
        reason: '🔴 THE HARD RULE: a location failure DEGRADES the payload, it '
            'NEVER blocks the alarm. An SOS that fails to send because GPS '
            'failed is a worse safety defect than an imprecise one');
    expect(safety.calls.single.lat, isNull,
        reason: 'no fix means NO coordinate — never a fabricated or default '
            'lat (no backend holes: send none and disclose it)');
    expect(safety.calls.single.lng, isNull,
        reason: 'no fix means NO coordinate — never a fabricated default lng');
    expect(safety.calls.single.rideId, 'ride-1',
        reason: 'the trip is still attached even when the GPS is not');

    // The rider must KNOW the alert went without their location, so they can
    // say where they are. A silently locationless SOS is its own lie.
    expect(
      find.textContaining('could not get your location'),
      findsOneWidget,
      reason: 'an SOS that quietly ships without coordinates, while the modal '
          'promised "will immediately send your location", is a lie — the '
          'rider must be told to say where they are',
    );

    // The button must not be left spinning or disabled: the rider can raise
    // again.
    final button = tester.widget<HopButton>(
      find.byKey(const Key('sos_raise_button')),
    );
    expect(button.onPressed, isNotNull,
        reason: 'the SOS button must never hang or latch disabled after a '
            'location failure — the rider can always raise again');
  });

  testWidgets(
      'HAPPY PATH: a real fix is attached to raiseSos and the rider is told '
      'their location went with it', (tester) async {
    final location =
        _ScriptedLocationService(fix: (lat: 52.5862, lng: -2.1281));
    final safety = _RecordingSafetyRepository();

    await _pumpSafety(
      tester,
      location: location,
      safety: safety,
      rideId: 'ride-1',
    );
    await _raiseSos(tester, safety);

    expect(safety.calls, hasLength(1), reason: 'the SOS must fire');
    expect(safety.calls.single.lat, 52.5862,
        reason: 'SAFETY-01 requires trip + GPS — the coordinates the device '
            'gave us must reach POST /me/sos');
    expect(safety.calls.single.lng, -2.1281,
        reason: 'SAFETY-01 requires trip + GPS — the longitude must reach the '
            'safety team');
    expect(
      find.textContaining('with your location'),
      findsOneWidget,
      reason: 'the modal promised the location; the confirmation must honour '
          'the promise it made',
    );
  });

  testWidgets(
      'CANCELLED TRIP: rideId null still raises an SOS (SAFETY-01: logged '
      'even if cancelled)', (tester) async {
    final location =
        _ScriptedLocationService(fix: (lat: 52.5862, lng: -2.1281));
    final safety = _RecordingSafetyRepository();

    // No ride: opened from home, or the trip was cancelled out from under the
    // rider mid-panic.
    await _pumpSafety(tester, location: location, safety: safety);
    await _raiseSos(tester, safety);

    expect(safety.calls, hasLength(1),
        reason: 'the Scope Lock requires the SOS to be logged even when the '
            'trip is cancelled — no trip is not a reason to swallow a panic');
    expect(safety.calls.single.rideId, isNull,
        reason: 'no trip means no ride_id — never a fabricated one');
    expect(safety.calls.single.lat, 52.5862,
        reason: 'GPS is still attached when the trip is gone — the coordinates '
            'are the only thing the safety team has to go on');
  });

  testWidgets(
      'NO PERMISSION-DANCE ON THE PANIC PATH: with permission absent the SOS '
      'fires immediately, unprompted, with a null fix', (tester) async {
    final location = _ScriptedLocationService(granted: false);
    final safety = _RecordingSafetyRepository();

    await _pumpSafety(
      tester,
      location: location,
      safety: safety,
      rideId: 'ride-1',
    );
    await _raiseSos(tester, safety);

    expect(location.permissionPrompts, 0,
        reason: 'the OS permission dialog must NEVER be the thing standing '
            'between a frightened rider and the SOS button');
    expect(safety.calls, hasLength(1),
        reason: 'a denied permission degrades the payload — it does not veto '
            'the alarm');
    expect(safety.calls.single.lat, isNull,
        reason: 'no permission, no fix — and no fabricated coordinate');
  });

  testWidgets('the confirm modal renders on tokens in DARK theme too',
      (tester) async {
    final location =
        _ScriptedLocationService(fix: (lat: 52.5862, lng: -2.1281));
    final safety = _RecordingSafetyRepository();

    await _pumpSafety(
      tester,
      location: location,
      safety: safety,
      rideId: 'ride-1',
      theme: HoppinTheme.riderDark(),
    );

    await tester.tap(find.byKey(const Key('sos_raise_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Trigger Emergency Alert?'), findsOneWidget,
        reason: 'the SOS modal must render in both themes — a rider in dark '
            'mode gets the same warning');
    expect(
      find.textContaining('cannot be undone'),
      findsOneWidget,
      reason: 'the Figma regulatory-incident warning must be present in both '
          'themes',
    );
  });

  testWidgets('cancelling the confirm modal raises NOTHING', (tester) async {
    final location =
        _ScriptedLocationService(fix: (lat: 52.5862, lng: -2.1281));
    final safety = _RecordingSafetyRepository();

    await _pumpSafety(
      tester,
      location: location,
      safety: safety,
      rideId: 'ride-1',
    );

    await tester.tap(find.byKey(const Key('sos_raise_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('sos_cancel_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(safety.calls, isEmpty,
        reason: 'the confirm modal is the accident guard — cancelling it must '
            'never raise a regulatory incident');
    expect(location.reads, 0,
        reason: 'no location is read for an SOS the rider did not confirm');
  });
}
