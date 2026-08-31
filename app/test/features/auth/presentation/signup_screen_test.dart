import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/theme/app_theme.dart';
import 'package:hoppin_rider/features/auth/application/auth_controller.dart';
import 'package:hoppin_rider/features/auth/domain/auth_state.dart';
import 'package:hoppin_rider/features/auth/presentation/signup_screen.dart';
import 'package:mocktail/mocktail.dart';

class _MockController extends Mock implements AuthController {}

Widget _harness(AuthController controller) => ProviderScope(
      overrides: [authControllerProvider.overrideWith((ref) => controller)],
      child: MaterialApp(theme: AppTheme.light, home: const SignupScreen()),
    );

void main() {
  late _MockController controller;

  setUp(() {
    controller = _MockController();
    when(() => controller.state).thenReturn(const AuthSnapshot());
    when(() => controller.signUp(
          email: any(named: 'email'),
          password: any(named: 'password'),
          fullName: any(named: 'fullName'),
          dateOfBirth: any(named: 'dateOfBirth'),
          phone: any(named: 'phone'),
        )).thenAnswer((_) async {});
    // riverpod's StateNotifierProvider subscribes to the notifier as soon as
    // it is created, and relies on that listener firing immediately to seed
    // its own internal state. mocktail leaves unconfigured methods returning
    // null (crashing on addListener's non-nullable return type) and never
    // invokes the callback, so the provider never initializes -- stub it to
    // behave like the real addListener for the fireImmediately case actually
    // used here.
    when(() => controller.addListener(any(),
        fireImmediately:
            any(named: 'fireImmediately'))).thenAnswer((invocation) {
      final listener =
          invocation.positionalArguments[0] as void Function(AuthSnapshot);
      final fireImmediately =
          invocation.namedArguments[#fireImmediately] as bool? ?? true;
      if (fireImmediately) listener(controller.state);
      return () {};
    });
  });

  testWidgets('has one full-name field, not first and last', (tester) async {
    await tester.pumpWidget(_harness(controller));

    expect(find.text('Full name'), findsOneWidget);
    expect(find.text('First Name'), findsNothing);
    expect(find.text('Last Name'), findsNothing);
  });

  testWidgets('has a date-of-birth field and no 18+ checkbox',
      (tester) async {
    await tester.pumpWidget(_harness(controller));

    expect(find.text('Date of birth'), findsOneWidget);
    expect(find.byType(Checkbox), findsNothing,
        reason: 'self-certification enforces nothing; a stored DOB does');
    expect(find.textContaining('18 years'), findsNothing);
  });

  testWidgets('the primary button says Create account, not Login',
      (tester) async {
    await tester.pumpWidget(_harness(controller));
    expect(find.widgetWithText(ElevatedButton, 'Login'), findsNothing);
    expect(find.text('Create account'), findsOneWidget);
  });

  testWidgets('marks the phone field optional', (tester) async {
    await tester.pumpWidget(_harness(controller));
    expect(find.textContaining('optional'), findsOneWidget);
  });

  testWidgets('blocks submission until a date of birth is chosen',
      (tester) async {
    await tester.pumpWidget(_harness(controller));

    await tester.enterText(find.byType(TextField).at(0), 'Ada Lovelace');
    await tester.enterText(find.byType(TextField).at(1), 'ada@example.com');
    await tester.enterText(find.byType(TextField).at(3), 'hunter2');
    // The form is taller than the test viewport, so the button starts
    // off-screen; scroll it into view before tapping.
    await tester.ensureVisible(find.text('Create account'));
    await tester.tap(find.text('Create account'));
    await tester.pump();

    verifyNever(() => controller.signUp(
          email: any(named: 'email'),
          password: any(named: 'password'),
          fullName: any(named: 'fullName'),
          dateOfBirth: any(named: 'dateOfBirth'),
          phone: any(named: 'phone'),
        ));
    expect(find.text('Enter your date of birth'), findsOneWidget);
  });

  testWidgets('offers a retry when the profile write failed', (tester) async {
    when(() => controller.state)
        .thenReturn(const AuthSnapshot(status: AuthStatus.profileIncomplete));

    await tester.pumpWidget(_harness(controller));
    await tester.pump();

    // The account exists; signing out would strand the rider with an email
    // they cannot reuse. The only sane action is to finish the job.
    expect(find.textContaining('finish'), findsOneWidget);
  });
}
