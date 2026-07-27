import 'package:flutter/material.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

/// The promo affordance for the Book Ride surface: a collapsed "Add promo
/// code" row → inline upper-case entry → staged removable chip. Events out
/// only — the interactor holds the truth via [onPromoChanged]; the widget
/// stays dumb (riblet view rule).
///
/// Lifted out of the former FarePanel so the Figma Book Ride composition
/// (FareEstimateCard for the fare, this row for the promo) keeps the promo
/// staging reachable without changing any interactor logic. Baymard rule: the
/// field never renders pre-opened at full price.
class PromoRow extends StatefulWidget {
  const PromoRow({
    required this.pendingPromoCode,
    required this.onPromoChanged,
    this.promoError,
    super.key,
  });

  /// The staged promo code (already normalised) — renders the staged chip.
  final String? pendingPromoCode;

  /// Fired with a normalised upper-case code on commit, or null on removal.
  final ValueChanged<String?> onPromoChanged;

  /// Entry-time rejection from the promo-check seam — rendered under the row
  /// in the error colour so a refused code is never silent.
  final String? promoError;

  @override
  State<PromoRow> createState() => _PromoRowState();
}

class _PromoRowState extends State<PromoRow> {
  final _ctrl = TextEditingController();
  bool _open = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _commit(String raw) {
    final normalised = raw.trim().toUpperCase();
    setState(() => _open = false);
    _ctrl.clear();
    widget.onPromoChanged(normalised.isEmpty ? null : normalised);
  }

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;
    final type = hoppin.type;
    final staged = widget.pendingPromoCode;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (staged != null)
          Row(
            children: [
              Icon(Icons.local_offer, size: 16, color: colors.success),
              SizedBox(width: hoppin.spacing.sm),
              Expanded(
                child: Text(
                  '$staged · will be applied to this trip',
                  style: type.label.copyWith(color: colors.success),
                ),
              ),
              IconButton(
                tooltip: 'Remove promo code',
                icon: Icon(Icons.close, size: 18, color: colors.textMid),
                onPressed: () => widget.onPromoChanged(null),
              ),
            ],
          )
        else if (_open)
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(hintText: 'e.g. HOPPIN20'),
                  onSubmitted: _commit,
                ),
              ),
              SizedBox(width: hoppin.spacing.sm),
              HopButton.secondary(
                label: 'Apply',
                expand: false,
                onPressed: () => _commit(_ctrl.text),
              ),
            ],
          )
        else
          InkWell(
            onTap: () => setState(() => _open = true),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Row(
                children: [
                  Icon(
                    Icons.local_offer_outlined,
                    size: 18,
                    color: colors.accent,
                  ),
                  SizedBox(width: hoppin.spacing.sm),
                  Text(
                    'Add promo code',
                    style: type.bodySmall.copyWith(color: colors.textHi),
                  ),
                  const Spacer(),
                  Icon(Icons.expand_more, size: 20, color: colors.textMid),
                ],
              ),
            ),
          ),
        if (widget.promoError != null) ...[
          SizedBox(height: hoppin.spacing.xs),
          Text(
            widget.promoError!,
            style: type.bodySmall.copyWith(color: colors.error),
          ),
        ],
      ],
    );
  }
}
