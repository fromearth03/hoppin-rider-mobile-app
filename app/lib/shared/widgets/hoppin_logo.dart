import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The "Hoppin' Go" lockup that sits at the foot of the auth screens.
///
/// The supplied brand vector, rendered as-is. The wordmark is outlined paths
/// rather than text, so it needs no font and cannot reflow; the whole lockup
/// stays sharp at any size.
///
/// Two files rather than a runtime tint: the wordmark's near-black would
/// disappear on a dark surface, but the mark's red must NOT change with it, so
/// a single `colorFilter` over the lockup is not an option. The dark variant
/// differs only in the wordmark's fill.
class HoppinLogo extends StatelessWidget {
  /// Rendered height. The lockup's aspect ratio is fixed by the asset.
  final double height;

  const HoppinLogo({super.key, this.height = 34});

  static const _aspect = 257 / 43;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SvgPicture.asset(
      isDark
          ? 'assets/brand/hoppin_go_dark.svg'
          : 'assets/brand/hoppin_go.svg',
      height: height,
      width: height * _aspect,
      fit: BoxFit.contain,
      semanticsLabel: "Hoppin' Go",
    );
  }
}
