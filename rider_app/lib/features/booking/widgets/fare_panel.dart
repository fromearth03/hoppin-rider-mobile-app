import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

/// The fare-estimate money moment (RIDER-01/RIDER-07 research §3: the GBP
/// figure IS the screen).
///
/// Pure presentation, riblet view rules: state in, events out — the panel
/// never touches a repository or the interactor. Composition:
/// - schematic journey header (origin dot, dashed connector, destination
///   node, honest pre-map distance/minutes line);
/// - the GBP total as the typographic hero in tabular Geist Mono, with the
///   "Estimated" badge beside it and an estimate-range line — the price is an
///   honest estimate that settles at drop-off (§3.4 pricing transparency);
/// - the component breakdown collapsed behind a chevron (progressive
///   disclosure — the same Quote maths the pricing engine charges);
/// - the promo code as a collapsed row (Baymard rule: an open field shouts
///   at full-price customers), expanding to an inline upper-case entry and
///   staging a removable chip once committed.
class FarePanel extends StatefulWidget {
  const FarePanel({
    required this.estimate,
    this.pickupLabel,
    this.destinationLabel,
    this.pendingPromoCode,
    this.promoError,
    this.onPromoChanged,
    super.key,
  });

  /// The live quote — mirrors the pricing engine's `Quote` (docs/04).
  final FareEstimate estimate;

  /// Journey labels; the schematic degrades to generic words when absent.
  final String? pickupLabel;
  final String? destinationLabel;

  /// The staged promo code (already normalised) — renders the staged chip.
  final String? pendingPromoCode;

  /// Entry-time rejection from the promo-check seam — rendered under the
  /// promo row in the error colour so a refused code is never silent.
  final String? promoError;

  /// Fired with a normalised upper-case code on commit, or null on removal.
  /// The interactor holds the truth; the panel stays dumb.
  final ValueChanged<String?>? onPromoChanged;

  @override
  State<FarePanel> createState() => _FarePanelState();
}

class _FarePanelState extends State<FarePanel> {
  final _promoCtrl = TextEditingController();
  bool _breakdownOpen = false;
  bool _promoOpen = false;

  @override
  void dispose() {
    _promoCtrl.dispose();
    super.dispose();
  }

  void _commitPromo(String raw) {
    final normalised = raw.trim().toUpperCase();
    setState(() => _promoOpen = false);
    _promoCtrl.clear();
    widget.onPromoChanged?.call(normalised.isEmpty ? null : normalised);
  }

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;
    final type = hoppin.type;
    final q = widget.estimate.estimate;
    final minimumApplied = q.total > q.gross;
    final miles = widget.estimate.distanceMeters / 1609.344;
    final mins = (widget.estimate.durationSeconds / 60).round();

