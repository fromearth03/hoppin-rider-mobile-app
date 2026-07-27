import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

import '../../app.dart';
import '../legal/consent_notifier.dart';
import '../legal/widgets/consent_record_unavailable.dart';
import 'widgets/delete_account_popup.dart';
import 'widgets/settings_prefs_unavailable.dart';
import 'widgets/settings_toggle_row.dart';

/// Stable widget keys the Settings screen exposes for tests.
abstract final class SettingsScreenKeys {
  /// The screen root.
  static const root = ValueKey('settings-screen-root');

  /// The ONE genuinely working control on this screen.
  static const themeToggle = ValueKey('settings-theme-toggle');

  /// The marketing-consent toggle — live, because withdrawal must be as easy
  /// as giving.
  static const marketingToggle = ValueKey('settings-marketing-toggle');

  /// The red route to the Art. 17 erasure request.
  static const deleteAccountRow = ValueKey('settings-delete-account-row');
}

/// **ACCT-03 — Settings.** Eight controls in the Figma. Exactly ONE works.
///
/// This is the phase's hardest honesty test. Settings is where a rider most
/// expects a control to *do* something, and almost nothing here can: there is
/// no preferences endpoint (gap 71), and there is deliberately no local cache
/// to fake one with. So every unbacked switch ships **visible and inert**
/// (`onChanged: null` — never an empty closure), under a single screen-level
/// [SettingsPrefsUnavailable] rung.
///
/// **What is LIVE:**
/// * **Theme** — client-side, genuinely works, and applies immediately. ACCT-03
///   requires it and the Figma frame does not contain it. Truth wins over
///   Figma; here truth means ADDING.
/// * **Promotional offers** — live because it must be. It is the same consent
///   choice the signup toggle collects, and the ICO is explicit that withdrawal
///   must be as easy as giving. A greyed-out withdrawal control would make the
///   signup consent invalid.
///
/// **Four controls the Figma draws that this screen deliberately does NOT.**
/// Each is logged in the release-gate report by name; they are described here
/// obliquely on purpose, because a CI guard greps this subtree for those exact
/// strings and a mention in a comment would be a false positive that trains
/// people to ignore the alarm.
///
/// 1. **The payment-security toggle.** The frame renders it ON — advertising
///    that card payments are protected by a passcode. The app has no such
///    feature anywhere. A switch that is ON and claims a protection that does
///    not exist is a **security lie**, materially worse than a merely broken
///    preference, and it is the one omission on this screen that is not just a
///    matter of tidiness. Omitted, not disabled: disabled-but-ON still reads as
///    a live guarantee.
/// 2. **The locale picker.** There is no i18n in the app whatsoever.
/// 3. **The map-style picker.** No backend, no client setting behind it.
/// 4. **The vehicle-class picker.** It would imply a standing preference is
///    honoured in dispatch. It is not (and cf. gap 65 — the larger and
///    accessible classes are not even bookable).
///
/// This screen writes NOTHING. The only write in this lane is the deletion /
/// export ticket, and it happens in the popup.
class SettingsScreen extends ConsumerWidget {
  /// Creates the settings screen.
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;

    final themeMode = ref.watch(themeModeProvider);
    final isDark = themeMode == ThemeMode.dark;
    final marketing = ref.watch(marketingConsentProvider);

