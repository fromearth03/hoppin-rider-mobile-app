import 'package:flutter/material.dart';

import '../../../../core/theme/colors.dart';

/// The curved indigo header both auth screens share.
///
/// The curve is a single bottom-right radius, matching the design. The header
/// keeps its brand colour in both themes — the indigo IS the brand, and
/// inverting it in dark mode would make the app unrecognisable.
class AuthScaffold extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  final bool showBack;

  const AuthScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.showBack = true,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 16,
              left: 24,
              right: 24,
              bottom: 40,
            ),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomLeft,
                end: Alignment.topRight,
                colors: [AppColors.primaryDark, AppColors.primary],
              ),
              borderRadius: BorderRadius.only(
                bottomRight: Radius.circular(48),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showBack)
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.15),
                    ),
                  ),
                const SizedBox(height: 48),
                Text(title,
                    style: const TextStyle(
                        fontSize: 38,
                        fontWeight: FontWeight.w400,
                        color: Colors.white)),
                const SizedBox(height: 8),
                Text(subtitle,
                    style: TextStyle(
                        fontSize: 15,
                        color: Colors.white.withValues(alpha: 0.85))),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}
