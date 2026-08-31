import 'package:flutter/material.dart';

import '../../../../core/theme/colors.dart';

/// A row with a leading icon, a label and a trailing switch.
///
/// [onChanged] is null for every unbacked toggle on this screen -- Flutter's
/// [Switch] renders itself visibly inert (dimmed, no ripple, ignores taps)
/// when its `onChanged` is null, which is a real disabled state rather than a
/// toggle that merely looks disabled while still working.
class SettingsToggleRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool comingSoon;

  const SettingsToggleRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.onChanged,
    this.comingSoon = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final disabled = onChanged == null;
    final textColor = disabled
        ? (theme.brightness == Brightness.light
            ? AppColors.lightTextDisabled
            : AppColors.darkTextDisabled)
        : theme.textTheme.bodyLarge?.color;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 22, color: textColor),
          const SizedBox(width: 16),
          Expanded(
            child: Text(label,
                style: theme.textTheme.bodyLarge?.copyWith(color: textColor)),
          ),
          if (comingSoon) ...[
            _SoonBadge(),
            const SizedBox(width: 8),
          ],
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// A row with a leading icon, a label and a trailing chevron.
///
/// When [onTap] is null the row is genuinely inert: no [InkWell], no
/// callback, dimmed text and icon, and a "Soon" badge in place of a
/// navigable chevron affordance.
class SettingsNavRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool comingSoon;

  const SettingsNavRow({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.comingSoon = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final disabled = onTap == null;
    final textColor = disabled
        ? (theme.brightness == Brightness.light
            ? AppColors.lightTextDisabled
            : AppColors.darkTextDisabled)
        : theme.textTheme.bodyLarge?.color;

    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          Icon(icon, size: 22, color: textColor),
          const SizedBox(width: 16),
          Expanded(
            child: Text(label,
                style: theme.textTheme.bodyLarge?.copyWith(color: textColor)),
          ),
          if (comingSoon) ...[
            _SoonBadge(),
            const SizedBox(width: 8),
          ],
          Icon(Icons.chevron_right, size: 22, color: textColor),
        ],
      ),
    );

    if (disabled) return row;

    return InkWell(onTap: onTap, child: row);
  }
}

/// A plain tappable action row (Logout, Delete Account) with no trailing
/// control.
class SettingsActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool destructive;
  final bool comingSoon;

  const SettingsActionRow({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.destructive = false,
    this.comingSoon = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final disabled = onTap == null;
    final Color? textColor = disabled
        ? (theme.brightness == Brightness.light
            ? AppColors.lightTextDisabled
            : AppColors.darkTextDisabled)
        : destructive
            ? AppColors.negative
            : theme.textTheme.bodyLarge?.color;

    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          Icon(icon, size: 22, color: textColor),
          const SizedBox(width: 16),
          Expanded(
            child: Text(label,
                style: theme.textTheme.bodyLarge?.copyWith(color: textColor)),
          ),
          if (comingSoon) _SoonBadge(),
        ],
      ),
    );

    if (disabled) return row;

    return InkWell(onTap: onTap, child: row);
  }
}

class _SoonBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = theme.brightness == Brightness.light
        ? AppColors.lightBorder
        : AppColors.darkBorder;
    final fg = theme.brightness == Brightness.light
        ? AppColors.lightTextSecondary
        : AppColors.darkTextSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text('Soon',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: fg, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}
