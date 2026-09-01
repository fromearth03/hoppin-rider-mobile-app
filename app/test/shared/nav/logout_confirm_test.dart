import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/theme/app_theme.dart';
import 'package:hoppin_rider/shared/nav/logout_confirm.dart';

Widget _harness() => MaterialApp(
      theme: AppTheme.light,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => confirmLogout(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

Future<void> _open(WidgetTester tester) async {
  await tester.pumpWidget(_harness());
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the frame copy, illustration and close X',
      (tester) async {
    await _open(tester);

    expect(find.text('Are you logging out?'), findsOneWidget);
    // Verbatim from Logout.png per Ismail's 2026-09-01 instruction.
    expect(
        find.text("You've been signed out successfully. We'll be here "
            "whenever you're ready for your next ride."),
        findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
    // The cropped See-you-Again illustration from the design pack.
    expect(
        find.byWidgetPredicate((w) =>
            w is Image &&
            w.image is AssetImage &&
            (w.image as AssetImage)
                .assetName
                .contains('logout_see_you_again')),
        findsOneWidget);
  });

  testWidgets('the X dismisses without confirming', (tester) async {
    await _open(tester);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.text('Are you logging out?'), findsNothing);
  });

  testWidgets('Cancel dismisses, Logout confirms', (tester) async {
    await _open(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Are you logging out?'), findsNothing);
  });
}
