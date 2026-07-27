import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/features/auth/otp_verify_screen.dart';
import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

import 'support/recording_auth_service.dart';

/// AUTH-02 — OTP entry via the existing [OtpInput], a resend countdown that
/// ticks on the clock, and a retry-lockout advisory DISCLOSED as advisory
/// (SL-14; the client counter is spoofable, so it is a heads-up, not a gate).
void main() {
  final light = HoppinTheme.riderLight();

  Widget harness(RecordingAuthService auth) => ProviderScope(
        overrides: [authServiceProvider.overrideWithValue(auth)],
        child: MaterialApp(
          theme: light,
          home: const OtpVerifyScreen(phone: '+447700900000'),
        ),
      );

  testWidgets('renders an OtpInput and the advisory retry-lockout line',
      (tester) async {
    await tester.pumpWidget(harness(RecordingAuthService()));

    expect(find.byType(OtpInput), findsOneWidget);
    // SL-14 disclosure: the lockout is surfaced AND framed as advisory.
    expect(find.textContaining('advisory', findRichText: true), findsWidgets);
  });

  testWidgets('the resend countdown ticks down on the clock', (tester) async {
    await tester.pumpWidget(harness(RecordingAuthService()));

    // A fresh screen shows a running countdown, resend disabled.
    expect(find.textContaining('Resend in'), findsOneWidget);

    // Advance the clock; the countdown must decrease.
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('Resend in'), findsOneWidget);

    // After the full window the resend action becomes available.
    await tester.pump(const Duration(seconds: 30));
    expect(find.text('Resend code'), findsOneWidget);
  });

  testWidgets('tapping verify with a full code calls verifyOtp',
      (tester) async {
    final auth = RecordingAuthService();
    await tester.pumpWidget(harness(auth));

    // Type a 5-digit code into the OtpInput boxes.
    final boxes = find.byType(TextField);
    expect(boxes, findsNWidgets(5));
    for (var i = 0; i < 5; i++) {
      await tester.enterText(boxes.at(i), '${i + 1}');
    }
    await tester.pump();

    await tester.tap(find.byKey(const Key('otp_verify_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(auth.verifyCalls, hasLength(1));
    expect(auth.verifyCalls.single.token, '12345');
    expect(auth.verifyCalls.single.phone, '+447700900000');
  });
}
