import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/theme/app_theme.dart';
import 'package:hoppin_rider/features/auth/presentation/reset_password_screen.dart';
import 'package:hoppin_rider/features/auth/presentation/widgets/auth_scaffold.dart';
import 'package:hoppin_rider/shared/widgets/hoppin_button.dart';

Widget _harness(Widget child, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
      home: child,
    );

void main() {
  testWidgets('carries the design heading and subtitle', (tester) async {
    await tester.pumpWidget(_harness(const ResetPasswordScreen()));

    // "Reset Password" appears twice: the AuthScaffold heading and the
    // submit button label. The AuthScaffold constructor argument is the
    // unambiguous source of truth for the heading.
    final scaffold = tester.widget<AuthScaffold>(find.byType(AuthScaffold));
    expect(scaffold.title, 'Reset Password');
    expect(
      find.textContaining('must be atleast 8 characters'),
      findsOneWidget,
    );
  });

  testWidgets('renders the two password fields with in-field eye toggles',
      (tester) async {
    await tester.pumpWidget(_harness(const ResetPasswordScreen()));

    expect(find.text('Set New Password'), findsOneWidget);
    expect(find.text('Confirm New Password'), findsOneWidget);
    // One eye toggle per obscurable field — no custom "show password" button.
    expect(find.byIcon(Icons.visibility_outlined), findsNWidgets(2));
  });

  testWidgets('the button is disabled until both fields are filled',
      (tester) async {
    await tester.pumpWidget(_harness(const ResetPasswordScreen()));

    HoppinButton button() => tester.widget<HoppinButton>(
        find.widgetWithText(HoppinButton, 'Reset Password'));
    expect(button().onPressed, isNull);

    final fields = find.byType(TextField);
    await tester.enterText(fields.first, 'longenoughpw');
    await tester.pump();
    expect(button().onPressed, isNull);
  });

  testWidgets('the button stays disabled under 8 characters', (tester) async {
    await tester.pumpWidget(_harness(const ResetPasswordScreen()));

    final fields = find.byType(TextField);
    await tester.enterText(fields.first, 'short1');
    await tester.enterText(fields.last, 'short1');
    await tester.pump();

    HoppinButton button() => tester.widget<HoppinButton>(
        find.widgetWithText(HoppinButton, 'Reset Password'));
    expect(button().onPressed, isNull);
    expect(find.textContaining('at least 8 characters'), findsWidgets);
  });

  testWidgets('the button stays disabled when the two fields do not match',
      (tester) async {
    await tester.pumpWidget(_harness(const ResetPasswordScreen()));

    final fields = find.byType(TextField);
    await tester.enterText(fields.first, 'longenoughpw');
    await tester.enterText(fields.last, 'differentpassword');
    await tester.pump();

    HoppinButton button() => tester.widget<HoppinButton>(
        find.widgetWithText(HoppinButton, 'Reset Password'));
    expect(button().onPressed, isNull);
    expect(find.textContaining('do not match'), findsOneWidget);
  });

  testWidgets('the button enables once both fields match and meet the rule',
      (tester) async {
    await tester.pumpWidget(_harness(const ResetPasswordScreen()));

    final fields = find.byType(TextField);
    await tester.enterText(fields.first, 'longenoughpw');
    await tester.enterText(fields.last, 'longenoughpw');
    await tester.pump();

    HoppinButton button() => tester.widget<HoppinButton>(
        find.widgetWithText(HoppinButton, 'Reset Password'));
    expect(button().onPressed, isNotNull);
  });

  testWidgets(
      'submitting reports the reset path is unavailable rather than faking success',
      (tester) async {
    // AuthRepository has no method to complete a password reset (no
    // updateUser/setSession-backed call exists). The screen must not invent
    // one or pretend the submission succeeded.
    await tester.pumpWidget(_harness(const ResetPasswordScreen()));

    final fields = find.byType(TextField);
    await tester.enterText(fields.first, 'longenoughpw');
    await tester.enterText(fields.last, 'longenoughpw');
    await tester.pump();

    await tester.tap(find.widgetWithText(HoppinButton, 'Reset Password'));
    await tester.pumpAndSettle();

    expect(find.textContaining('not yet available'), findsOneWidget);
  });

  testWidgets('an injected onSubmit callback is honoured instead',
      (tester) async {
    String? submitted;
    await tester.pumpWidget(_harness(ResetPasswordScreen(
      onSubmit: (password) async {
        submitted = password;
        return true;
      },
    )));

    final fields = find.byType(TextField);
    await tester.enterText(fields.first, 'longenoughpw');
    await tester.enterText(fields.last, 'longenoughpw');
    await tester.pump();

    await tester.tap(find.widgetWithText(HoppinButton, 'Reset Password'));
    await tester.pumpAndSettle();

    expect(submitted, 'longenoughpw');
    expect(find.textContaining('not yet available'), findsNothing);
  });

  testWidgets('renders in dark mode', (tester) async {
    await tester.pumpWidget(
        _harness(const ResetPasswordScreen(), brightness: Brightness.dark));
    final scaffold = tester.widget<AuthScaffold>(find.byType(AuthScaffold));
    expect(scaffold.title, 'Reset Password');
  });
}
