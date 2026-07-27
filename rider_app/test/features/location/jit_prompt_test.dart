import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/features/location/jit_location_prompt.dart';
import 'package:hoppin_rider/features/location/location_service.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

/// COMPLY-02 — the just-in-time OS location prompt.
///
/// Plain-English purpose text MUST render BEFORE any OS permission request; the
/// prompt must NEVER fire over an active ride (a `canPrompt` gate returns false
/// while a trip is live). A fake [LocationService] keeps the widget test off
/// real OS APIs.
class _FakeLocationService implements LocationService {
  int requestCount = 0;
  LocationPermissionResult result = LocationPermissionResult.granted;

  @override
  Future<LocationPermissionResult> requestPermission() async {
    requestCount++;
    return result;
  }

  @override
  Future<bool> hasPermission() async => false;

  /// SAFETY-01 widened the interface. This prompt never reads a fix — it only
  /// asks for consent — so the double refuses, proving the JIT path and the
  /// position read stay independent.
  @override
  Future<({double lat, double lng})?> currentPosition({
    Duration timeout = const Duration(seconds: 5),
  }) async =>
      null;
}

void main() {
  final light = HoppinTheme.riderLight();

  testWidgets('shows purpose text BEFORE requesting permission',
      (tester) async {
    final svc = _FakeLocationService();
    await tester.pumpWidget(
      MaterialApp(
        theme: light,
        home: Scaffold(
          body: JitLocationPrompt(
            service: svc,
            canPrompt: true,
            onResult: (_) {},
          ),
        ),
      ),
    );

    // Purpose-first: the rationale is on screen and no request has fired yet.
    expect(find.textContaining('find nearby drivers'), findsOneWidget);
    expect(svc.requestCount, 0,
        reason: 'purpose text must precede the OS request');

    // Only an explicit user tap triggers the request.
    await tester.tap(find.byKey(const Key('jit_allow_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(svc.requestCount, 1);
  });

  testWidgets('the allow action is gated OFF during an active trip',
      (tester) async {
    final svc = _FakeLocationService();
    await tester.pumpWidget(
      MaterialApp(
        theme: light,
        home: Scaffold(
          body: JitLocationPrompt(
            service: svc,
            canPrompt: false, // an active ride is in progress
            onResult: (_) {},
          ),
        ),
      ),
    );

    // Never a consent wall over an active ride: the request cannot fire.
    final button = tester.widget<JitLocationPrompt>(
      find.byType(JitLocationPrompt),
    );
    expect(button.canPrompt, isFalse);

    // Even if the button is present, tapping must not request during a trip.
    final allow = find.byKey(const Key('jit_allow_button'));
    if (allow.evaluate().isNotEmpty) {
      await tester.tap(allow, warnIfMissed: false);
      await tester.pump();
    }
    expect(svc.requestCount, 0);
  });
}
