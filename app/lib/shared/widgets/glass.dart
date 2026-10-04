import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../core/theme/colors.dart';

/// The app's glass material.
///
/// The frames already use it in two places (the dark status chips over the
/// live map, the pill buttons under the notification list). This is that same
/// material as one widget, so every surface that floats over the map or over
/// scrolling content is frosted the same way: the layout, type and colours of
/// the design are untouched, the surfaces just stop being flat paint.
///
/// Two kinds, because blur is not free:
///
///  * [Glass] — a real backdrop blur. For the few surfaces that sit over a
///    MOVING background (the map, a scrolling list): the bottom sheets, the
///    round map buttons, the ad banner, the app drawer, dialogs.
///  * [GlassCard] — translucent, no blur. For cards on a static screen, where
///    there is nothing moving behind to blur; the soft [AmbientBackground]
///    tints through instead. A list of twenty of these costs nothing.
class Glass extends StatelessWidget {
  final Widget child;
  final BorderRadius borderRadius;

  /// Blur strength (sigma). 18 reads as frosted without smearing map labels
  /// into mud; go lower for small chips.
  final double blur;

  /// The surface colour before translucency is applied.
  final Color tint;

  /// How solid the surface is. Text sits on this, so it stays high: glass that
  /// costs legibility is decoration at the rider's expense.
  final double opacity;

  /// The bright hairline along the edge that makes glass read as glass.
  final bool highlight;

  /// Drop shadow under the pane. Null for none.
  final List<BoxShadow>? shadow;

  const Glass({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.blur = 18,
    this.tint = Colors.white,
    this.opacity = 0.78,
    this.highlight = true,
    this.shadow = Glass.softShadow,
  });

  /// A soft, wide, low-contrast shadow in the brand navy: depth without the
  /// grey smudge a default elevation leaves under a translucent surface.
  static const softShadow = [
    BoxShadow(color: Color(0x1A181C39), blurRadius: 24, offset: Offset(0, 8)),
  ];

  /// The same shadow thrown upwards, for sheets rising from the bottom edge.
  static const sheetShadow = [
    BoxShadow(color: Color(0x1F181C39), blurRadius: 28, offset: Offset(0, -6)),
  ];

  @override
  Widget build(BuildContext context) {
    final pane = ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: DecoratedBox(
          decoration: BoxDecoration(
            // Slightly brighter at the top-left, as light would catch it.
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                tint.withValues(alpha: (opacity + 0.08).clamp(0.0, 1.0)),
                tint.withValues(alpha: opacity),
              ],
            ),
            borderRadius: borderRadius,
            border: highlight
                ? Border.all(color: Colors.white.withValues(alpha: 0.65))
                : null,
          ),
          child: child,
        ),
      ),
    );
    if (shadow == null) return pane;
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: borderRadius, boxShadow: shadow),
      child: pane,
    );
  }
}

/// A card on a static screen: translucent white with the glass hairline and a
/// soft shadow, no backdrop blur (see [Glass] for why).
class GlassCard extends StatelessWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry? padding;
  final double opacity;

  const GlassCard({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.padding,
    this.opacity = 0.74,
  });

  /// The decoration on its own, for widgets that already own a Container.
  static BoxDecoration decoration({
    BorderRadius borderRadius = const BorderRadius.all(Radius.circular(16)),
    double opacity = 0.74,
  }) =>
      BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: (opacity + 0.12).clamp(0.0, 1.0)),
            Colors.white.withValues(alpha: opacity),
          ],
        ),
        borderRadius: borderRadius,
        border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
        boxShadow: const [
          BoxShadow(
              color: Color(0x0F181C39), blurRadius: 18, offset: Offset(0, 6)),
        ],
      );

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration:
            decoration(borderRadius: borderRadius, opacity: opacity),
        child: child,
      );
}

/// The backdrop the flat screens sit on: the design's light grey, with two
/// very soft brand-coloured glows (indigo top-left, orange bottom-right) so
/// the translucent cards have something to pick up. Deliberately faint: at a
/// glance it is still the plain light background of the frames.
///
/// Opaque, so a page wrapped in it fully covers the page beneath during a
/// route transition.
class AmbientBackground extends StatelessWidget {
  final Widget child;
  const AmbientBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: AppColors.lightBackground),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const Positioned(
            top: -140,
            left: -120,
            child: _Glow(color: AppColors.primary, size: 420, strength: 0.13),
          ),
          const Positioned(
            bottom: -160,
            right: -140,
            child: _Glow(color: AppColors.accent, size: 440, strength: 0.11),
          ),
          const Positioned(
            top: 260,
            right: -180,
            child: _Glow(color: AppColors.info, size: 360, strength: 0.06),
          ),
          child,
        ],
      ),
    );
  }
}

/// A radial fade to nothing: a "blurred orb" without a blur filter.
class _Glow extends StatelessWidget {
  final Color color;
  final double size;
  final double strength;
  const _Glow({required this.color, required this.size, required this.strength});

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                color.withValues(alpha: strength),
                color.withValues(alpha: strength * 0.4),
                color.withValues(alpha: 0),
              ],
              stops: const [0, 0.45, 1],
            ),
          ),
        ),
      );
}

/// A whole screen on the ambient backdrop: [AmbientBackground] plus a theme
/// whose Scaffold and app bar are transparent, so the backdrop shows through.
/// The router wraps every route in this; render tests do the same so a shot
/// looks like the screen does in the app.
class AmbientPage extends StatelessWidget {
  final Widget child;
  const AmbientPage({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    return AmbientBackground(
      child: Theme(
        data: base.copyWith(
          scaffoldBackgroundColor: Colors.transparent,
          appBarTheme: base.appBarTheme.copyWith(
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
          ),
        ),
        child: child,
      ),
    );
  }
}
