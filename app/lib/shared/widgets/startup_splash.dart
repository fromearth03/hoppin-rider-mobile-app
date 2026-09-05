import 'package:flutter/material.dart';

import '../../core/theme/colors.dart';
import 'hoppin_logo.dart';

/// Shown while the app works out whether the rider is still signed in.
///
/// The router starts at `/login` and `redirectFor` deliberately declines to
/// redirect while the status is unknown — so without this the login FORM is
/// what a returning rider stares at for the length of a session refresh and a
/// profile fetch, before being redirected away from it. Two seconds of "please
/// sign in" aimed at someone who never signed out.
class StartupSplash extends StatelessWidget {
  const StartupSplash({super.key});

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Colors.white,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            HoppinLogo(height: 42),
            SizedBox(height: 28),
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                valueColor: AlwaysStoppedAnimation(AppColors.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
