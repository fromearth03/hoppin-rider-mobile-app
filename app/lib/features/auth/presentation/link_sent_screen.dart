import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../../../shared/widgets/hoppin_button.dart';
import 'widgets/auth_scaffold.dart';

/// "Check your email" confirmation — `Link on Email.png`.
///
/// Reached after a password-reset request is accepted, or after resending
/// from [ExpiredLinkScreen]. Copy is deliberately conditional ("If an account
/// exists for…"), matching the discipline `ForgotPasswordScreen` already
/// applies: this screen must never confirm whether a given address has an
/// account, so the confirmation reads the same whether or not one exists.
///
/// The design frame renders this screen mid-export with a generic "LOADING"
/// spinner graphic shared across the pack's placeholder states — not a real,
/// permanent control. A confirmation screen that shows a spinner forever
/// would be dishonest UI, so it is rendered here as a static icon instead;
/// everything else (heading, copy, single button) matches the frame.
class LinkSentScreen extends StatelessWidget {
  final String? email;

  const LinkSentScreen({super.key, this.email});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trimmedEmail = email?.trim();
    final hasEmail = trimmedEmail != null && trimmedEmail.isNotEmpty;

    return AuthScaffold(
      title: 'Check your email',
      subtitle: 'Securely recover access to your account.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.mark_email_read_outlined,
              size: 72, color: AppColors.buttonPrimary),
          const SizedBox(height: 24),
          Text(
            hasEmail
                ? "If an account exists for $trimmedEmail, we've sent you a "
                    'password reset link. Please open the email and follow '
                    'the link to create a new password.'
                : "We've sent you a password reset link. Please open the "
                    'email and follow the link to create a new password.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 32),
          HoppinButton(
            label: 'Back to login',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }
}
