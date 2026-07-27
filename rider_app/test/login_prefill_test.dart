import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/features/auth/login_screen.dart';
import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

/// DEMO-05 seam proof for the rider login.
///
/// The screen reads [loginPrefillProvider] once in initState. With the
/// default (null) the fields start empty — production behavior untouched.
/// With an override the fields boot pre-filled, so the demo's login beat is
/// a single tap on the normal Sign in button.
void main() {
  // One ThemeData reused across pumps (04-02 test-harness trap); the login
  // view reads context.hoppin, so the brand theme must be on the tree.
  final light = HoppinTheme.riderLight();

  List<TextFormField> formFields(WidgetTester tester) =>
      tester.widgetList<TextFormField>(find.byType(TextFormField)).toList();

  testWidgets('fields start empty with no prefill override', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(theme: light, home: const LoginScreen()),
      ),
    );

    final fields = formFields(tester);
    // Sign-in mode shows exactly email + password (name is sign-up only).
    expect(fields, hasLength(2));
    expect(fields[0].controller!.text, isEmpty);
    expect(fields[1].controller!.text, isEmpty);
    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('override seeds email and password before first frame',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          loginPrefillProvider.overrideWithValue(
            (email: 'demo.rider@hoppin.uk', password: 'hoppin-demo'),
          ),
        ],
        child: MaterialApp(theme: light, home: const LoginScreen()),
      ),
    );

    final fields = formFields(tester);
    expect(fields[0].controller!.text, 'demo.rider@hoppin.uk');
    expect(fields[1].controller!.text, 'hoppin-demo');
    // Production-identical chrome: the normal Sign in button still renders.
    expect(find.text('Sign in'), findsOneWidget);
  });
}
