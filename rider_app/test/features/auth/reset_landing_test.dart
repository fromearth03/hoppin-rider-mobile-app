import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/features/auth/reset_landing_screen.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

/// Password-reset deep-link landing — real set-password form.
void main() {
  final light = HoppinTheme.riderLight();

  testWidgets('renders the set-password form', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: light, home: const ResetLandingScreen()),
    );

    expect(find.text('Set a new password'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(find.byType(HopEmptyState), findsNothing);
    expect(find.textContaining("isn't active yet"), findsNothing);
    expect(find.text('Contact support'), findsNothing);
  });
}
