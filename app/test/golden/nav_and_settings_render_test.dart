@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/theme/app_theme.dart';
import 'package:hoppin_rider/features/auth/application/auth_controller.dart';
import 'package:hoppin_rider/features/auth/data/profile_repository.dart';
import 'package:hoppin_rider/features/auth/domain/auth_state.dart';
import 'package:hoppin_rider/features/settings/presentation/settings_screen.dart';
import 'package:hoppin_rider/shared/nav/app_drawer.dart';
import 'package:mocktail/mocktail.dart';

class _MockAuthController extends Mock implements AuthController {}

/// Renders the drawer and Settings screens so they can be put side by side
/// with `docs/figma/extracted/`. See `auth_render_test.dart` for why these
/// are renders, not assertions.
void main() {
  late _MockAuthController controller;

  const profile = RiderProfile(
    fullName: 'Taimoor',
    phoneNumber: '+44 123 567 8910',
    email: 'taimoor@example.com',
    avatarUrl: null,
    dateOfBirth: '1995-04-12',
    rating: 4.31,
    ratingCount: 150,
  );

  setUp(() {
    controller = _MockAuthController();
    when(() => controller.state)
        .thenReturn(const AuthSnapshot(status: AuthStatus.signedIn, profile: profile));
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

  testWidgets('drawer light', (t) async {
    // The drawer only renders its full width when opened via a Scaffold — a
    // bare Drawer widget is unbounded. Host it in a Scaffold and open it, the
    // same way the app itself does.
    final key = GlobalKey<ScaffoldState>();
    await shoot(
      t,
      Scaffold(
        key: key,
        drawer: const AppDrawer(),
        body: Builder(builder: (context) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Scaffold.of(context).openDrawer();
          });
          return const SizedBox.shrink();
        }),
      ),
      'drawer_light',
    );
  });

  testWidgets('settings light', (t) async {
    await shoot(t, const SettingsScreen(), 'settings_light');
  });

  testWidgets('logout dialog light', (t) async {
    // Same drawer host as above, but capture AFTER tapping Logout so the
    // confirmation dialog (`Logout.png`) is what lands in the shot.
    t.view.physicalSize = const Size(430, 932);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);

    await t.pumpWidget(
      ProviderScope(
        overrides: [authControllerProvider.overrideWith((_) => controller)],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          home: Scaffold(
            drawer: const AppDrawer(),
            body: Builder(builder: (context) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                Scaffold.of(context).openDrawer();
              });
              return const SizedBox.shrink();
            }),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();

    await t.tap(find.text('Logout'));
    await t.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('shots/logout_dialog_light.png'),
    );
  });
}
