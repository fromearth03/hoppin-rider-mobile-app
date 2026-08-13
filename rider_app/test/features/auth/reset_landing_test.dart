import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/features/auth/reset_landing_screen.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

void main() {
  final light = HoppinTheme.riderLight();

  testWidgets('password and confirmation visibility toggle independently', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(theme: light, home: const ResetLandingScreen()),
      ),
    );

    List<TextField> fields() =>
        tester.widgetList<TextField>(find.byType(TextField)).toList();

    expect(fields(), hasLength(2));
    expect(fields()[0].obscureText, isTrue);
    expect(fields()[1].obscureText, isTrue);
    expect(find.byTooltip('Show password'), findsOneWidget);
    expect(find.byTooltip('Show confirmation password'), findsOneWidget);

    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(fields()[0].obscureText, isFalse);
    expect(fields()[1].obscureText, isTrue);

    await tester.tap(find.byTooltip('Show confirmation password'));
    await tester.pump();
    expect(fields()[0].obscureText, isFalse);
    expect(fields()[1].obscureText, isFalse);
  });
}
