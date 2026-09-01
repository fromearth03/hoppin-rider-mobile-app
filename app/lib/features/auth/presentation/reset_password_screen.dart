import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/error_codes.dart';
import '../../../core/theme/colors.dart';
import '../../../shared/nav/app_router.dart';
import '../../../shared/widgets/hoppin_button.dart';
import '../../../shared/widgets/hoppin_text_field.dart';
import '../application/auth_controller.dart';
import 'widgets/auth_scaffold.dart';

/// Set a new password — `Reset Password.png` — completed with the 6-digit
/// CODE from the recovery email, never the emailed link.
///
/// The Supabase project is shared with the admin panel, whose site URL owns
/// where the emailed link lands — riders tapping it were routed into the
/// admin reset page. The code printed in the same email works everywhere
/// (web and APK) with zero auth-config changes: `verifyOTP` (type recovery)
/// signs the rider in on a recovery session, `updateUser` sets the password,
/// and this screen then navigates home itself (the router deliberately does
/// not bounce a signed-in rider off this one screen mid-reset).
///
/// Design says the minimum is 8 characters. Supabase's own floor is 6, so
/// enforcing 8 here is stricter, not looser, than the backend — it can never
/// reject a password the server would have accepted.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  static const minLength = 8;

  /// Where the recovery code was emailed. Arrives via `?email=` from the
  /// Forgot Password screen; editable here for a rider who lands directly.
  final String email;

  const ResetPasswordScreen({super.key, this.email = ''});

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  late final _email = TextEditingController(text: widget.email);
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final c in [_email, _code, _password, _confirm]) {
      c.addListener(_onChanged);
    }
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    for (final c in [_email, _code, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _valid =>
      _email.text.trim().isNotEmpty &&
      _code.text.trim().length >= 6 &&
      _password.text.length >= ResetPasswordScreen.minLength &&
      _password.text == _confirm.text;

  String? get _mismatch =>
      _confirm.text.isNotEmpty && _password.text != _confirm.text
          ? 'Passwords do not match'
          : null;

  Future<void> _submit() async {
    if (!_valid || _submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });

    final ok =
        await ref.read(authControllerProvider.notifier).resetPasswordWithCode(
              email: _email.text,
              code: _code.text,
              newPassword: _password.text,
            );
    if (!mounted) return;

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Password updated — you are signed in.')),
      );
      context.go(AppRoutes.home);
      return;
    }

    final error = ref.read(authControllerProvider).error;
    setState(() {
      _submitting = false;
      // The most common failure by far is a mistyped or expired code — say
      // that plainly rather than a raw auth message.
      _error = switch (error?.code) {
        'otp_expired' || 'invalid_otp' =>
          'That code is invalid or has expired. Request a new one from '
              'Forgot Password.',
        _ => error != null
            ? RiderErrorCopy.messageFor(error)
            : 'Could not reset the password. Check the code and try again.',
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Reset Password',
      subtitle:
          'Enter the 6-digit code we emailed you, then choose a new password.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HoppinTextField(
            label: 'Email',
            controller: _email,
            hint: 'abc@hoppins.com',
          ),
          const SizedBox(height: 16),
          HoppinTextField(
            label: 'Reset code',
            controller: _code,
            hint: '6-digit code from the email',
          ),
          const SizedBox(height: 16),
          HoppinTextField(
            label: 'New password',
            controller: _password,
            obscurable: true,
            hint: 'At least ${ResetPasswordScreen.minLength} characters',
          ),
          const SizedBox(height: 16),
          HoppinTextField(
            label: 'Confirm password',
            controller: _confirm,
            obscurable: true,
            errorText: _mismatch,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!,
                style: const TextStyle(color: AppColors.negative)),
          ],
          const SizedBox(height: 24),
          HoppinButton(
            label: _submitting ? 'Resetting…' : 'Reset Password',
            onPressed: _valid && !_submitting ? _submit : null,
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => context.go(AppRoutes.forgotPassword),
            child: const Text('Send a new code'),
          ),
        ],
      ),
    );
  }
}
