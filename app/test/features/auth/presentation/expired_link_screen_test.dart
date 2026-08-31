import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/theme/app_theme.dart';
import 'package:hoppin_rider/features/auth/presentation/expired_link_screen.dart';
import 'package:hoppin_rider/shared/widgets/hoppin_button.dart';

Widget _harness(Widget child, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
      home: child,
    );

void main() {
  testWidgets('carries the design heading and subtitle', (tester) async {
    await tester.pumpWidget(_harness(const ExpiredLinkScreen()));

    expect(find.text("We're Almost There"), findsOneWidget);
    expect(
      find.textContaining("We couldn't complete your password reset"),
      findsOneWidget,
    );
  });

  testWidgets('try again invokes the supplied callback', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(
      _harness(ExpiredLinkScreen(onRetry: () => tapped++)),
    );

    await tester.tap(find.widgetWithText(HoppinButton, 'Try Again'));
    await tester.pump();

    expect(tapped, 1);
  });

  testWidgets('try again pops when no callback is supplied', (tester) async {
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: key,
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ExpiredLinkScreen()),
          ),
          child: const Text('open'),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text("We're Almost There"), findsOneWidget);

    await tester.tap(find.widgetWithText(HoppinButton, 'Try Again'));
    await tester.pumpAndSettle();
    expect(find.text("We're Almost There"), findsNothing);
  });

  testWidgets('renders in dark mode', (tester) async {
    await tester.pumpWidget(
        _harness(const ExpiredLinkScreen(), brightness: Brightness.dark));
    expect(find.text("We're Almost There"), findsOneWidget);
  });
}
