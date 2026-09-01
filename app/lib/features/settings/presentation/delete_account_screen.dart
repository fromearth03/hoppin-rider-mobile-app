import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/result.dart';
import '../../../core/theme/colors.dart';
import '../../auth/application/auth_controller.dart';
import '../data/account_repository.dart';
import 'widgets/settings_card.dart';
import 'widgets/settings_header.dart';

/// Delete Account — `Delete Account.png`.
///
/// **Delete is live.** `POST /me/delete-account` deletes the account
/// synchronously and irreversibly: the handler erases personal data and
/// answers `{"status": "deleted"}`. It is not a queued request and not a
/// deactivation, so the confirm dialog says exactly that.
///
/// **Deactivate stays disabled.** There is no deactivate endpoint anywhere in
/// the ride service's route table — only `/me/delete-account`. The frame draws
/// deactivation as the gentler of two exits, but shipping a button that
/// deletes-while-labelled-deactivate would be the single worst control in the
/// app, so it keeps the established "Soon" treatment.
///
/// The copy is the frame's, verbatim — including its swapped phrasing
/// ("deactivate account permanently or temporarily delete") and a temporary
/// deletion the API cannot perform. Ismail's 2026-09-01 instruction was to
/// take the frame UI as-is, reversing the earlier rewrite; the Deactivate
/// button stays genuinely inert, which keeps the screen honest in behaviour
/// even where the copy oversells. Recorded in SCREEN-DECISIONS.md.
///
/// A 409 `DELETION_BLOCKED` is not an error to apologise for — it is a list of
/// things the rider must finish first (an open trip, an unresolved dispute),
/// so the server's reasons render as their own block rather than a snackbar
/// that scrolls away.
class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  ConsumerState<DeleteAccountScreen> createState() =>
      _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  bool _deleting = false;
  List<String> _blockers = const [];
  String? _error;

  Future<void> _confirmAndDelete() async {
    final confirmed = await _confirmDeletion(context);
    if (!confirmed || !mounted) return;

    setState(() {
      _deleting = true;
      _blockers = const [];
      _error = null;
    });

    final result =
        await ref.read(accountRepositoryProvider).deleteAccount();
    if (!mounted) return;

    switch (result) {
      case Ok():
        // The account is gone; the session that addressed it is meaningless.
        // Signing out moves the app to the signed-out branch of the router,
        // which is the only honest place to be now.
        await ref.read(authControllerProvider.notifier).signOut();
      case Err(:final error):
        setState(() {
          _deleting = false;
          _blockers = AccountRepository.blockersOf(error);
          // With blockers to show, the generic line would only repeat them.
          _error = _blockers.isEmpty ? error.message : null;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.5);
    final bodyColor = theme.textTheme.bodyLarge?.color;

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
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: bodyColor),
                      ),
                      const SizedBox(height: 14),
                      Text('•  Permanent Deletion',
                          style: theme.textTheme.labelLarge),
                      const SizedBox(height: 4),
                      Text(
                        'Erase all rides history and your data. This cannot '
                        'be undone.',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: bodyColor),
                      ),
                      if (_blockers.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _BlockerNotice(reasons: _blockers),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          // Server-owned copy, rendered verbatim.
                          _error!,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: AppColors.negative),
                        ),
                      ],
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton(
                              // Genuinely disabled: no deactivate endpoint
                              // exists. Not styled-inert — actually inert.
                              onPressed: null,
                              style: FilledButton.styleFrom(
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
                              onPressed: _deleting ? null : _confirmAndDelete,
                              style: FilledButton.styleFrom(
                                // The frame's soft salmon (#FB868B sampled
                                // from Delete Account.png), not the shared
                                // negative red.
                                backgroundColor: const Color(0xFFFB868B),
                                foregroundColor: Colors.white,
                                disabledBackgroundColor: const Color(0xFFFB868B)
                                    .withValues(alpha: 0.35),
                                disabledForegroundColor: Colors.white70,
                              ),
                              child: _deleting
                                  ? const SizedBox(
                                      height: 18,
                                      width: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text('Delete'),
                            ),
                          ),
                        ],
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

/// The server's 409 reasons, rendered as their own block.
///
/// These are not a failure to apologise for — they are the list of things the
/// rider has to finish before the account can go, so they stay on screen
/// rather than passing by in a snackbar.
class _BlockerNotice extends StatelessWidget {
  final List<String> reasons;

  const _BlockerNotice({required this.reasons});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.negative.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your account cannot be deleted yet',
            style: theme.textTheme.labelLarge
                ?.copyWith(color: AppColors.negative),
          ),
          const SizedBox(height: 6),
          for (final reason in reasons)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              // Server-owned copy, rendered verbatim.
              child: Text('•  $reason',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.textTheme.bodyLarge?.color)),
            ),
        ],
      ),
    );
  }
}

/// A last stop before an irreversible call.
///
/// Deliberately a plain confirm rather than a type-the-word gate: the backend
/// still refuses deletion while a trip or dispute is open, so the destructive
/// path is already guarded server-side. What this must do is make sure the tap
/// was not an accident, and say plainly that nothing here comes back.
Future<bool> _confirmDeletion(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      final isDark = theme.brightness == Brightness.dark;

      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Delete your account?', textAlign: TextAlign.center),
        content: Text(
          'This erases your rides history and personal data immediately. '
          'It cannot be undone.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
        actions: [
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  style: FilledButton.styleFrom(
                    backgroundColor:
                        isDark ? AppColors.darkBorder : AppColors.lightBorder,
                    foregroundColor: theme.textTheme.bodyLarge?.color,
                  ),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.negative,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Delete'),
                ),
              ),
            ],
          ),
        ],
      );
    },
  );
  return confirmed ?? false;
}
