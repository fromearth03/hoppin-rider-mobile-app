import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/api/api_exception.dart';
import 'package:hoppin_rider/core/theme/app_theme.dart';
import 'package:hoppin_rider/features/auth/application/auth_controller.dart';
import 'package:hoppin_rider/features/auth/domain/auth_state.dart';
import 'package:go_router/go_router.dart';
import 'package:hoppin_rider/features/auth/presentation/forgot_password_screen.dart';
import 'package:hoppin_rider/shared/nav/app_router.dart';
import 'package:hoppin_rider/shared/widgets/hoppin_button.dart';
import 'package:mocktail/mocktail.dart';

class _MockController extends Mock implements AuthController {}

String? _lastLocation;

Widget _harness(AuthController controller,
    {Brightness brightness = Brightness.light}) {
  // A real router: success now navigates ON to the code-entry screen (the
  // emailed LINK belongs to the admin panel; the rider flow uses the code).
  final router = GoRouter(
    initialLocation: AppRoutes.forgotPassword,
    routes: [
      GoRoute(
        path: AppRoutes.forgotPassword,
        builder: (_, __) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: AppRoutes.resetPassword,
        builder: (_, state) {
          _lastLocation = state.uri.toString();
          return const Scaffold(body: Text('reset screen'));
        },
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      authControllerProvider.overrideWith((ref) => controller),
    ],
    child: MaterialApp.router(
      theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
      routerConfig: router,
    ),
  );
}

void main() {
  late _MockController controller;

  setUp(() {
    controller = _MockController();
    when(() => controller.state).thenReturn(const AuthSnapshot());
    when(() => controller.requestPasswordReset(any()))
        .thenAnswer((_) async => true);
    // See login_screen_test: mocktail leaves addListener returning null, which
    // stops the provider ever seeding its state.
    when(() => controller.addListener(any(),
            fireImmediately: any(named: 'fireImmediately')))
        .thenAnswer((invocation) {
      final listener =
          invocation.positionalArguments[0] as void Function(AuthSnapshot);
      final fireImmediately =
          invocation.namedArguments[#fireImmediately] as bool? ?? true;
      if (fireImmediately) listener(controller.state);
      return () {};
    });
  });

  testWidgets('carries the design heading and subtitle', (tester) async {
    await tester.pumpWidget(_harness(controller));

    expect(find.text('Forgot Password'), findsOneWidget);
    expect(
        find.text('Securely recover access to your account.'), findsOneWidget);
  });

  testWidgets('the reset button is disabled until an email is typed',
      (tester) async {
    await tester.pumpWidget(_harness(controller));

    HoppinButton button() => tester.widget<HoppinButton>(
        find.widgetWithText(HoppinButton, 'Reset Password'));
    expect(button().onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'ada@example.com');
    await tester.pump();
    expect(button().onPressed, isNotNull);
  });

  testWidgets('sends the typed email', (tester) async {
    await tester.pumpWidget(_harness(controller));

    await tester.enterText(find.byType(TextField), 'ada@example.com');
    await tester.pump();
    await tester.tap(find.widgetWithText(HoppinButton, 'Reset Password'));
    await tester.pumpAndSettle();

    verify(() => controller.requestPasswordReset('ada@example.com')).called(1);
  });

  testWidgets('success continues to the code screen carrying the email',
      (tester) async {
    _lastLocation = null;
    await tester.pumpWidget(_harness(controller));

    await tester.enterText(find.byType(TextField), 'ada@example.com');
    await tester.pump();
    await tester.tap(find.widgetWithText(HoppinButton, 'Reset Password'));
    await tester.pumpAndSettle();

    expect(find.text('reset screen'), findsOneWidget);
    expect(_lastLocation, contains('email=ada%40example.com'));
  });

  testWidgets('shows the server message and stays put on failure',
      (tester) async {
    const snapshot = AuthSnapshot(
      status: AuthStatus.signedOut,
      error: ApiException('RATE_LIMITED', 'Too many requests', 429),
    );
    when(() => controller.requestPasswordReset(any()))
        .thenAnswer((_) async => false);
    when(() => controller.state).thenReturn(snapshot);

    await tester.pumpWidget(_harness(controller));
    await tester.enterText(find.byType(TextField), 'ada@example.com');
    await tester.pump();
    await tester.tap(find.widgetWithText(HoppinButton, 'Reset Password'));
    await tester.pumpAndSettle();

    expect(find.text('Too many requests'), findsOneWidget);
    expect(find.text('Check your email'), findsNothing);
  });

  testWidgets('renders in dark mode', (tester) async {
    await tester.pumpWidget(
        _harness(controller, brightness: Brightness.dark));
    expect(find.widgetWithText(HoppinButton, 'Reset Password'), findsOneWidget);
  });
}
