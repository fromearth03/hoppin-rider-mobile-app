import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/result.dart';
import '../../../core/theme/colors.dart';
import '../../../shared/nav/app_router.dart';
import '../../../shared/widgets/bottom_scroll_fade.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../safety/data/safety_repository.dart';
import '../data/faq_repository.dart';
import 'widgets/settings_card.dart';
import 'widgets/settings_header.dart';

/// The platform's live contact points (admin-configured, `GET /contacts`).
final _platformContactsProvider =
    FutureProvider.autoDispose<PlatformContacts?>((ref) async {
  final result =
      await ref.watch(safetyRepositoryProvider).platformContacts();
  return switch (result) {
    Ok(:final value) => value,
    // The section falls back to the static support address rather than
    // vanishing.
    Err() => null,
  };
});

/// Help & Support — `Help & Support.png` (added to the pack 2026-08-31; the
/// first build of this screen predates the design and was laid out blind).
///
/// Three sections, as drawn: an FAQ accordion, two contact cards, and legal
/// links.
///
/// Deviations, recorded in SCREEN-DECISIONS.md:
/// - The design's second question, "What if any of my document expires?", is
///   driver vocabulary — riders hold no documents this service tracks. It is
///   dropped rather than shown to riders who could make nothing of it.
/// - "Open Ticket" is drawn as a live card and `Support.png` draws a whole
///   ticket-filing flow behind it, but no support-ticket endpoint exists in
///   the rider API, so the card renders disabled with the established "Soon"
///   treatment rather than opening a form that submits into nowhere.
/// - FAQ copy is operator-written (`GET /faqs?audience=rider`, migration 133),
///   not bundled: the answers describe rules the panel changes in seconds, so
///   copy that could only change with a store release was copy guaranteed to
///   go stale.
/// - The legal rows are drawn as accordions, but no terms or privacy-policy
///   documents exist to put inside them; they render disabled until the
///   documents do.
/// - Email stays plain text: `url_launcher` is not a dependency, so a mailto
///   link cannot be opened from here.
class HelpSupportScreen extends ConsumerWidget {
  const HelpSupportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final faqs = ref.watch(riderFaqsProvider);

    return Scaffold(
      appBar: const SettingsHeader(title: 'Help & Support'),
      body: SafeArea(
        // The frames fade scrolling content into the background at the
        // bottom edge; the fade dissolves once the rider reaches the end.
        child: BottomScrollFade(
          child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            SettingsCard(
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Text('Frequently Asked Questions (FAQs)',
                      style: theme.textTheme.titleMedium),
                ),
                // SettingsCard inserts the dividers between children; adding
                // our own here doubled every line in the render.
                ...faqs.when(
                  // Fixed blocks, not SkeletonList: this card already sits
                  // inside the page's ListView, and a nested scrollable has no
                  // bounded height to expand into.
                  loading: () => [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                      child: Column(
                        children: [
                          Skeleton.block(height: 18),
                          const SizedBox(height: 14),
                          Skeleton.block(height: 18),
                          const SizedBox(height: 14),
                          Skeleton.block(height: 18),
                        ],
                      ),
                    ),
                  ],
                  // Said plainly rather than as an empty list: "Hoppin has no
                  // answers" and "we could not load them" are different
                  // messages, and the rider opened this screen for help.
                  error: (_, __) => const [
                    _FaqMessage(
                        'We could not load the answers right now. '
                        'Check your connection and try again.'),
                  ],
                  data: (list) => list.isEmpty
                      ? const [_FaqMessage('No questions have been added yet.')]
                      : [
                          for (final (i, faq) in list.indexed)
                            _FaqTile(
                              question: faq.question,
                              answer: faq.answer,
                              // The frame draws the first question already open.
                              initiallyOpen: i == 0,
                            ),
                        ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            SettingsCard(
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Text('Contact to Support',
                      style: theme.textTheme.titleMedium),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _ContactCard(
                          icon: Icons.find_in_page_outlined,
                          title: 'Open Ticket',
                          subtitle: 'Representative will respond in 24 Hours',
                          enabled: true,
                          // Live: POST /me/support-tickets exists now.
                          onTap: () => context.push(AppRoutes.supportTicket),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _ContactCard(
                          icon: Icons.report_problem_outlined,
                          title: 'File a Complaint',
                          subtitle: 'Something went wrong on a ride',
                          enabled: true,
                          onTap: () => context.push(
                              '${AppRoutes.supportTicket}?tab=complaints'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SettingsCard(
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Text('Legal', style: theme.textTheme.titleMedium),
                ),
                const _LegalRow(label: 'Terms of Services'),
                const _LegalRow(label: 'Privacy Policy'),
              ],
            ),
            const SizedBox(height: 20),
            // Live contact points from the admin's platform-contacts config —
            // the email card's information, restored at the bottom with the
            // emergency number beside it.
            const _ContactsSection(),
          ],
          ),
        ),
      ),
    );
  }
}

