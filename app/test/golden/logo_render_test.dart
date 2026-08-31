@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/shared/widgets/hoppin_logo.dart';

/// Renders the lockup large so the mark can be compared with the design crop.
/// See `auth_render_test.dart` for why these are renders rather than
/// assertions.
void main() {
  testWidgets('logo large', (tester) async {
    tester.view.physicalSize = const Size(900, 180);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: ColoredBox(
          color: Color(0xFFF6F6F6),
          child: Center(
            child: FittedBox(child: HoppinLogo(height: 110)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('shots/logo_large.png'),
    );
  });
}
