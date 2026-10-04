import 'package:flutter/material.dart';

import '../../../../core/theme/colors.dart';
import '../../../../shared/widgets/glass.dart';

/// A rounded white/surface card grouping related settings rows, matching
/// `Setting.png`.
class SettingsCard extends StatelessWidget {
  final List<Widget> children;

  const SettingsCard({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      // Glass card: translucent over the screen's ambient backdrop, with the
      // glass hairline and a soft shadow. Same shape and spacing as the frame.
      decoration: GlassCard.decoration(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        // Stretch, not the default centre: a card header is a bare padded
        // Text, and centring it floats the title mid-card — the frames all
        // draw card titles left-aligned.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1)
              Divider(
                height: 1,
                indent: 20,
                endIndent: 20,
                color: theme.brightness == Brightness.light
                    ? AppColors.lightBorder
                    : AppColors.darkBorder,
              ),
          ],
        ],
      ),
    );
  }
}
