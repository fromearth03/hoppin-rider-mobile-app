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

/// Request a password-reset email — `Forgot Password.png`.
///
/// On success the screen swaps to a confirmation rather than navigating away:
/// the rider needs to leave the app for their inbox, and dropping them back on
/// login would leave them wondering whether anything was sent.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState
    extends ConsumerState<ForgotPasswordScreen> {
  final _email = TextEditingController();
  bool _sent = false;

  @override
  void initState() {
    super.initState();
    // The button is disabled until the field holds something, so it has to
    // rebuild as the rider types.
    _email.addListener(_onChanged);
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _email.removeListener(_onChanged);
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final ok = await ref
        .read(authControllerProvider.notifier)
        .requestPasswordReset(_email.text);
    if (!ok || !mounted) return;
    // The email carries a one-tap LINK to the hosted set-password page
    // (rider.hoppin.tech/reset) — nothing more happens in the app.
    setState(() => _sent = true);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);
    final theme = Theme.of(context);
    final error = state.error;

    return AuthScaffold(
      title: 'Forgot Password',
      subtitle: 'Securely recover access to your account.',
      child: _sent
          ? _Sent(email: _email.text.trim())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                HoppinTextField(
                  label: 'Email',
                  controller: _email,
                  hint: 'abc@hoppins.com',
                  keyboardType: TextInputType.emailAddress,
                  prefixIcon: const Icon(Icons.mail_outline),
                  autofillHints: const [AutofillHints.email],
                  textInputAction: TextInputAction.done,
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    RiderErrorCopy.messageFor(error),
                    style: const TextStyle(color: AppColors.negative),
                  ),
                ],
                const SizedBox(height: 20),
                HoppinButton(
                  label: 'Reset Password',
                  isLoading: state.isBusy,
                  // Sending to an empty address only produces an error the
                  // rider has to read and recover from.
                  onPressed:
                      _email.text.trim().isEmpty ? null : _submit,
                ),
                const SizedBox(height: 12),
                Center(
                  child: TextButton(
                    onPressed: () => _backToLogin(context),
                    child: Text(
                      'Back to login',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _Sent extends StatelessWidget {
  final String email;

  const _Sent({required this.email});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.mark_email_read_outlined,
            size: 56, color: AppColors.buttonPrimary),
        const SizedBox(height: 16),
        Text(
          'Check your email',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'If an account exists for $email, we have sent it a link to '
          'reset the password. The link expires after a short while.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        HoppinButton(
          label: 'Back to login',
          onPressed: () => _backToLogin(context),
        ),
      ],
    );
  }
}

/// Pops back where possible; a rider who deep-linked straight here has no
/// stack to pop, so fall through to the login route instead of doing nothing.
void _backToLogin(BuildContext context) {
  if (Navigator.of(context).canPop()) {
    Navigator.of(context).pop();
  } else {
    context.go(AppRoutes.login);
  }
}
