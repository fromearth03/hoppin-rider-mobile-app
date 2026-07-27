import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/features/launch/launch_gate.dart';
import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

/// The launch gate — the operator's kill switch over EVERY route. These pin the
/// three things that must never regress: a maintenance/force block fully
/// replaces the app, a soft-nudge or ok does NOT, and an unresolved/failed
/// check fails OPEN (the app shows through).
void main() {
  const child = Key('app-child');

  /// Pumps the gate with the provider overridden to produce [data] (or, when
  /// null, a state chosen by [loading]/[error]).
  Future<void> pump(
    WidgetTester tester, {
    AppStatus? data,
    bool loading = false,
    bool error = false,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appStatusProvider.overrideWith((ref) {
            if (loading) return Completer<AppStatus>().future; // never resolves
            if (error) throw Exception('boom');
            return data!;
          }),
        ],
        child: MaterialApp(
          theme: HoppinTheme.riderLight(),
          home: const LaunchGate(
            child: SizedBox(key: child, width: 10, height: 10),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('maintenance BLOCKS — the app is replaced entirely',
      (tester) async {
    await pump(tester, data: const AppStatus(maintenanceMode: true));

    expect(find.byKey(child), findsNothing);
    expect(find.textContaining('maintenance'), findsOneWidget);
  });

  testWidgets('force update BLOCKS with an update action', (tester) async {
    await pump(tester, data: const AppStatus(forceUpdateRequired: true));

    expect(find.byKey(child), findsNothing);
    expect(find.text('Update required'), findsOneWidget);
    expect(find.text('Update now'), findsOneWidget);
  });

  testWidgets('a soft nudge does NOT block — the app shows through',
      (tester) async {
    await pump(tester, data: const AppStatus(updateAvailable: true));

    expect(find.byKey(child), findsOneWidget,
        reason: 'update-available is a dismissible nudge, never a launch wall');
  });

  testWidgets('ok shows the app', (tester) async {
    await pump(tester, data: const AppStatus());
    expect(find.byKey(child), findsOneWidget);
  });

  testWidgets('an UNRESOLVED check FAILS OPEN — app shows, no block',
      (tester) async {
    // Loading (the real launch instant): the gate must not paint a block or a
    // spinner over a working app while the status is still in flight.
    await pump(tester, loading: true);

    expect(find.byKey(child), findsOneWidget);
    expect(find.textContaining('maintenance'), findsNothing);
    expect(find.text('Update required'), findsNothing);
  });

  testWidgets('an ERRORED check FAILS OPEN — app shows, no block',
      (tester) async {
    await pump(tester, error: true);

    expect(find.byKey(child), findsOneWidget,
        reason: 'a failed launch check must never lock a user out');
  });
}
