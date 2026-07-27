import 'package:flutter/material.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

import 'widgets/share_link_unavailable_state.dart';

/// SAFETY-02 — the live-trip share sheet, on disclosed seam **#57** (SL-8).
///
/// Presents the Figma "Share Trip" sheet for [rideId]. This is the entry point
/// the trip screen reaches (Lane E re-points the two old `_shareTrip` call
/// sites here), and the `show<Name>` idiom Group C's reachability check accepts
/// as a mount site for [ShareLinkUnavailableState].
///
/// ## What this sheet does not do
///
/// **It never fabricates a URL, and it never touches the clipboard.**
///
/// Wave 0 deleted a snackbar that claimed a link had been copied while copying
/// the sentence `Follow my Hoppin trip — arriving 14:32.` — no URL, no ride id,
/// nothing trackable. A rider pasted that into WhatsApp and sent a friend a
/// message that tracked nothing, believing they were being watched over.
///
/// The Figma frame draws a mockup tracking URL in the Link field. It resolves
/// nowhere. No endpoint issues a tokenised public tracking URL and none revokes
/// one (gap #57), so the app cannot produce one — and rendering the mockup's
/// placeholder would be the deleted lie with a real-looking id bolted on, which
/// is strictly worse: it is *more* convincing.
///
/// (Neither the mockup URL nor the deleted snackbar string is spelled literally
/// anywhere in this file. The phase gate greps `lib/` for both, and a docstring
/// *explaining* the ban must not be what trips the gate — the same trap Wave 0
/// hit with `SEAM(#`.)
///
/// So the Link field's slot renders [ShareLinkUnavailableState], and the four
/// Figma share targets render at full fidelity but **disabled**. There is
/// nothing to share, and that is precisely what the seam discloses.
///
/// ## Two deliberate departures from the Figma
///
/// **1. The expiry note is rewritten.** The frame promises *"Link expires when
/// trip ends."* The backend cannot keep that promise — there is no link and no
/// expiry. Per the standing ruling (truth wins, keep the layout) the note
/// survives in its place, restated as the FUTURE behaviour rather than
/// asserted as current fact.
///
/// **2. A revoke control is ADDED.** The Figma has none; the Scope Lock
/// mandates one and ROADMAP success criterion 6 reads "UI + revoke control on
/// a seam". A share link a rider cannot kill is not a safety feature. It ships
/// on the same #57 seam — disabled, because there is no link to revoke yet.
///
/// Lane E registers seam #57 with [ShareLinkUnavailableState] as its
/// `unavailableWidget`.
Future<void> showShareTripSheet(
  BuildContext context, {
  required String rideId,
}) {
  return HopSheet.show<void>(
    context,
    builder: (sheetContext) => _ShareTripSheetBody(rideId: rideId),
  );
}

class _ShareTripSheetBody extends StatelessWidget {
  const _ShareTripSheetBody({required this.rideId});