    return HopCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _JourneySchematic(
            pickupLabel: widget.pickupLabel ?? 'Pickup',
            destinationLabel: widget.destinationLabel ?? 'Destination',
          ),
          SizedBox(height: hoppin.spacing.sm),
          Text(
            '${miles.toStringAsFixed(1)} mi · about $mins min',
            style: type.numeralCaption.copyWith(color: colors.textMid),
          ),
          SizedBox(height: hoppin.spacing.lg),
          // ── The hero: the GBP figure IS the screen ────────────────────
          Row(
            children: [
              Text(
                formatPounds(q.total),
                style: type.moneyHero.copyWith(color: colors.textHi),
              ),
              SizedBox(width: hoppin.spacing.md),
              const StatusPill(label: 'Estimated', tone: PillTone.accent),
            ],
          ),
          SizedBox(height: hoppin.spacing.xs),
          // Estimate-range framing (BOOK-05): the total is an honest estimate,
          // the final fare is settled at drop-off — never a silent number.
          Text(
            'Estimated — final fare settled at drop-off',
            style: type.numeralCaption.copyWith(color: colors.textMid),
          ),
          SizedBox(height: hoppin.spacing.md),
          _hairline(colors),
          // ── Breakdown: progressive disclosure ─────────────────────────
          InkWell(
            onTap: () => setState(() => _breakdownOpen = !_breakdownOpen),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Row(
                children: [
                  Text(
                    'Fare breakdown',
                    style: type.label.copyWith(color: colors.textMid),
                  ),
                  const Spacer(),
                  AnimatedRotation(
                    turns: _breakdownOpen ? 0.5 : 0,
                    duration: hoppin.motion.quick,
                    curve: hoppin.motion.easeOut,
                    child: Icon(
                      Icons.expand_more,
                      size: 20,
                      color: colors.textMid,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: hoppin.motion.quick,
            curve: hoppin.motion.easeOut,
            alignment: Alignment.topCenter,
            child: !_breakdownOpen
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: EdgeInsets.only(bottom: hoppin.spacing.sm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _breakdownRow(context, 'Base fare', q.base),
                        _breakdownRow(context, 'Distance', q.distance),
                        _breakdownRow(context, 'Time', q.time),
                        _breakdownRow(context, 'Service fee', q.serviceFee),
                        // §3.4 (BOOK-06): the surge row ALWAYS renders — at the
                        // ×1.0 baseline it says so in plain English; a rider
                        // never sees surge silently absent.
                        _breakdownRow(
                          context,
                          q.surge > 1.0
                              ? 'Surge ×${q.surge.toStringAsFixed(2)} '
                                    '(busy — higher demand)'
                              : 'Surge — none right now',
                          null,
                        ),
                        if (minimumApplied)
                          Padding(
                            padding: EdgeInsets.only(top: hoppin.spacing.xs),
                            child: Text(
                              'Minimum fare applied',
                              style: type.bodySmall.copyWith(
                                color: colors.textMid,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
          _hairline(colors),
          SizedBox(height: hoppin.spacing.xs),
          _PromoRow(
            pendingPromoCode: widget.pendingPromoCode,
            open: _promoOpen,
            controller: _promoCtrl,
            onOpen: () => setState(() => _promoOpen = true),
            onCommit: _commitPromo,
            onRemove: () => widget.onPromoChanged?.call(null),
          ),
          if (widget.promoError != null) ...[
            SizedBox(height: hoppin.spacing.xs),
            Text(
              widget.promoError!,
              style: hoppin.type.bodySmall.copyWith(color: colors.error),
            ),
          ],
        ],
      ),
    );
  }

  Widget _hairline(HoppinColors colors) =>
      Container(height: 1, color: colors.hairline);

  Widget _breakdownRow(BuildContext context, String label, double? pounds) {
    final hoppin = context.hoppin;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: hoppin.spacing.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: hoppin.type.bodySmall.copyWith(color: hoppin.colors.textMid),
          ),
          if (pounds != null)
            Text(
              formatPounds(pounds),
              style: hoppin.type.numeralCaption.copyWith(
                color: hoppin.colors.textHi,
              ),
            ),
        ],
      ),
    );
  }
}

/// Origin dot, dashed connector, destination node, labels — the honest
/// pre-map journey card (list-first is a locked decision; maps are Phase 6).
class _JourneySchematic extends StatelessWidget {
  const _JourneySchematic({
    required this.pickupLabel,
    required this.destinationLabel,
  });

  final String pickupLabel;
  final String destinationLabel;

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;
    final type = hoppin.type;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 12,
            child: Column(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.accent, width: 2),
                  ),
                ),
                Expanded(
                  child: CustomPaint(
                    size: const Size(12, double.infinity),
                    painter: _DashedConnectorPainter(color: colors.hairline),
                  ),
                ),
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: colors.accent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: hoppin.spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pickupLabel,
                  style: type.body.copyWith(color: colors.textHi),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: hoppin.spacing.md),
                Text(
                  destinationLabel,
                  style: type.body.copyWith(color: colors.textHi),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DashedConnectorPainter extends CustomPainter {
  const _DashedConnectorPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    const dash = 3.0;
    const gap = 3.5;
    final x = size.width / 2;
    var y = 2.0;
    while (y < size.height - 2) {
      canvas.drawLine(
        Offset(x, y),
        Offset(x, math.min(y + dash, size.height - 2)),
        paint,
      );
      y += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedConnectorPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// The promo affordance: collapsed row → inline upper-case entry → staged
/// removable chip. Events out only.
class _PromoRow extends StatelessWidget {
  const _PromoRow({
    required this.pendingPromoCode,
    required this.open,
    required this.controller,
    required this.onOpen,
    required this.onCommit,
    required this.onRemove,
  });

  final String? pendingPromoCode;
  final bool open;
  final TextEditingController controller;
  final VoidCallback onOpen;
  final ValueChanged<String> onCommit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;
    final type = hoppin.type;
    final staged = pendingPromoCode;

    if (staged != null) {
      return Row(
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
            onPressed: onRemove,
          ),
        ],
      );
    }

    if (open) {
      return Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(hintText: 'e.g. HOPPIN20'),
              onSubmitted: onCommit,
            ),
          ),
          SizedBox(width: hoppin.spacing.sm),
          FilledButton(
            onPressed: () => onCommit(controller.text),
            child: const Text('Apply'),
          ),
        ],
      );
    }

    return InkWell(
      onTap: onOpen,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          children: [
            Icon(Icons.local_offer_outlined, size: 18, color: colors.accent),
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
    );
  }
}
