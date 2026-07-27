import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/features/booking/widgets/service_unavailable_screen.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

/// BOOK-07 (decision A) — the outside-service-area rung is a DESIGNED
/// unavailable state, not a dead end: an honest "not in your area yet"
/// message with a clear exit back to a usable surface. Token-driven,
/// non-blank, built from the Phase-8 kit (HopEmptyState + HopButton).
void main() {
  Widget host(Widget child) => MaterialApp(
        theme: HoppinTheme.riderLight(),
        home: Scaffold(body: child),
      );

  /// Bounded pump — never pumpAndSettle (project convention).
  Future<void> pumpBounded(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('renders a designed HopEmptyState with headline + copy',
      (tester) async {
    await tester.pumpWidget(host(ServiceUnavailableScreen(onExit: () {})));
    await pumpBounded(tester);

    // Built from the designed empty-state component, not raw Text soup.
    expect(find.byType(HopEmptyState), findsOneWidget);

    // Non-blank: the honest headline + Wolverhampton-only supporting copy.
    expect(find.textContaining('area', findRichText: true), findsWidgets);
    expect(find.textContaining('Wolverhampton', findRichText: true),
        findsWidgets);
  });

  testWidgets('offers a working exit affordance (no dead end)',
      (tester) async {
    var exited = false;
    await tester.pumpWidget(
      host(ServiceUnavailableScreen(onExit: () => exited = true)),
    );
    await pumpBounded(tester);

    // The exit is a designed HopButton, never a stock button.
    final exit = find.byType(HopButton);
    expect(exit, findsOneWidget);

    await tester.tap(exit);
    await pumpBounded(tester);
    expect(exited, isTrue, reason: 'tapping the exit fires onExit');
  });
}
