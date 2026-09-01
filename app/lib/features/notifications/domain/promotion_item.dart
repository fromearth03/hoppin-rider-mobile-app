/// The three states the design draws a coloured pill for.
enum PromotionStatus { active, availed, expired }

/// A single card on the Promotional screen, from `GET /promotions`.
class PromotionItem {
  /// The promo code - the server's own identifier for the offer, and the
  /// thing the rider types at checkout.
  final String id;
  final String title;
  final String description;

  /// Server-owned (`state` on the wire) so the client never guesses which
  /// pill an offer wears.
  final PromotionStatus status;

  /// Null for an open-ended offer. The frame always draws a Valid Until line,
  /// but a fabricated date is worse than no line at all, so the card omits it.
  final DateTime? validUntil;

  const PromotionItem({
    required this.id,
    required this.title,
    required this.description,
    required this.status,
    required this.validUntil,
  });
}
