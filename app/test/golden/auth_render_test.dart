@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/theme/app_theme.dart';
import 'package:hoppin_rider/features/auth/application/auth_controller.dart';
import 'package:hoppin_rider/features/auth/domain/auth_state.dart';
import 'package:hoppin_rider/features/auth/presentation/forgot_password_screen.dart';
import 'package:hoppin_rider/features/auth/presentation/login_screen.dart';
import 'package:hoppin_rider/features/auth/presentation/signup_screen.dart';
import 'package:mocktail/mocktail.dart';

class _MockController extends Mock implements AuthController {}

/// Renders the auth screens to PNGs so they can be put side by side with
/// `docs/figma/extracted/`.
///
/// Not assertions — a widget test proves behaviour and nothing here proves
/// appearance, which is exactly why the screens drifted from the design in the
/// first place. Run with `flutter test --run-skipped -t golden` and look at
/// the output.
void main() {
  late _MockController controller;

  setUp(() {
    controller = _MockController();
    when(() => controller.state).thenReturn(const AuthSnapshot());
    when(() => controller.signIn(any(), any())).thenAnswer((_) async {});
    when(() => controller.requestPasswordReset(any()))
        .thenAnswer((_) async => true);
    when(() => controller.addListener(any(),
            fireImmediately: any(named: 'fireImmediately')))
        .thenAnswer((invocation) {
      final listener =
          invocation.positionalArguments[0] as void Function(AuthSnapshot);
      final fire =
          invocation.namedArguments[#fireImmediately] as bool? ?? true;
      if (fire) listener(controller.state);
      return () {};
    });
  });

  Future<void> shoot(
    WidgetTester tester,
    Widget screen,
    String name, {
    Brightness brightness = Brightness.light,
    // The Figma frames are 430x932. A 320-wide render is not a Figma frame —
    // it exists purely to surface the class of bug a fixed-height Row with a
    // squeezed flexible child produces, which only shows up under narrower
    // constraints than the design ships at.
    double width = 430,
  }) async {
    tester.view.physicalSize = Size(width, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [authControllerProvider.overrideWith((_) => controller)],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme:
              brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
          home: screen,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('shots/$name.png'),
    );
  }

  testWidgets('login light', (t) async {
    await shoot(t, const LoginScreen(), 'login_light');
  });

  testWidgets('login dark', (t) async {
    await shoot(t, const LoginScreen(), 'login_dark',
        brightness: Brightness.dark);
  });

  testWidgets('login narrow', (t) async {
    await shoot(t, const LoginScreen(), 'login_narrow', width: 320);
  });

  testWidgets('forgot password light', (t) async {
    await shoot(t, const ForgotPasswordScreen(), 'forgot_light');
  });

  testWidgets('forgot password narrow', (t) async {
    await shoot(t, const ForgotPasswordScreen(), 'forgot_narrow', width: 320);
  });

  testWidgets('signup light', (t) async {
    await shoot(t, const SignupScreen(), 'signup_light');
  });

  testWidgets('signup narrow', (t) async {
    await shoot(t, const SignupScreen(), 'signup_narrow', width: 320);
  });
}
