import 'package:flutter/material.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

/// A labelled switch row for the Settings screen.
///
/// App-local by design, NOT a `hoppin_ui` component. `hoppin_ui` has no switch
/// in its inventory, and seven of this screen's eight switches are inert — a
/// shared `HopSwitch` would be a component that exists almost entirely to be
/// greyed out, and adding it would spend a shared-package structural touch
/// during a parallel milestone for a widget with exactly one consumer. Promote
/// it later if the driver settings screen needs one too.
///
/// 🔴 **[onChanged] is nullable, and NULL is the whole point.**
///
/// A disabled preference must be `onChanged: null` — genuinely off-limits, no
/// ripple, no tactile feedback, no state change. It must NEVER be an empty
/// closure. That is the Wave-0 bug wearing a different hat:
/// `profile_screen.dart:261` shipped a null-coalesced empty tap handler, giving
/// five dead rows a full tap ripple over a silent no-op. The rider felt the app
/// respond and nothing had happened. A control that visibly reacts and changes
/// nothing is worse than one that plainly cannot be touched.
///
/// (Stated in prose, not in code, on purpose: the CI guard for this lane greps
/// the source for those no-op shapes, and an example in a comment would be a
/// false positive that trains people to ignore the alarm.)
class SettingsToggleRow extends StatelessWidget {
  /// Creates a settings switch row. Pass a null [onChanged] to disable it.
  const SettingsToggleRow({
    required this.label,
    required this.value,
    this.onChanged,
    this.supporting,
    this.divider = false,
    super.key,
  });

  /// The control's name, as the rider reads it.
  final String label;

  /// The switch position. For inert rows this is the Figma default, shown so
  /// the design reads correctly while nothing is claimed.
  final bool value;

  /// The change intent. **NULL means genuinely disabled.** Never `(_) {}`.
  final ValueChanged<bool>? onChanged;

  /// Optional one-line note under the label.
  final String? supporting;

  /// When true, draws a hairline divider beneath the row.
  final bool divider;

  /// Whether this row is live. Reads better than `onChanged != null` at the
  /// call sites that style on it.
  bool get isEnabled => onChanged != null;

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;

    // Disabled rows are visibly off-limits: the label drops to the muted role
    // so a rider can SEE the control is not theirs to move, before they reach
    // for it. Visible, honest, and inert.
    final labelColor = isEnabled ? colors.textHi : colors.textMid;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: hoppin.spacing.lg,
            vertical: hoppin.spacing.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: hoppin.type.bodyMedium.copyWith(color: labelColor),
                    ),
                    if (supporting != null) ...[
                      SizedBox(height: hoppin.spacing.xs),
                      Text(
                        supporting!,
                        style: hoppin.type.metaSmall
                            .copyWith(color: colors.textMid),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(width: hoppin.spacing.md),
              Switch(
                value: value,
                // The one line this whole widget exists to protect.
                onChanged: onChanged,
                activeThumbColor: colors.onAccent,
                activeTrackColor: colors.accent,
              ),
            ],
          ),
        ),
        if (divider)
          Divider(
            height: 1,
            thickness: 1,
            color: colors.hairline,
            indent: hoppin.spacing.lg,
            endIndent: hoppin.spacing.lg,
          ),
      ],
    );
  }
}
