@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/theme/app_theme.dart';
import 'package:hoppin_rider/features/auth/application/auth_controller.dart';
import 'package:hoppin_rider/features/auth/domain/auth_state.dart';
import 'package:hoppin_rider/features/auth/presentation/login_screen.dart';
import 'package:hoppin_rider/features/auth/presentation/signup_screen.dart';
import 'package:mocktail/mocktail.dart';

class _MockController extends Mock implements AuthController {}

/// Renders the auth screens at a NARROW width.
///
/// The card-number defect — a number wrapping one character per line into an
/// unreadable vertical stack — existed because an unconstrained sibling in a
/// Row crushed a flexible one. It was invisible at 430px and obvious the
/// moment the row got tighter. Every screen deserves this check, not just the
/// one where the bug was found.
void main() {
  late _MockController controller;

  setUp(() {
    controller = _MockController();
    when(() => controller.state).thenReturn(const AuthSnapshot());
    when(() => controller.signIn(any(), any())).thenAnswer((_) async {});
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

  Future<void> shoot(WidgetTester tester, Widget screen, String name) async {
    // 320x780 — a small phone, and the width at which a squeezed Row shows.
    tester.view.physicalSize = const Size(320, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [authControllerProvider.overrideWith((_) => controller)],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          home: screen,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // An overflow paints a striped bar and throws here; catching it is the
    // point of the pass.
    expect(tester.takeException(), isNull,
        reason: '$name overflowed at 320px');

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('shots/narrow_$name.png'),
    );
  }

  testWidgets('login at 320', (t) async {
    await shoot(t, const LoginScreen(), 'login');
  });

  testWidgets('signup at 320', (t) async {
    await shoot(t, const SignupScreen(), 'signup');
  });
}
