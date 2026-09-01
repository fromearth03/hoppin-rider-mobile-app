import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/theme/app_theme.dart';
import 'package:hoppin_rider/features/auth/presentation/reset_password_screen.dart';
import 'package:hoppin_rider/shared/widgets/hoppin_button.dart';

Widget _harness(Widget child, {Brightness brightness = Brightness.light}) =>
    ProviderScope(
      child: MaterialApp(
        theme:
            brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
        home: child,
      ),
    );

/// The reset is completed with the emailed 6-digit CODE (`verifyOTP` type
/// recovery, then `updateUser`) — never the emailed link, which belongs to
/// the admin panel's site URL on the shared Supabase project.
void main() {
  bool buttonEnabled(WidgetTester tester) =>
      tester.widget<HoppinButton>(find.byType(HoppinButton)).onPressed !=
      null;

  testWidgets('carries the design heading and the code instruction',
      (tester) async {
    await tester.pumpWidget(_harness(const ResetPasswordScreen()));

    expect(find.text('Reset Password'), findsWidgets);
    expect(find.textContaining('6-digit code'), findsWidgets);
  });

  testWidgets('prefills the email it was routed with', (tester) async {
    await tester.pumpWidget(
        _harness(const ResetPasswordScreen(email: 'a@b.com')));

    expect(find.text('a@b.com'), findsOneWidget);
  });

  testWidgets('the button stays disabled until every field is valid',
      (tester) async {
    await tester.pumpWidget(
        _harness(const ResetPasswordScreen(email: 'a@b.com')));

    expect(buttonEnabled(tester), isFalse);

    await tester.enterText(
        find.widgetWithText(TextField, '6-digit code from the email'),
        '123456');
    await tester.pump();
    expect(buttonEnabled(tester), isFalse);

    final passwords = find.byType(TextField);
    // Fields: email, code, password, confirm — in order.
    await tester.enterText(passwords.at(2), 'longenough1');
    await tester.pump();
    expect(buttonEnabled(tester), isFalse,
        reason: 'confirm still empty');

    await tester.enterText(passwords.at(3), 'different111');
    await tester.pump();
    expect(buttonEnabled(tester), isFalse,
        reason: 'passwords do not match');
    expect(find.text('Passwords do not match'), findsOneWidget);

    await tester.enterText(passwords.at(3), 'longenough1');
    await tester.pump();
    expect(buttonEnabled(tester), isTrue);
  });

  testWidgets('a short password keeps the button disabled', (tester) async {
    await tester.pumpWidget(
        _harness(const ResetPasswordScreen(email: 'a@b.com')));

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(1), '123456');
    await tester.enterText(fields.at(2), 'short1');
    await tester.enterText(fields.at(3), 'short1');
    await tester.pump();

    expect(buttonEnabled(tester), isFalse);
  });

  testWidgets('renders in dark mode', (tester) async {
    await tester.pumpWidget(_harness(const ResetPasswordScreen(),
        brightness: Brightness.dark));

    expect(find.text('Reset Password'), findsWidgets);
  });
}
