import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/colors.dart';
import '../../../../shared/nav/app_router.dart';
import '../../../../shared/widgets/hoppin_logo.dart';

/// The curved indigo header both auth screens share.
///
/// The curve is a single bottom-right radius, matching the design. The header
/// keeps its brand colour in both themes — the indigo IS the brand, and
/// inverting it in dark mode would make the app unrecognisable.
///
/// The "Hoppin' Go" lockup pins to the bottom of the screen, as in the design.
/// It is inside the scroll view rather than fixed, so a small screen with the
/// keyboard up scrolls it away instead of stealing height from the fields.
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
                    // `go` navigation leaves nothing to pop — the arrow was
                    // dead on Forgot/Reset. Fall back to Login.
                    onPressed: () {
                      final nav = Navigator.of(context);
                      if (nav.canPop()) {
                        nav.pop();
                      } else {
                        context.go(AppRoutes.login);
                      }
                    },
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
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
                  child: ConstrainedBox(
                    // Fills the viewport when the form is short, so the logo
                    // reaches the foot of the screen rather than floating
                    // directly under the last field; taller forms simply push
                    // past it and scroll.
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - 56,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      // Pushes the logo to the foot of the available space.
                      // `Spacer` would throw here: this Column is inside a
                      // scroll view, so its height is unbounded.
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        child,
                        const Padding(
                          padding: EdgeInsets.only(top: 32),
                          child: Center(child: HoppinLogo()),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
