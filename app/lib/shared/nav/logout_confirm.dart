import 'package:flutter/material.dart';

import '../../core/theme/colors.dart';

/// The logout confirmation from `Logout.png`, shared by every surface that
/// offers logout (drawer, settings) so one stray tap never ends the session.
///
/// Frame-exact per Ismail's 2026-09-01 instruction: the See-you-Again
/// illustration (cropped from the design pack), the X in the corner, the
/// frame's copy verbatim, then Cancel and Logout as an equal-width pill pair
/// — Cancel grey-filled, Logout the design's muted lavender (#9787BC).
Future<bool> confirmLogout(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final theme = Theme.of(ctx);

      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        backgroundColor: theme.colorScheme.surface,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  icon: const Icon(Icons.close,
                      size: 22, color: Color(0xFF8E909E)),
                ),
              ),
              Image.asset(
                'assets/illustrations/logout_see_you_again.png',
                width: 190,
              ),
              const SizedBox(height: 20),
              Text(
                'Are you logging out?',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineLarge?.copyWith(fontSize: 24),
              ),
              const SizedBox(height: 14),
              Text(
                "You've been signed out successfully. We'll be here "
                "whenever you're ready for your next ride.",
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFEFEFF1),
                        foregroundColor: theme.textTheme.bodyLarge?.color,
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.buttonPrimary,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Logout'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
  return confirmed ?? false;
}
