import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/theme/app_theme.dart';
import 'package:hoppin_rider/features/settings/presentation/delete_account_screen.dart';

Widget _harness({Brightness brightness = Brightness.light}) => MaterialApp(
      theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
      home: const DeleteAccountScreen(),
    );

void main() {
  testWidgets('shows the title, back arrow and the design copy',
      (tester) async {
    await tester.pumpWidget(_harness());

    expect(find.text('Delete Account'), findsNWidgets(2)); // header + card
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    expect(find.textContaining('Temporarily Deletion'), findsOneWidget);
    expect(find.textContaining('Permanent Deletion'), findsOneWidget);
    expect(find.textContaining('This cannot be undone'), findsOneWidget);
  });

  testWidgets(
      'both buttons are genuinely disabled — no deactivate or delete endpoint '
      'exists, and a live-looking Delete would be worse than none',
      (tester) async {
    await tester.pumpWidget(_harness());

    final buttons =
        tester.widgetList<FilledButton>(find.byType(FilledButton)).toList();
    expect(buttons, hasLength(2));
    for (final b in buttons) {
      expect(b.onPressed, isNull,
          reason: 'a FilledButton with a non-null onPressed here would be a '
              'destructive control wired to nothing');
    }

    // Tapping does nothing and navigates nowhere.
    await tester.tap(find.text('Delete'), warnIfMissed: false);
    await tester.pump();
    expect(find.textContaining('This cannot be undone'), findsOneWidget);
  });

  testWidgets('says plainly how to close an account today', (tester) async {
    await tester.pumpWidget(_harness());

    expect(
      find.textContaining('email Support@hoppin.com'),
      findsOneWidget,
    );
  });

  testWidgets('renders in dark mode', (tester) async {
    await tester.pumpWidget(_harness(brightness: Brightness.dark));
    expect(find.textContaining('Permanent Deletion'), findsOneWidget);
  });
}
