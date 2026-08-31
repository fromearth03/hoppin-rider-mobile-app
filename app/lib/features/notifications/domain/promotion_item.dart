/// The three states the design draws a coloured pill for.
enum PromotionStatus { active, availed, expired }

/// A single card on the Promotional screen.
///
/// There is no promotions endpoint anywhere in this API today - see
/// [PromotionsSource]. This model exists so the screen has something concrete
/// to render once a real source is plugged in; it is not fed by invented
/// data.
class PromotionItem {
  final String id;
  final String title;
  final String description;
  final PromotionStatus status;
  final DateTime validUntil;

  const PromotionItem({
    required this.id,
    required this.title,
    required this.description,
    required this.status,
    required this.validUntil,
  });
}
