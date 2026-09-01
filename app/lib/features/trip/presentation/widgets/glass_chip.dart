import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// The frames' over-map glass surface: a blurred, translucent dark ground
/// with white content on top. One widget so the status banner, turn banner,
/// destination bar and route panel all read as the same material.
class GlassChip extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  const GlassChip({
    super.key,
    required this.child,
    required this.padding,
    this.radius = 14,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: padding,
          color: Colors.black.withValues(alpha: 0.55),
          child: child,
        ),
      ),
    );
  }
}
