import 'package:flutter/material.dart';

/// The plain back-arrow + centred title header shared by Settings and Help &
/// Support, matching `Setting.png`. Unlike the auth screens there is no
/// gradient here -- the design draws a flat background with a simple row.
class SettingsHeader extends StatelessWidget implements PreferredSizeWidget {
  final String title;

  const SettingsHeader({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return AppBar(
      centerTitle: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
        onPressed: () => Navigator.of(context).maybePop(),
        icon: const Icon(Icons.arrow_back),
      ),
      title: Text(title, style: Theme.of(context).textTheme.titleMedium),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
