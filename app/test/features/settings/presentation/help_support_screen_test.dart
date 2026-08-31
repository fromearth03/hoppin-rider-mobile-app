import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/theme/app_theme.dart';
import 'package:hoppin_rider/features/settings/presentation/help_support_screen.dart';

Widget _harness({Brightness brightness = Brightness.light}) => MaterialApp(
      theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
      home: const HelpSupportScreen(),
    );

void main() {
  testWidgets('shows a Help & Support title and back arrow', (tester) async {
    await tester.pumpWidget(_harness());

    expect(find.text('Help & Support'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
  });

  testWidgets('shows FAQ entries and a contact section', (tester) async {
    await tester.pumpWidget(_harness());

    expect(find.text('Frequently asked questions'), findsOneWidget);
    expect(find.text('Contact us'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('support@hoppin.app'),
      200,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('support@hoppin.app'), findsOneWidget);
  });

  testWidgets('back arrow pops the route', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const HelpSupportScreen()),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Help & Support'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('Help & Support'), findsNothing);
  });

  testWidgets('renders in dark mode', (tester) async {
    await tester.pumpWidget(_harness(brightness: Brightness.dark));
    expect(find.text('Help & Support'), findsOneWidget);
    expect(find.text('Contact us'), findsOneWidget);
  });
}
