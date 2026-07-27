import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'booking_builder.dart';
import 'booking_state.dart';

/// ALL navigation for the booking feature lives in this file (riblet rule,
/// DOCS/05). The feature's route line stays in the app router; the ONE
/// navigation the booking flow itself triggers — matched → the trip — is
/// translated here, nowhere else.
///
/// Handover contract (04-01): by the time the matched state flips, the
/// interactor has already written `tripHandoffProvider` (fixed fare,
/// duration, any applied promo) and applied the pending promo code — so the
/// trip screen this navigation lands on finds everything in place.
class BookingNavigationHost extends ConsumerWidget {
  const BookingNavigationHost({required this.child, super.key});

  /// The wrapped view subtree.
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<BookingState>(bookingInteractorProvider, (previous, next) {
      if (next.phase == BookingPhase.matched && next.rideId != null) {
        final rideId = next.rideId!;
        // One-shot: reset BEFORE navigating so nothing can replay the
        // matched state while the route change rebuilds the tree (the same
        // acknowledge-then-navigate order as TripNavigationHost).
        ref.read(bookingInteractorProvider.notifier).reset();
        context.go('/trip/$rideId');
      }
    });
    return child;
  }
}
