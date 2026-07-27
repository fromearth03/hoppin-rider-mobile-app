import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

/// The router's `errorBuilder` target — what a rider sees when navigation
/// lands on a path the route table does not contain.
///
/// **Why this screen exists.** Until Phase 12 the rider app had NO
/// `errorBuilder`, which means go_router fell back to its own default: a bare
/// grey page reading "Page not found" above a raw exception dump, in a shipped
/// consumer app. That default was not hypothetical — seven live navigation
/// targets resolved to nothing (the four Profile-hub rows, the two legal links,
/// and the home screen's `/wallet` quick-link), so this was, in practice, a
/// reachable screen that we had simply never designed.
///
/// Phase 12 mounts all seven of those routes, so nothing in `lib/` should reach
/// this screen any more. It stays anyway, for two reasons:
///
///  1. A deep link or a push payload can carry ANY path — those come from
///     outside the binary, and no amount of internal route hygiene constrains
///     them. This is the honest landing for one that does not resolve.
///  2. The next dead `context.go` someone writes lands here instead of on a
///     stack trace. A designed dead end that offers a way out is not a lie; an
///     exception dump is just a broken app.
///
/// It deliberately does NOT show the failed path or the exception. A rider can
/// do nothing with either, and printing internals at a user is the same
/// category of mistake as the default page we are replacing.
class RouteNotFoundScreen extends StatelessWidget {
  /// Creates the not-found screen.
  const RouteNotFoundScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    return Scaffold(
      backgroundColor: hoppin.colors.canvas,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(hoppin.spacing.gutter),
            child: HopEmptyState(
              headline: 'We could not open that page',
              supporting:
                  "That link does not point anywhere in the app. Nothing has "
                  'gone wrong with your account or any trip — you can head back '
                  'and carry on.',
              actionLabel: 'Back to booking',
              // `go`, not `pop`: the failed navigation may BE the first route
              // (a cold-start deep link), in which case there is nothing
              // beneath to pop to and a pop would strand the rider on this
              // screen — a dead end inside the dead-end screen.
              onAction: () => context.go('/book'),
            ),
          ),
        ),
      ),
    );
  }
}