  /// The trip that would be shared, once there is anything to share it with.
  final String rideId;

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    // Bounded + scrollable. `showModalBottomSheet` caps a non-scroll-controlled
    // sheet at 9/16 of the viewport, and HopSheet's own Column spends part of
    // that on the drag handle and the gutter padding. Our body is taller than
    // what remains on a short screen — the #57 rung says considerably more
    // than the one-line URL it replaces, and honesty costs pixels. So the body
    // caps itself to the space it will actually be given and scrolls inside
    // it, rather than overflowing HopSheet (which this lane does not own).
    final media = MediaQuery.of(context);
    final sheetBudget =
        media.size.height * 9 / 16 - (hoppin.spacing.gutter * 2) - 28;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: sheetBudget.clamp(240.0, 640.0)),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 1 — the Figma title row.
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Share Trip',
                    style: hoppin.type.title.copyWith(
                      color: hoppin.colors.textHi,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  key: const Key('share.close'),
                  tooltip: 'Close',
                  icon: Icon(Icons.close, color: hoppin.colors.textMid),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            Divider(color: hoppin.colors.hairline, height: hoppin.spacing.lg),

            // 2 — the Figma supporting line.
            Text(
              'Share your live trip location:',
              style: hoppin.type.body.copyWith(color: hoppin.colors.textHi),
            ),
            SizedBox(height: hoppin.spacing.md),

            // 3 — the Link field slot. THE MOUNT SITE for seam #57 (Group C).
            //     The Figma renders a URL here. We render the truth here.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.only(top: hoppin.spacing.sm),
                  child: Text(
                    'Link:',
                    style: hoppin.type.body.copyWith(
                      color: hoppin.colors.textHi,
                    ),
                  ),
                ),
                SizedBox(width: hoppin.spacing.md),
                const Expanded(child: ShareLinkUnavailableState()),
              ],
            ),
            SizedBox(height: hoppin.spacing.lg),

            // 4 — the four Figma targets: present at fidelity, DISABLED.
            //     `onPressed: null` throughout. They do NOT go through the
            //     UrlLauncher today — there is nothing to launch. The launcher is
            //     wired at body-swap time when #57 ships.
            Row(
              children: [
                for (final target in _targets) ...[
                  Expanded(
                    child: ShareTargetButton(
                      key: Key('share.target.${target.label.toLowerCase()}'),
                      icon: target.icon,
                      label: target.label,
                      tooltip: '${target.label} — no link to share yet',
                    ),
                  ),
                  if (target != _targets.last)
                    SizedBox(width: hoppin.spacing.sm),
                ],
              ],
            ),
            SizedBox(height: hoppin.spacing.lg),

            // 5 — the revoke control. NOT in the Figma; the Scope Lock mandates
            //     it. Disabled on the same seam: there is no link to revoke.
            const ShareTargetButton(
              key: Key('share.revoke'),
              icon: Icons.link_off_outlined,
              label: 'Revoke link',
              tooltip: 'Revoke link — no link has been issued to revoke',
            ),
            SizedBox(height: hoppin.spacing.md),

            // 6 — the expiry note, REWRITTEN. The Figma asserts "Link expires when
            //     trip ends." as fact. The backend cannot keep that promise, so
            //     the note states it as the future behaviour instead.
            Text(
              'Note: when live-trip links ship, a link will expire when your '
              'trip ends — and you will be able to revoke it sooner.',
              key: const Key('share.expiry.note'),
              style: hoppin.type.bodySmall.copyWith(color: hoppin.colors.error),
            ),
            Divider(color: hoppin.colors.hairline, height: hoppin.spacing.lg),

            // 7 — Done.
            Align(
              alignment: Alignment.centerRight,
              child: HopButton.primary(
                label: 'Done',
                expand: false,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const _targets = <_ShareTarget>[
    _ShareTarget(Icons.chat_outlined, 'WhatsApp'),
    _ShareTarget(Icons.sms_outlined, 'SMS'),
    _ShareTarget(Icons.mail_outline, 'Email'),
    _ShareTarget(Icons.copy_outlined, 'Copy'),
  ];
}

class _ShareTarget {
  const _ShareTarget(this.icon, this.label);

  final IconData icon;
  final String label;
}

/// One share destination in the sheet's target row — and the revoke control.
///
/// [onPressed] is `null` for every instance this phase builds, and that is the
/// point rather than an omission. A share target with nothing to share, wired
/// to a callback that quietly does nothing, is exactly the dead-end control
/// the no-holes rule forbids (Wave 0 deleted five of them). So the button is
/// visibly, honestly disabled, with a tooltip saying why.
///
/// When #57 ships, [onPressed] is filled in and the target launches the real
/// tokenised URL through `urlLauncherProvider` — nothing else about this sheet
/// changes.
class ShareTargetButton extends StatelessWidget {
  /// Creates a share target. Omit [onPressed] to render the disabled seam
  /// state (the only state this phase has).
  const ShareTargetButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    this.onPressed,
    super.key,
  });

  /// The target's Figma glyph.
  final IconData icon;

  /// The target's label — the Figma frame is icon-only, but an unlabelled
  /// disabled glyph discloses nothing.
  final String label;

  /// Why it is disabled. Never decorative.
  final String tooltip;

  /// `null` on the seam — there is no link to share or revoke.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    final disabled = onPressed == null;
    final ink = disabled
        ? hoppin.colors.textMid.withValues(alpha: 0.45)
        : hoppin.colors.accent;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(hoppin.radii.input),
      side: BorderSide(color: hoppin.colors.hairline),
    );
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: !disabled,
        label: tooltip,
        child: Material(
          color: hoppin.colors.card,
          shape: shape,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            customBorder: shape,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: hoppin.spacing.xs,
                  vertical: hoppin.spacing.sm,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 20, color: ink),
                    SizedBox(height: hoppin.spacing.xs),
                    Text(
                      label,
                      style: hoppin.type.labelSmall.copyWith(color: ink),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
