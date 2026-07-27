import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

/// OTP verification (AUTH-02, Figma "Verification Code #5").
///
/// Enters a 5-digit code via the existing [OtpInput], verifies it against
/// [AuthService.verifyOtp], and runs a resend countdown on the clock (so it
/// ticks under `fake_async`). The retry-lockout line is surfaced but DISCLOSED
/// as advisory — the client counter is spoofable and there is no confirmed
/// backend lockout endpoint yet (SL-14 MISSING-BE, relayed; register in 09-05).
class OtpVerifyScreen extends ConsumerStatefulWidget {
  const OtpVerifyScreen({
    required this.phone,
    this.resendWindow = const Duration(seconds: 30),
    super.key,
  });

  /// The phone the OTP was sent to — echoed back on verify.
  final String phone;

  /// How long before "Resend code" re-enables.
  final Duration resendWindow;

  @override
  ConsumerState<OtpVerifyScreen> createState() => _OtpVerifyScreenState();
}

class _OtpVerifyScreenState extends ConsumerState<OtpVerifyScreen> {
  String _code = '';
  bool _busy = false;
  String? _error;

  Timer? _ticker;
  late DateTime _windowEndsAt;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    // clock.now() (not DateTime.now()) so the window is controllable in tests.
    _windowEndsAt = clock.now().add(widget.resendWindow);
    _remaining = widget.resendWindow;
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final left = _windowEndsAt.difference(clock.now());
      setState(() => _remaining = left.isNegative ? Duration.zero : left);
      if (left.isNegative || left == Duration.zero) _ticker?.cancel();
    });
  }

  bool get _canResend => _remaining <= Duration.zero;

  Future<void> _resend() async {
    setState(() => _error = null);
    try {
      await ref.read(authServiceProvider).signInWithOtp(phone: widget.phone);
      _startCountdown();
    } on Object catch (e) {
      if (mounted) setState(() => _error = friendlyErrorMessage(e));
    }
  }

  Future<void> _verify() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authServiceProvider).verifyOtp(
            phone: widget.phone,
            token: _code,
          );
      // Router redirect / caller handles navigation on the auth event.
    } on Object catch (e) {
      if (mounted) setState(() => _error = friendlyErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;
    final type = hoppin.type;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: hoppin.spacing.gutter,
              vertical: hoppin.spacing.xl,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Verify your number',
                    textAlign: TextAlign.center,
                    style: type.display.copyWith(color: colors.accent),
                  ),
                  SizedBox(height: hoppin.spacing.sm),
                  Text(
                    'Enter the 5-digit code we sent to ${widget.phone}.',
                    textAlign: TextAlign.center,
                    style: type.body.copyWith(color: colors.textMid),
                  ),
                  SizedBox(height: hoppin.spacing.xl),
                  if (_error != null) ...[
                    HopBanner.error(message: _error!),
                    SizedBox(height: hoppin.spacing.md),
                  ],
                  OtpInput(onChanged: (v) => setState(() => _code = v)),
                  SizedBox(height: hoppin.spacing.gutter),
                  HopButton.primary(
                    key: const Key('otp_verify_button'),
                    label: 'Verify',
                    onPressed: (_busy || _code.length < 5) ? null : _verify,
                    busy: _busy,
                  ),
                  SizedBox(height: hoppin.spacing.md),
                  if (_canResend)
                    TextButton(
                      onPressed: _busy ? null : _resend,
                      style: TextButton.styleFrom(
                        minimumSize: const Size.fromHeight(44),
                      ),
                      child: const Text('Resend code'),
                    )
                  else
                    Text(
                      'Resend in ${_remaining.inSeconds}s',
                      textAlign: TextAlign.center,
                      style: type.bodySmall.copyWith(color: colors.textMid),
                    ),
                  SizedBox(height: hoppin.spacing.sm),
                  // SL-14 disclosure — surfaced, but framed as advisory only.
                  Text(
                    'For your security, repeated failed attempts may be '
                    'temporarily locked out. This guidance is advisory — the '
                    'final check is enforced on our servers.',
                    textAlign: TextAlign.center,
                    style: type.bodySmall.copyWith(color: colors.textMid),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
