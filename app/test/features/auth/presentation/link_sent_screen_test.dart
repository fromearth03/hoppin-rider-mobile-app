import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/theme/app_theme.dart';
import 'package:hoppin_rider/features/auth/presentation/link_sent_screen.dart';
import 'package:hoppin_rider/shared/widgets/hoppin_button.dart';

Widget _harness(Widget child, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
      home: child,
    );

void main() {
  testWidgets('carries the design heading and subtitle', (tester) async {
    await tester.pumpWidget(_harness(const LinkSentScreen()));

    expect(find.text('Check your email'), findsOneWidget);
    expect(
      find.textContaining(
          'We\'ve sent you a password reset link'),
      findsOneWidget,
    );
  });

  testWidgets('never confirms an account exists for a specific address',
      (tester) async {
    // Same discipline as ForgotPasswordScreen's own confirmation: the copy
    // must not state that an email was sent to a specific address in a way
    // that confirms whether that account exists.
    await tester.pumpWidget(
      const MaterialApp(home: LinkSentScreen(email: 'ada@example.com')),
    );

    expect(find.textContaining('If an account exists'), findsOneWidget);
    expect(find.textContaining('ada@example.com'), findsOneWidget);
  });

  testWidgets('renders without an email argument', (tester) async {
    await tester.pumpWidget(_harness(const LinkSentScreen()));

    expect(find.text('Check your email'), findsOneWidget);
  });

  testWidgets('back to login pops the route', (tester) async {
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: key,
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const LinkSentScreen()),
          ),
          child: const Text('open'),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Check your email'), findsOneWidget);

    await tester.tap(find.widgetWithText(HoppinButton, 'Back to login'));
    await tester.pumpAndSettle();
    expect(find.text('Check your email'), findsNothing);
  });

  testWidgets('renders in dark mode', (tester) async {
    await tester.pumpWidget(
        _harness(const LinkSentScreen(), brightness: Brightness.dark));
    expect(find.text('Check your email'), findsOneWidget);
  });
}
