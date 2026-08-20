import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'trip_builder.dart';
import 'trip_state.dart';

/// ALL navigation for the trip family lives in this file (riblet rule,
/// DOCS/05). The trip riblet's own route line stays in the app router
/// (04-04 owns lib/router.dart this wave); everything the trip feature
/// itself triggers — receipt, chat, safety, home, book-again — leaves the
/// interactor as a one-shot [TripNavIntent] and is translated to a
/// `context.go` here, nowhere else. The trip screen AND the receipt screen
/// (04-05) each mount a host over the same family instance.
class TripNavigationHost extends ConsumerWidget {
  const TripNavigationHost({
    required this.rideId,
    required this.child,
    super.key,
  });

  /// Which trip riblet instance this host listens to.
  final String rideId;

  /// The wrapped view subtree.
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(tripInteractorProvider(rideId), (previous, next) {
      // Cancellation is terminal. Leave the live-trip route as soon as the
      // server confirms it, so a rider is never trapped in the old arrival
      // card waiting for a manual back action.
      if (next.phase == TripPhase.cancelled &&
          previous?.phase != TripPhase.cancelled) {
        context.go('/book');
        return;
      }
      // Read the CURRENT state, not the notification snapshot: with two
      // hosts alive at once (receipt pushed over the trip screen), the
      // first listener consumes the intent and the second must see null —
      // one intent, one navigation.
      final intent = ref.read(tripInteractorProvider(rideId)).navIntent;
      if (intent == null) return;
      // One-shot: acknowledge BEFORE navigating so nothing can replay the
      // intent while the route change rebuilds the tree.
      ref.read(tripInteractorProvider(rideId).notifier).consumeNavIntent();
      switch (intent) {
        // PUSH the four leaves, `go` the two destinations. The distinction is
        // not stylistic — it decides whether "back" works.
        //
        // `go` REPLACES the route, so `canPop()` on the far side is false and
        // the leaf's back button falls through to a hardcoded fallback: the
        // rider taps back from the chat and lands on the Book tab instead of
        // returning to the trip they were watching. Worse, a screen relying on
        // the stock AppBar's auto-arrow gets NO arrow at all, because that arrow
        // is conditional on the very stack `go` just destroyed. That is how the
        // SOS screen ended up with no exit.
        //
        // These four are leaves the rider is expected to come BACK from, so they
        // are pushed and `pop()` returns them to the trip.
        case TripNavIntent.receipt:
          unawaited(context.push('/trip/$rideId/receipt'));
        case TripNavIntent.chat:
          unawaited(context.push('/trip/$rideId/chat'));
        case TripNavIntent.call:
          unawaited(context.push('/trip/$rideId/call'));
        case TripNavIntent.safety:
          unawaited(context.push('/safety?rideId=$rideId'));

        // These two are DESTINATIONS, not leaves: the trip is over (or
        // abandoned) and the rider is being returned to the app's home tab.
        // `go` is right here — there is nothing to come back to, and pushing
        // would bury the shell's bottom nav under a tab route.
        case TripNavIntent.home:
          // The old '/' HomeScreen hub is superseded by the Book tab as the
          // landing surface under the 08-03 shell — re-point home here.
          context.go('/book');
        case TripNavIntent.book:
          context.go('/book');

        // Minimise: the trip screen disappears but the trip stays live.
        // `go` replaces the route so the trip screen is removed from the
        // stack; the live-trip banner on /book gives the rider a way back.
        case TripNavIntent.minimize:
          context.go('/book');
      }
    });
    return child;
  }
}
