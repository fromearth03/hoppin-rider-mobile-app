@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/theme/app_theme.dart';
import 'package:hoppin_rider/features/settings/presentation/delete_account_screen.dart';

/// Renders Delete Account (`Delete Account.png`) so it can be put side by
/// side with `docs/figma/extracted/`. The screen is not routed yet, so it is
/// pumped directly. See `auth_render_test.dart` for why these are renders,
/// not assertions.
void main() {
  Future<void> shoot(
    WidgetTester tester,
    Widget screen,
    String name, {
    Brightness brightness = Brightness.light,
    double width = 430,
  }) async {
    tester.view.physicalSize = Size(width, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
      home: screen,
    ));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('shots/$name.png'),
    );
  }

  testWidgets('delete account light', (t) async {
    await shoot(t, const DeleteAccountScreen(), 'delete_account_light');
  });

  testWidgets('delete account narrow', (t) async {
    await shoot(t, const DeleteAccountScreen(), 'delete_account_narrow',
        width: 320);
  });
}
