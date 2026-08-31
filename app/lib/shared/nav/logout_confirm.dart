import 'package:flutter/material.dart';

import '../../core/theme/colors.dart';

/// The logout confirmation from `Logout.png`, shared by every surface that
/// offers logout (drawer, settings) so one stray tap never ends the session.
///
/// Matches the frame: centred title and body, then Cancel and Logout as an
/// equal-width pill pair spanning the card — Cancel grey-filled, Logout the
/// design's muted lavender (#9787BC ≈ our primary), not a stock Material
/// action bar.
///
/// The design's dialog copy contradicts itself — "Are you logging out?" over
/// "You've been signed out successfully", a pre-action question with
/// post-action copy. The question and the sign-off line are kept; the
/// premature past tense is not. Its illustration is a raster we don't have
/// as an asset; omitted rather than approximated.
Future<bool> confirmLogout(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      final isDark = theme.brightness == Brightness.dark;

      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Are you logging out?', textAlign: TextAlign.center),
        content: Text(
          "We'll be here whenever you're ready for your next ride.",
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
                  child: const Text('Logout'),
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
