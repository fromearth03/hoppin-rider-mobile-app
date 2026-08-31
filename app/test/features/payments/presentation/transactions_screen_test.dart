import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/theme/app_theme.dart';
import 'package:hoppin_rider/features/payments/presentation/transactions_screen.dart';

Widget _harness({
  Brightness brightness = Brightness.light,
  List<Override> overrides = const [],
}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
        home: const TransactionsScreen(),
      ),
    );

void main() {
  group('TransactionsScreen', () {
    testWidgets('has a title identifying it as Recent Payments',
        (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      expect(find.text('Recent Payments'), findsOneWidget);
    });

    testWidgets(
        'renders an honest empty state — there is no /me/transactions client yet',
        (tester) async {
      // GET /api/v1/me/transactions is documented in
      // docs/PAYMENTS-STRIPE.md and docs/SCREEN-DECISIONS.md, but no
      // repository method calls it anywhere in this app. The screen must
      // never fabricate rows to fill the design — it renders a real,
      // clearly-labelled empty state instead.
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      expect(find.textContaining('No recent payments'), findsOneWidget);
      // Nothing that looks like a fabricated transaction row.
      expect(find.byType(ListTile), findsNothing);
    });

    testWidgets('renders in dark mode', (tester) async {
      await tester.pumpWidget(_harness(brightness: Brightness.dark));
      await tester.pumpAndSettle();

      expect(find.text('Recent Payments'), findsOneWidget);
      expect(find.textContaining('No recent payments'), findsOneWidget);
    });

    testWidgets('has a working back action', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    });

    testWidgets('never renders a fabricated card or amount', (tester) async {
      // "No demo fakeness" — this screen must not show a sample Visa row or
      // any invented amount, ever, since there is no backend for it.
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      expect(find.textContaining('Visa'), findsNothing);
      expect(find.textContaining('£'), findsNothing);
    });
  });
}