/// "Contact & Emergency" — the admin-configured numbers off `GET /contacts`,
/// with the static support address as the fallback when the fetch fails.
class _ContactsSection extends ConsumerWidget {
  const _ContactsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final contacts = ref.watch(_platformContactsProvider).valueOrNull;

    final email = contacts?.supportEmail ?? 'Support@hoppin.com';
    final phone = contacts?.supportPhone;
    final emergency = contacts?.emergencyPhone;
    final whatsapp = contacts?.whatsappNumber;

    Widget row(IconData icon, String label, String value, {Color? color}) =>
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 20, color: color ?? AppColors.navy),
              const SizedBox(width: 12),
              Text(label, style: theme.textTheme.bodyMedium),
              const Spacer(),
              SelectableText(value,
                  style: theme.textTheme.bodyLarge?.copyWith(
                      fontSize: 14,
                      color: color ?? AppColors.navy,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        );

    return SettingsCard(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
        child:
            Text('Contact & Emergency', style: theme.textTheme.titleMedium),
      ),
      row(Icons.mail_outline, 'Email', email),
      if (phone != null && phone.isNotEmpty)
        row(Icons.phone_outlined, 'Phone', phone),
      if (whatsapp != null && whatsapp.isNotEmpty)
        row(Icons.chat_outlined, 'WhatsApp', whatsapp),
      if (emergency != null && emergency.isNotEmpty)
        row(Icons.emergency_outlined, 'Emergency', emergency,
            color: AppColors.negative),
      const SizedBox(height: 8),
    ]);
  }
}

/// One expandable question, as the design's accordion draws it — bullet,
/// question, chevron that flips when open.
/// Copy shown in place of the accordion — empty, or unreachable.
class _FaqMessage extends StatelessWidget {
  final String text;
  const _FaqMessage(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
        child: Text(
          text,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: AppColors.lightTextSecondary),
        ),
      );
}

class _FaqTile extends StatefulWidget {
  final String question;
  final String answer;
  final bool initiallyOpen;

  const _FaqTile({
    required this.question,
    required this.answer,
    this.initiallyOpen = false,
  });

  @override
  State<_FaqTile> createState() => _FaqTileState();
}

class _FaqTileState extends State<_FaqTile> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
            child: Row(
              children: [
                Text('•  ', style: theme.textTheme.bodyLarge),
                Expanded(
                  child: Text(widget.question,
                      style: theme.textTheme.bodyLarge),
                ),
                Icon(
                  _open
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  // Sampled from the frame: the chevrons sit lighter than
                  // body text.
                  color: theme.brightness == Brightness.light
                      ? const Color(0xFFAEB0BA)
                      : theme.textTheme.bodyMedium?.color,
                ),
              ],
            ),
          ),
        ),
        if (_open)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                widget.answer,
                // The frame paints answers in the same navy as questions,
                // not the secondary grey.
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.textTheme.bodyLarge?.color),
              ),
            ),
          ),
      ],
    );
  }
}

/// One of the design's two square contact tiles. A disabled tile carries the
/// same "Soon" treatment the rest of the app uses for controls with no
/// backend, rather than looking tappable and doing nothing.
class _ContactCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback? onTap;

  const _ContactCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final titleColor = enabled
        ? theme.textTheme.bodyLarge?.color
        : theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.5);
    // The frame keeps the subtitle grey even on the live tile; only the
    // icon and title carry the navy.
    final subtitleColor = enabled
        ? theme.textTheme.bodyMedium?.color
        : theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.5);

    final card = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkBackground : AppColors.lightBackground,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 30, color: titleColor),
          const SizedBox(height: 12),
          Row(
            children: [
              Flexible(
                child: Text(title,
                    style:
                        theme.textTheme.bodyLarge?.copyWith(color: titleColor)),
              ),
              if (!enabled) ...[
                const SizedBox(width: 6),
                Text('Soon',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontSize: 11, color: titleColor)),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(subtitle,
              style:
                  theme.textTheme.bodyMedium?.copyWith(color: subtitleColor)),
        ],
      ),
    );

    if (onTap == null) return card;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: card,
    );
  }
}

/// Drawn as an accordion, but there is no document to expand — no terms or
/// privacy text exists anywhere in the project or the API. Disabled until one
/// does; an accordion opening onto nothing would be worse.
class _LegalRow extends StatelessWidget {
  final String label;

  const _LegalRow({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.5);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
      child: Row(
        children: [
          Text('•  ', style: TextStyle(color: muted, fontSize: 16)),
          Expanded(
            child: Text(label,
                style: theme.textTheme.bodyLarge?.copyWith(color: muted)),
          ),
          Text('Soon',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontSize: 11, color: muted)),
        ],
      ),
    );
  }
}
