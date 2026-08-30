import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/api/api_exception.dart';
import 'package:hoppin_rider/core/theme/app_theme.dart';
import 'package:hoppin_rider/features/auth/application/auth_controller.dart';
import 'package:hoppin_rider/features/auth/domain/auth_state.dart';
import 'package:hoppin_rider/features/auth/presentation/login_screen.dart';
import 'package:mocktail/mocktail.dart';

class _MockController extends Mock implements AuthController {}

Widget _harness(AuthController controller, AuthSnapshot snapshot,
        {Brightness brightness = Brightness.light}) =>
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith((ref) => controller),
      ],
      child: MaterialApp(
        theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
        home: const LoginScreen(),
      ),
    );

void main() {
  late _MockController controller;

  setUp(() {
    controller = _MockController();
    when(() => controller.state).thenReturn(const AuthSnapshot());
    when(() => controller.signIn(any(), any())).thenAnswer((_) async {});
    // riverpod's StateNotifierProvider subscribes to the notifier as soon as
    // it is created, and relies on that listener firing immediately to seed
    // its own internal state. mocktail leaves unconfigured methods returning
    // null (crashing on addListener's non-nullable return type) and never
    // invokes the callback, so the provider never initializes -- stub it to
    // behave like the real addListener for the fireImmediately case actually
    // used here.
    when(() => controller.addListener(any(),
        fireImmediately: any(named: 'fireImmediately'))).thenAnswer((invocation) {
      final listener =
          invocation.positionalArguments[0] as void Function(AuthSnapshot);
      final fireImmediately =
          invocation.namedArguments[#fireImmediately] as bool? ?? true;
      if (fireImmediately) listener(controller.state);
      return () {};
    });
  });

  testWidgets('labels the identifier field Email, never phone',
      (tester) async {
    // The design says "Email or Phone Number", but Supabase cannot
    // authenticate a phone it never verified by SMS.
    await tester.pumpWidget(_harness(controller, const AuthSnapshot()));

    expect(find.text('Email'), findsOneWidget);
    expect(find.textContaining('Phone'), findsNothing);
  });

  testWidgets('drops the invite-flow subtitle', (tester) async {
    await tester.pumpWidget(_harness(controller, const AuthSnapshot()));
    expect(find.textContaining('credentials'), findsNothing);
  });

  testWidgets('submits the typed email and password', (tester) async {
    await tester.pumpWidget(_harness(controller, const AuthSnapshot()));

    await tester.enterText(find.byType(TextField).first, 'ada@example.com');
    await tester.enterText(find.byType(TextField).last, 'hunter2');
    await tester.tap(find.text('Login'));
    await tester.pump();

    verify(() => controller.signIn('ada@example.com', 'hunter2')).called(1);
  });

  testWidgets('shows the server message verbatim on failure', (tester) async {
    const snapshot = AuthSnapshot(
      status: AuthStatus.signedOut,
      error: ApiException('INVALID_CREDENTIALS', 'Invalid login credentials', 400),
    );
    when(() => controller.state).thenReturn(snapshot);

    await tester.pumpWidget(_harness(controller, snapshot));
    await tester.pump();

    expect(find.text('Invalid login credentials'), findsOneWidget);
  });

  testWidgets('renders in dark mode', (tester) async {
    await tester.pumpWidget(_harness(controller, const AuthSnapshot(),
        brightness: Brightness.dark));
    expect(find.text('Login'), findsWidgets);
  });
}
