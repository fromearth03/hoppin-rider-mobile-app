import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

/// The operator's real support/emergency details — `GET /api/v1/contacts`.
///
/// Public (no JWT) and admin-edited, so a number change never needs an app
/// release. `autoDispose` because this screen is a leaf the rider opens rarely;
/// re-entering re-reads rather than serving a number that changed last week.
final platformContactsProvider =
    FutureProvider.autoDispose<PlatformContacts>((ref) {
  return ref.watch(ridesRepositoryProvider).contacts();
});

/// Profile › Help & Support (Figma #38) — `/profile/help`.
///
/// 🔴 **This screen was never built, and nobody noticed** — because the Profile
/// hub's "Help & Support" row *looked* wired. It points at `/support`, which is
/// the ticket TAB: a different screen, with a different job. The frame the hub
/// actually promises is this one: FAQ + Contact + Legal. No tickets on it.
///
/// It needs **zero backend**, and it is where the **privacy-notice link that
/// COMPLY-01 depends on** lives. Cheapest, highest-value screen in the phase.
///
/// ⚠️ **The FRAME's phone number and support email address are PLACEHOLDERS.**
/// They are not real, and shipping them would be a dead end that lies — a rider
/// would ring the number. (Their literal values are deliberately NOT quoted
/// here: the guard test greps this source for them.)
///
/// ✅ **Real details now arrive from the server.** `GET /api/v1/contacts` is
/// public (no JWT — a rider in trouble may not be signed in) and serves
/// admin-edited `platform_contacts`. It existed for this screen's whole life
/// and nothing called it, so the card said "we do not have a public support
/// phone line yet" while the backend was serving one. That sentence is now
/// shown ONLY when the operator has genuinely published nothing.
///
/// 🔴 **The dial/email URI-scheme pin still holds, deliberately.** Details are
/// rendered as selectable TEXT, never as launch schemes: the Phase 11 pin is
/// what stops a tap dialling a number that turns out to be stale, and nothing
/// here needs to break it to be useful. Do not "improve" this into a dial
/// button.
///
/// (⚠️ The literal schemes are NOT spelled out anywhere in this file — the
/// guard test greps this source for them, so a comment quoting them would trip
/// the pin permanently. Same trap the promotions screen documents.)
class HelpSupportScreen extends ConsumerWidget {
  /// Creates the Help & Support screen.
  const HelpSupportScreen({super.key});

