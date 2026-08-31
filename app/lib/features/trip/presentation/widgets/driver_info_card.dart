import 'package:flutter/material.dart';

import '../../../../core/theme/colors.dart';
import '../../data/live_trip_source.dart';

/// The bottom card on `Driver Arrived.png` / `Start Ride.png`: driver photo,
/// name, rating with count, chat / safety shortcuts and Cancel Ride.
///
/// Renders the awaiting-match state -- [driver] null -- as a real designed
/// state rather than a blank card or a crash, per the decisions doc: `driver`
/// is null while matching, a normal state, not an error.
///
/// The call button drawn in the Figma is NOT built: `RideDriverInfoView`
/// exposes no phone number (`ride_context_repo.go:20-38`), so a button here
/// would do nothing -- worse than its absence, since a rider taps it when
/// they need the driver most. Deferred to phase 2 per SCREEN-DECISIONS.md.
class DriverInfoCard extends StatelessWidget {
  final TripDriver? driver;
  final VoidCallback onChat;
  final VoidCallback onSafety;
  final VoidCallback onCancel;

  const DriverInfoCard({
    super.key,
    required this.driver,
    required this.onChat,
    required this.onSafety,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = driver;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        MediaQuery.of(context).padding.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (d == null)
            _AwaitingDriverRow(theme: theme)
          else
            _AssignedDriverRow(
              driver: d,
              theme: theme,
              onChat: onChat,
              onSafety: onSafety,
            ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: onCancel,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryDark,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Cancel Ride'),
          ),
        ],
      ),
    );
  }
}

class _AwaitingDriverRow extends StatelessWidget {
  final ThemeData theme;
  const _AwaitingDriverRow({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Finding your driver', style: theme.textTheme.titleMedium),
              Text(
                'This usually takes a moment',
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AssignedDriverRow extends StatelessWidget {
  final TripDriver driver;
  final ThemeData theme;
  final VoidCallback onChat;
  final VoidCallback onSafety;

  const _AssignedDriverRow({
    required this.driver,
    required this.theme,
    required this.onChat,
    required this.onSafety,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: AppColors.buttonPrimary.withValues(alpha: 0.25),
          child: Text(
            driver.name.isNotEmpty ? driver.name[0].toUpperCase() : '?',
            style: theme.textTheme.titleMedium,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(driver.name, style: theme.textTheme.titleMedium),
              // Rating is nullable and never defaulted: a new driver with no
              // rating yet must not be shown a fabricated score.
              if (driver.hasRating)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star, size: 16, color: AppColors.warning),
                    const SizedBox(width: 4),
                    Text(
                      '${driver.rating!.toStringAsFixed(1)} (${driver.ratingCount})',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
            ],
          ),
        ),
        // Call is deferred to phase 2 -- no phone number exists on any
        // endpoint. Chat and SOS are the two real controls.
        IconButton(
          onPressed: onChat,
          icon: const Icon(Icons.chat_bubble, color: AppColors.primary),
        ),
        IconButton(
          onPressed: onSafety,
          icon: const Icon(Icons.warning_rounded, color: AppColors.negative),
        ),
      ],
    );
  }
}
