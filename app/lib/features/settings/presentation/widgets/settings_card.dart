import 'package:flutter/material.dart';

import '../../../../core/theme/colors.dart';

/// A rounded white/surface card grouping related settings rows, matching
/// `Setting.png`.
class SettingsCard extends StatelessWidget {
  final List<Widget> children;

  const SettingsCard({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
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
