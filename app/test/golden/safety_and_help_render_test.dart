@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/api/api_client.dart';
import 'package:hoppin_rider/core/result.dart';
import 'package:hoppin_rider/core/theme/app_theme.dart';
import 'package:hoppin_rider/features/safety/data/safety_repository.dart';
import 'package:hoppin_rider/features/safety/presentation/safety_screen.dart';
import 'package:hoppin_rider/features/settings/presentation/help_support_screen.dart';
import 'package:mocktail/mocktail.dart';

class _MockApi extends Mock implements ApiClient {}

/// Renders Safety and Help & Support so they can be checked for overflows and
/// layout bugs. Neither has a Figma design (see the audit task), so this IS
/// the audit for both — no side-by-side comparison, just "does it render
/// cleanly at Figma width and at a narrow width". See `auth_render_test.dart`
/// for why these are renders, not assertions.
void main() {
  Future<void> shoot(
    WidgetTester tester,
    Widget screen,
    String name, {
    Brightness brightness = Brightness.light,
    Size size = const Size(430, 932),
    Future<void> Function(WidgetTester)? interact,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
      home: screen,
    ));
    await tester.pumpAndSettle();

    if (interact != null) {
      await interact(tester);
      await tester.pumpAndSettle();
    }

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('shots/$name.png'),
    );
  }

  Widget safetyApp(_MockApi api) => ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(api)],
        child: const SafetyScreen(rideId: 'r1'),
      );

  testWidgets('safety light', (t) async {
    final api = _MockApi();
    // Bare array — the live backend shape.
    when(() => api.get<dynamic>('/me/emergency-contacts'))
        .thenAnswer((_) async => const Ok<dynamic>([
              {
                'id': 'c1',
                'name': 'Jordan Lee',
                'phone': '+44 7700 900123',
                'relationship': 'Partner',
              },
            ]));
    when(() => api.get<Map<String, dynamic>>('/contacts'))
        .thenAnswer((_) async => const Ok({
              'support_email': 'support@hoppin.app',
              'support_phone': '+44 20 7946 0000',
              'emergency_phone': '999',
              'whatsapp_number': '+44 7700 900000',
            }));

    await shoot(t, safetyApp(api), 'safety_light');
  });

  testWidgets('safety narrow', (t) async {
    final api = _MockApi();
    // Bare array — the live backend shape.
    when(() => api.get<dynamic>('/me/emergency-contacts'))
        .thenAnswer((_) async => const Ok<dynamic>([
              {
                'id': 'c1',
                'name': 'Jordan Lee',
                'phone': '+44 7700 900123',
                'relationship': 'Partner',
              },
            ]));
    when(() => api.get<Map<String, dynamic>>('/contacts'))
        .thenAnswer((_) async => const Ok({
              'support_email': 'support@hoppin.app',
              'support_phone': '+44 20 7946 0000',
              'emergency_phone': '999',
              'whatsapp_number': '+44 7700 900000',
            }));

    await shoot(t, safetyApp(api), 'safety_narrow',
        size: const Size(320, 932));
  });

  // The first FAQ opens by default, as the frame draws it, so the expanded
  // branch renders without interaction.
  testWidgets('help support light', (t) async {
    await shoot(t, const HelpSupportScreen(), 'help_support_light');
  });

  testWidgets('help support narrow', (t) async {
    await shoot(t, const HelpSupportScreen(), 'help_support_narrow',
        size: const Size(320, 932));
  });
}
