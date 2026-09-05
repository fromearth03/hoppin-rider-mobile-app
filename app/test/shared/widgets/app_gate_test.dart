import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/app_status.dart';
import 'package:hoppin_rider/core/theme/app_theme.dart';
import 'package:hoppin_rider/shared/widgets/app_gate.dart';

Widget _harness(AsyncValue<AppStatus> status) => ProviderScope(
      overrides: [
        appStatusProvider.overrideWith((ref) => switch (status) {
              AsyncData(:final value) => Future.value(value),
              AsyncError(:final error) => Future<AppStatus>.error(error),
              _ => Completer<AppStatus>().future, // never completes
            }),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const AppGate(child: Text('the app')),
      ),
    );

void main() {
  testWidgets('maintenance mode replaces the whole app', (tester) async {
    await tester.pumpWidget(
        _harness(const AsyncData(AppStatus(maintenanceMode: true))));
    await tester.pumpAndSettle();

    expect(find.text('the app'), findsNothing);
    expect(find.text('Hoppin is down for maintenance'), findsOneWidget);
  });

  testWidgets("shows the operator's own message when they set one",
      (tester) async {
    await tester.pumpWidget(_harness(const AsyncData(AppStatus(
      maintenanceMode: true,
      maintenanceMessage: 'Back around 6pm — upgrading payments.',
    ))));
    await tester.pumpAndSettle();

    expect(find.text('Back around 6pm — upgrading payments.'), findsOneWidget);
  });

  testWidgets('a forced update blocks the app', (tester) async {
    await tester.pumpWidget(
        _harness(const AsyncData(AppStatus(forceUpdateRequired: true))));
    await tester.pumpAndSettle();

    expect(find.text('the app'), findsNothing);
    expect(find.text('Update required'), findsOneWidget);
  });

  testWidgets('a failed check must never lock the rider out', (tester) async {
    // The gate is a kill switch. An unreachable server must not be able to
    // trip one — a rider at the kerb on a flaky connection would be locked
    // out of a working app by a request that never arrived.
    await tester.pumpWidget(_harness(AsyncError('boom', StackTrace.empty)));
    await tester.pumpAndSettle();

    expect(find.text('the app'), findsOneWidget);
  });

  testWidgets('the app is not held behind the check while it loads',
      (tester) async {
    await tester.pumpWidget(_harness(const AsyncLoading()));
    await tester.pump();

    expect(find.text('the app'), findsOneWidget);
  });
}
