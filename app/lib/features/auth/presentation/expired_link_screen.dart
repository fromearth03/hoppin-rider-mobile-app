import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../../../shared/widgets/hoppin_button.dart';
import 'widgets/auth_scaffold.dart';

/// The recovery link has expired (or the reset otherwise could not complete)
/// — `Expired-link.png`.
///
/// [onRetry] lets the caller decide what "try again" means — typically
/// re-issuing the reset request and returning to [LinkSentScreen] — because
/// this screen owns no repository call itself. With no callback supplied it
/// simply pops, which is still a safe default for a screen reached by
/// pushing on top of the flow.
///
/// The design frame shows this screen mid-export with the same generic
/// "LOADING" spinner graphic used on `Link on Email.png` — a shared
/// placeholder from the design tool's export, not real content for either
/// screen. Rendered here as a static icon instead; heading, copy and the
/// single button match the frame.
class ExpiredLinkScreen extends StatelessWidget {
  final VoidCallback? onRetry;

  const ExpiredLinkScreen({super.key, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AuthScaffold(
      title: "We're Almost There",
      subtitle: 'Securely recover access to your account.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.error_outline,
              size: 72, color: AppColors.buttonPrimary),
          const SizedBox(height: 24),
          Text(
            "We couldn't complete your password reset right now. Please "
            'wait a moment and try again.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 32),
          // The design fills this button with the deep indigo header colour,
          // not the lavender `buttonPrimary` every other primary button
          // uses (confirmed by sampling `Expired-link.png`) — overridden
          // locally rather than in the shared theme, which the rest of the
          // app correctly keeps on `buttonPrimary`.
          Theme(
            data: Theme.of(context).copyWith(
              filledButtonTheme: FilledButtonThemeData(
                style: Theme.of(context).filledButtonTheme.style?.copyWith(
                      backgroundColor:
                          const WidgetStatePropertyAll(AppColors.primary),
                    ),
              ),
            ),
            child: HoppinButton(
              label: 'Try Again',
              onPressed:
                  onRetry ?? () => Navigator.of(context).maybePop(),
            ),
          ),
        ],
      ),
    );
  }
}