    return Scaffold(
      key: SettingsScreenKeys.root,
      backgroundColor: colors.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            HopTopBar(
              title: 'Settings',
              onBack: () => context.go('/profile'),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  hoppin.spacing.gutter,
                  hoppin.spacing.md,
                  hoppin.spacing.gutter,
                  hoppin.spacing.xl,
                ),
                children: [
                  // ── The gap-71 rung. ONE for the whole screen, pinned above
                  // the toggle groups. Eight identical rungs would be noise,
                  // and noise is how a disclosure gets ignored.
                  const SettingsPrefsUnavailable(),
                  SizedBox(height: hoppin.spacing.lg),

                  // ── Appearance — the one group that entirely works.
                  const _GroupLabel('Appearance'),
                  HopCard(
                    padding: EdgeInsets.symmetric(
                      vertical: hoppin.spacing.sm,
                    ),
                    child: SettingsToggleRow(
                      key: SettingsScreenKeys.themeToggle,
                      label: 'Dark mode',
                      supporting: 'Applies right away. Resets when you reopen '
                          'the app.',
                      value: isDark,
                      // LIVE. It writes the real theme provider the whole app
                      // watches — not a local bool that pretends to.
                      onChanged: (on) => ref
                          .read(themeModeProvider.notifier)
                          .set(on ? ThemeMode.dark : ThemeMode.light),
                    ),
                  ),
                  SizedBox(height: hoppin.spacing.lg),

                  // ── Notifications — every one of these is inert. The design
                  // is real; the backend is not. They ship at their Figma
                  // default positions so the screen reads correctly and
                  // nothing is claimed.
                  const _GroupLabel('Notifications'),
                  HopCard(
                    padding: EdgeInsets.symmetric(
                      vertical: hoppin.spacing.sm,
                    ),
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SettingsToggleRow(
                          label: 'Ride notifications',
                          value: true,
                          divider: true,
                        ),
                        SettingsToggleRow(
                          label: 'Email notifications',
                          value: true,
                          divider: true,
                        ),
                        SettingsToggleRow(
                          label: 'Chat & message sounds',
                          value: true,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: hoppin.spacing.lg),

                  // ── Privacy & security.
                  const _GroupLabel('Privacy & security'),
                  HopCard(
                    padding: EdgeInsets.symmetric(
                      vertical: hoppin.spacing.sm,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // LIVE — and it is a legal requirement that it is. This
                        // is the SAME session choice the signup toggle collects
                        // (one canonical notifier, not two): withdrawal must be
                        // as easy as giving (Art. 7(3)), and a consent you can
                        // give but never revisit is not a choice at all. A
                        // greyed-out withdrawal control here would retroactively
                        // invalidate the consent given at signup.
                        SettingsToggleRow(
                          key: SettingsScreenKeys.marketingToggle,
                          label: 'Promotional offers',
                          supporting: 'Off by default. We send nothing unless '
                              'you turn this on.',
                          value: marketing,
                          onChanged: (on) => ref
                              .read(marketingConsentProvider.notifier)
                              .set(granted: on),
                          divider: true,
                        ),
                        // Seam #74's SECOND mount site — the withdrawal half,
                        // and the one that matters. It sits directly beneath the
                        // control it qualifies, because a rider deciding whether
                        // to opt in deserves to know, AT THAT MOMENT, that the
                        // choice is session-scoped and that we therefore send
                        // nothing at all. Placed anywhere else it is a footnote.
                        const ConsentRecordUnavailable(),
                        // Inert. Adjacent to the seamed share-link gap (57) —
                        // deliberately wired to NOTHING.
                        const SettingsToggleRow(
                          label: 'Share live location',
                          value: false,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: hoppin.spacing.lg),

                  // ── The route out. Art. 17 is not honoured by a right you
                  // have to know to look for, so it is findable, at the bottom,
                  // in the destructive role — exactly where the Figma puts it.
                  const _GroupLabel('Account'),
                  HopCard(
                    padding: EdgeInsets.symmetric(
                      vertical: hoppin.spacing.sm,
                    ),
                    child: _DeleteAccountRow(
                      key: SettingsScreenKeys.deleteAccountRow,
                      onTap: () => showDeleteAccountPopup(context),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A group heading above a card of controls.
class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    return Padding(
      padding: EdgeInsets.only(
        left: hoppin.spacing.sm,
        bottom: hoppin.spacing.sm,
      ),
      child: Text(
        label,
        style: hoppin.type.bodyMedium.copyWith(color: hoppin.colors.textMid),
      ),
    );
  }
}

/// The red delete-account row. A [HopListRow] paints its icon in the accent
/// role; this route is destructive and must read as destructive, so it is a
/// local row on the error token.
class _DeleteAccountRow extends StatelessWidget {
  const _DeleteAccountRow({required this.onTap, super.key});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: hoppin.spacing.lg,
          vertical: hoppin.spacing.md,
        ),
        child: Row(
          children: [
            Icon(Icons.delete_outline, color: colors.error, size: 22),
            SizedBox(width: hoppin.spacing.md),
            Expanded(
              child: Text(
                'Delete my account',
                style: hoppin.type.bodyMedium.copyWith(color: colors.error),
              ),
            ),
            Icon(Icons.chevron_right, color: colors.error, size: 22),
          ],
        ),
      ),
    );
  }
}
