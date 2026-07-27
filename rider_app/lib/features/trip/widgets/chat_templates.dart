import 'package:flutter/material.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

/// COMMS-01 — the quick-reply chip row that sits directly above the chat
/// composer (Figma `Active trip (chat).jpg`).
///
/// This is MISSING-FE only, with **zero backend work and zero contract risk**:
/// `POST /rides/:id/messages` already takes a free-text `body`, so a chip is
/// literally `_send(templateText)` — the same BOUND endpoint, the same send
/// path, the same `409 CHAT_CLOSED` handling as the composer.
///
/// The three strings are **verbatim Figma copy**. They are asserted
/// character-for-character in `chat_templates_test.dart`; a reword is a spec
/// break, not a style choice.
class ChatTemplates extends StatelessWidget {
  /// Creates the template chip row.
  const ChatTemplates({required this.onSend, super.key});

  /// The three quick replies, **verbatim from Figma** — order included.
  static const List<String> templates = <String>[
    'Where are you?',
    "I'm waiting",
    'Running late',
  ];

  /// Fired with the tapped chip's body, verbatim. The host wires this to the
  /// same `_send` path the composer uses — never a separate endpoint, never a
  /// prefill.
  final ValueChanged<String> onSend;

  @override
  Widget build(BuildContext context) {
    final spacing = context.hoppin.spacing;

    return SizedBox(
      // 44, not 40: the chips fill this row's height, so the row's height IS
      // the touch target and 40 left it under the floor.
      height: 44 + spacing.sm * 2,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(
          horizontal: spacing.md,
          vertical: spacing.sm,
        ),
        itemCount: templates.length,
        separatorBuilder: (_, _) => SizedBox(width: spacing.sm),
        itemBuilder: (context, i) {
          final body = templates[i];
          return _TemplateChip(label: body, onTap: () => onSend(body));
        },
      ),
    );
  }
}

class _TemplateChip extends StatelessWidget {
  const _TemplateChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;
    final radius = BorderRadius.circular(hoppin.radii.pill);

    // The fill and the border belong to the SAME shape. They used to be split
    // across a Material colour and an inner Container decoration, which paints
    // the border on a different layer from the fill it is supposed to contain —
    // so the fill antialiased past the stroke on the pill's tight curve and the
    // chip's edge read as soft rather than drawn.
    final shape = RoundedRectangleBorder(
      borderRadius: radius,
      side: BorderSide(color: colors.hairline),
    );

    return Material(
      color: colors.card,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        customBorder: shape,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: hoppin.spacing.lg,
            vertical: hoppin.spacing.sm,
          ),
          child: Center(
            widthFactor: 1,
            child: Text(
              label,
              style: hoppin.type.meta.copyWith(color: colors.textHi),
              maxLines: 1,
            ),
          ),
        ),
      ),
    );
  }
}
