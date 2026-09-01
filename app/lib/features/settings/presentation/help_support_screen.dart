import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/colors.dart';
import '../../../shared/nav/app_router.dart';
import 'widgets/settings_card.dart';
import 'widgets/settings_header.dart';

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
/// - The legal rows are drawn as accordions, but no terms or privacy-policy
///   documents exist to put inside them; they render disabled until the
///   documents do.
/// - Email stays plain text: `url_launcher` is not a dependency, so a mailto
///   link cannot be opened from here.
class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  // The design's questions only — inventing FAQ copy is the designer's call,
  // not ours. The dropped documents question is recorded as a deviation.
  static const _faqs = [
    (
      'Penalty for cancellation after arrival?',
      'If a driver cancels a ride after arriving at pickup, then £5 fee is '
          'charged as penalty.',
    ),
    (
      'How to Dispute',
      'Email us at Support@hoppin.com with your ride details and we will '
          'look into it. A representative responds within 24 hours.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: const SettingsHeader(title: 'Help & Support'),
      body: SafeArea(
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
                for (final (i, faq) in _faqs.indexed)
                  _FaqTile(
                    question: faq.$1,
                    answer: faq.$2,
                    // The frame draws the first question already open.
                    initiallyOpen: i == 0,
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
                      const Expanded(
                        child: _ContactCard(
                          icon: Icons.mail_outline,
                          title: 'Email',
                          subtitle: 'Support@hoppin.com',
                          enabled: true,
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
          ],
        ),
      ),
    );
  }
}

/// One expandable question, as the design's accordion draws it — bullet,
/// question, chevron that flips when open.
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
