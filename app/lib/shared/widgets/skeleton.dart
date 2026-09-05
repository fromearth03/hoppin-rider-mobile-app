import 'package:flutter/material.dart';

/// Loading placeholders that mirror the shape of the content they stand in for.
///
/// Why these rather than a spinner: a spinner gives the eye nothing to parse, so
/// the wait feels longer, and the page lurches when content finally arrives
/// because nothing reserved its space. A skeleton does both jobs — it occupies
/// the real layout and it reads as "working".
///
/// The rule these widgets exist to enforce: a skeleton means LOADING and
/// nothing else. It must never stand in for an empty list or a failed request —
/// a placeholder that never resolves is a screen quietly lying about its state.
/// Use [SkeletonSwitcher] to keep loading, empty and failed genuinely distinct.
class Skeleton extends StatefulWidget {
  final double? width;
  final double height;
  final BorderRadius radius;

  const Skeleton({
    super.key,
    this.width,
    this.height = 14,
    BorderRadius? radius,
  }) : radius = radius ?? const BorderRadius.all(Radius.circular(6));

  /// A circle — avatars, icon slots.
  factory Skeleton.circle(double size) => Skeleton(
        width: size,
        height: size,
        radius: BorderRadius.all(Radius.circular(size / 2)),
      );

  /// A card-sized block.
  factory Skeleton.block({double height = 80, BorderRadius? radius}) =>
      Skeleton(
        height: height,
        radius: radius ?? const BorderRadius.all(Radius.circular(14)),
      );

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void initState() {
    super.initState();
    // Respect the platform's reduced-motion setting: a shimmer is decoration,
    // and for some people it is actively unpleasant.
    if (!WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final base = dark ? const Color(0xFF25283D) : const Color(0xFFE9EAF0);
    final highlight = dark ? const Color(0xFF31344D) : const Color(0xFFF5F6FA);

    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          // A band of lighter colour travelling left to right.
          final t = _c.isAnimating ? _c.value : 0.5;
          return Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              borderRadius: widget.radius,
              gradient: LinearGradient(
                begin: Alignment(-1.0 - 2 * (1 - t), 0),
                end: Alignment(1.0 - 2 * (1 - t), 0),
                colors: [base, highlight, base],
                stops: const [0.35, 0.5, 0.65],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A stack of list-row skeletons — history, notifications, saved places.
class SkeletonList extends StatelessWidget {
  final int rows;
  final double rowHeight;
  final EdgeInsets padding;
  final bool leadingCircle;

  const SkeletonList({
    super.key,
    this.rows = 5,
    this.rowHeight = 76,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 8),
    this.leadingCircle = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: padding,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: rows,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (leadingCircle) ...[
            Skeleton.circle(40),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Vary the widths so it reads as text, not as a barcode.
                Skeleton(width: i.isEven ? 180 : 210, height: 15),
                const SizedBox(height: 10),
                Skeleton(width: i.isEven ? 120 : 96, height: 12),
                SizedBox(height: rowHeight - 61),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const Skeleton(width: 56, height: 15),
        ],
      ),
    );
  }
}

/// Card-shaped skeletons for grid pickers (vehicle types, payment methods).
class SkeletonCards extends StatelessWidget {
  final int count;
  final double height;
  final EdgeInsets padding;

  const SkeletonCards({
    super.key,
    this.count = 3,
    this.height = 96,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Column(
          children: [
            for (var i = 0; i < count; i++) ...[
              Skeleton.block(height: height),
              if (i != count - 1) const SizedBox(height: 12),
            ],
          ],
        ),
      );
}