  static const _faqs = <(String, String)>[
    (
      'How do I book a ride?',
      'Enter your pickup and destination on the Book tab, choose the ride type '
          "you want, and confirm. We'll match you with a nearby driver and show "
          'you their car and plate.',
    ),
    (
      'How is my fare worked out?',
      'The estimate you see before booking is based on the route and the ride '
          'type. The final fare can differ if the route changes, if you wait, '
          'or if there are tolls or charges along the way.',
    ),
    (
      'Can I cancel a ride?',
      'Yes. If a driver is already on the way, a cancellation fee may apply — '
          "we'll tell you before you confirm the cancellation.",
    ),
    (
      'What if I leave something in the car?',
      'Open a ticket and tell us which ride it was. We can pass a message to '
          'the driver.',
    ),
    (
      'How do I get my data, or delete my account?',
      'Both are your right, and both go through a support ticket from Profile. '
          'A person actions it. Some ride and payment records have to be kept '
          'for licensing and tax reasons even after a deletion request, and the '
          'Privacy Notice explains which.',
    ),
    (
      'Why am I not getting marketing emails?',
      "Because we're not sending any. The marketing toggle is off unless you "
          "turn it on, and until we can record your choice properly we don't "
          'send marketing to anyone. This has no effect on your rides.',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;
    final type = hoppin.type;
    // Public read; an outage degrades to the tickets-only copy below.
    final contactsAsync = ref.watch(platformContactsProvider);
    final contacts = contactsAsync.hasValue
        ? contactsAsync.requireValue
        : const PlatformContacts();

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // A DEAD END until now. This screen is outside the shell, so no
            // bottom nav and no shell bar reach it, and the stock AppBar it used
            // only auto-draws a back arrow when `Navigator.canPop()` is true.
            // The Profile hub reaches it with `context.go`, which REPLACES
            // rather than pushes — so nothing could be popped, the arrow never
            // rendered, and the rider was trapped on the help screen. Pop when
            // there is a stack; otherwise fall back to the hub this row lives
            // on.
            HopTopBar(
              title: 'Help & Support',
              onBack: () =>
                  context.canPop() ? context.pop() : context.go('/profile'),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.all(hoppin.spacing.gutter),
                children: [
                  Text(
                    'FAQs',
                    style: type.section.copyWith(color: colors.textHi),
                  ),
                  SizedBox(height: hoppin.spacing.md),
                  HopCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Expand/collapse is EPHEMERAL view state — ExpansionTile's
                        // own StatefulWidget. Nothing here needs persisting, and
                        // nothing here may persist.
                        for (final (question, answer) in _faqs)
                          ExpansionTile(
                            title: Text(
                              question,
                              style: type.bodyMedium.copyWith(
                                color: colors.textHi,
                              ),
                            ),
                            childrenPadding: EdgeInsets.fromLTRB(
                              hoppin.spacing.lg,
                              0,
                              hoppin.spacing.lg,
                              hoppin.spacing.lg,
                            ),
                            expandedCrossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(
                                answer,
                                style: type.bodySmall.copyWith(
                                  color: colors.textMid,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  SizedBox(height: hoppin.spacing.xl),
                  Text(
                    'Contact us',
                    style: type.section.copyWith(color: colors.textHi),
                  ),
                  SizedBox(height: hoppin.spacing.md),
                  HopCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Open a ticket — that’s the fastest way to reach us.',
                          style: type.bodyMedium.copyWith(color: colors.textHi),
                        ),
                        SizedBox(height: hoppin.spacing.sm),
                        Text(
                          contacts.hasAny
                              ? 'Tickets go to a real person and you can follow '
                                  'the reply thread in the app. You can also '
                                  'reach us directly:'
                              // Unchanged, and still true when the operator has
                              // published nothing: better to say so than print a
                              // number nobody answers.
                              : 'Tickets go to a real person and you can follow '
                                  'the reply thread in the app. We do not have a '
                                  'public support phone line yet, and we would '
                                  'rather say so than print a number that nobody '
                                  'answers.',
                          style: type.bodySmall.copyWith(color: colors.textMid),
                        ),
                        // Real, admin-edited details. Selectable TEXT, never a
                        // dial/email launcher — see the class doc.
                        if (contacts.hasAny) ...[
                          SizedBox(height: hoppin.spacing.md),
                          _ContactRow(
                            icon: Icons.mail_outline,
                            label: 'Email',
                            value: contacts.supportEmail,
                          ),
                          _ContactRow(
                            icon: Icons.phone_outlined,
                            label: 'Phone',
                            value: contacts.supportPhone,
                          ),
                          _ContactRow(
                            icon: Icons.chat_outlined,
                            label: 'WhatsApp',
                            value: contacts.whatsappNumber,
                          ),
                          _ContactRow(
                            icon: Icons.emergency_outlined,
                            label: 'Urgent safety line',
                            value: contacts.emergencyPhone,
                          ),
                        ],
                        SizedBox(height: hoppin.spacing.md),
                        HopButton.primary(
                          key: const Key('help_open_ticket'),
                          label: 'Open a support ticket',
                          onPressed: () =>
                              GoRouter.maybeOf(context)?.go('/support'),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: hoppin.spacing.xl),
                  Text(
                    'Legal',
                    style: type.section.copyWith(color: colors.textHi),
                  ),
                  SizedBox(height: hoppin.spacing.md),
                  HopCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        HopListRow(
                          icon: Icons.description_outlined,
                          label: 'Terms of Service',
                          divider: true,
                          onTap: () =>
                              GoRouter.maybeOf(context)?.push('/legal/terms'),
                        ),
                        // The Arts. 13/14 transparency route COMPLY-01 depends on. It
                        // RESOLVES — the notice is bundled in-app and versioned.
                        HopListRow(
                          icon: Icons.privacy_tip_outlined,
                          label: 'Privacy Policy',
                          onTap: () =>
                              GoRouter.maybeOf(context)?.push('/legal/privacy'),
                        ),
                      ],
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

/// One real contact detail: quiet glyph, label, selectable value.
///
/// Renders NOTHING when [value] is null — an operator who has published a
/// support email but no WhatsApp number gets one row, not a row with a blank
/// where a number should be.
///
/// The value is [SelectableText] so a rider can copy it into their own dialler
/// or mail app. That is the deliberate alternative to a dial/email URI scheme,
/// which stays pinned at zero — the rider chooses to act on the number rather
/// than the app firing an intent at one that may be stale.
class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final v = value;
    if (v == null) return const SizedBox.shrink();

    final hoppin = context.hoppin;
    final colors = hoppin.colors;
    return Padding(
      padding: EdgeInsets.only(top: hoppin.spacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: colors.textMid),
          SizedBox(width: hoppin.spacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: hoppin.type.labelSmall.copyWith(color: colors.textMid),
                ),
                SelectableText(
                  v,
                  style: hoppin.type.bodyMedium.copyWith(color: colors.textHi),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
