import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import 'widgets/settings_card.dart';
import 'widgets/settings_header.dart';

/// Delete Account — `Delete Account.png` (added to the pack 2026-08-31).
///
/// The design offers two exits: temporary deactivation (hidden account, data
/// kept) and permanent deletion (everything erased, irreversible). **Neither
/// exists in the API** — there is no deactivate endpoint and no delete
/// endpoint anywhere in the rider surface — so both buttons render genuinely
/// disabled with the app's established "Soon" treatment.
///
/// The copy is the design's own, kept close to verbatim, so the screen is
/// ready the moment the endpoints exist. What must NOT happen here is a red
/// Delete button that looks live and does nothing, or worse, one that fakes
/// success on the most destructive action the app could offer.
class DeleteAccountScreen extends StatelessWidget {
  const DeleteAccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.5);

    return Scaffold(
      appBar: const SettingsHeader(title: 'Delete Account'),
      body: SafeArea(
        // The frame floats the card mid-screen with empty ground above and
        // below (top gap ≈ bottom gap), not flush under the app bar. Center
        // reproduces that; the scroll view keeps short viewports usable.
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: SettingsCard(
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Text('Delete Account',
                      style: theme.textTheme.titleMedium),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Would you like to deactivate account permanently '
                        'or temporarily delete your account?',
                        style: theme.textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 16),
                      Text('•  Temporarily Deletion',
                          style: theme.textTheme.labelLarge),
                      const SizedBox(height: 4),
                      Text(
                        "Hide your account temporarily. You won't be able "
                        'to book rides but your data will be saved.',
                        // The frame paints body copy in the same navy as the
                        // headings, not the secondary grey.
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.textTheme.bodyLarge?.color),
                      ),
                      const SizedBox(height: 14),
                      Text('•  Permanent Deletion',
                          style: theme.textTheme.labelLarge),
                      const SizedBox(height: 4),
                      Text(
                        'Erase all rides history and your data. This cannot '
                        'be undone.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.textTheme.bodyLarge?.color),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton(
                              // Genuinely disabled: no deactivate endpoint
                              // exists. Not styled-inert — actually inert.
                              onPressed: null,
                              style: FilledButton.styleFrom(
                                backgroundColor: theme.brightness ==
                                        Brightness.dark
                                    ? AppColors.darkBorder
                                    : AppColors.lightBorder,
                                disabledBackgroundColor:
                                    theme.brightness == Brightness.dark
                                        ? AppColors.darkBorder
                                        : AppColors.lightBorder,
                                disabledForegroundColor: muted,
                              ),
                              child: const Text('Deactivate'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              // Same: no delete endpoint. A live-looking red
                              // Delete that does nothing would be the worst
                              // control in the app.
                              onPressed: null,
                              style: FilledButton.styleFrom(
                                disabledBackgroundColor: AppColors.negative
                                    .withValues(alpha: 0.35),
                                disabledForegroundColor: Colors.white70,
                              ),
                              child: const Text('Delete'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: Text(
                          'Account deletion is coming soon. To close your '
                          'account today, email Support@hoppin.com.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(fontSize: 12, color: muted),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
