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
  }) async {
    // The Figma frames are 430x932.
    tester.view.physicalSize = const Size(430, 932);
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

  testWidgets('forgot password light', (t) async {
    await shoot(t, const ForgotPasswordScreen(), 'forgot_light');
  });
}
