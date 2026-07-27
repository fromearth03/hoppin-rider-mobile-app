import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/features/auth/reset_landing_screen.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

/// AUTH-04 (#49) — the password-reset deep-link landing.
///
/// The Supabase redirect config is not live yet, so the landing is GATED inert:
/// it must render a DESIGNED, honest "reset link unavailable" state — never a
/// fake password form that pretends to work. The redirect allowlist that keeps
/// this reachable while signed out is wired in 09-05; here we prove the honest
/// state renders and that no password field is present.
void main() {
  final light = HoppinTheme.riderLight();

  testWidgets('renders an honest unavailable state, not a password form',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: light, home: const ResetLandingScreen()),
    );

    // The designed unavailable-state, via the brand HopEmptyState.
    expect(find.byType(HopEmptyState), findsOneWidget);
    expect(find.textContaining("isn't active yet"), findsOneWidget);

    // Crucially: NO password entry — never a fake reset flow.
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(TextFormField), findsNothing);
  });
}
