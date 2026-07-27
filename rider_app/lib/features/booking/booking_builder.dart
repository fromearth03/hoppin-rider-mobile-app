import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'booking_interactor.dart';
import 'booking_router.dart';
import 'booking_state.dart';
import 'booking_view.dart';

/// Assembly for the booking riblet (riblet anatomy, DOCS/05).
///
/// The riblet is wired as: [BookingInteractor] (this provider — the proven
/// estimate/request/id-diff-poll brain plus promo staging and the staged
/// matching copy) + `BookingNavigationHost` (booking_router.dart — the ONLY
/// place booking navigation happens: matched → reset + `/trip/:id`) + the
/// booking view (booking_view.dart — fare-estimate money moment and the
/// RadarPulse matching beat).
///
/// Root-scoped (not autoDispose): the staged dropoff from home's "Go again"
/// shortcuts must survive the navigation into /book.
final bookingInteractorProvider =
    NotifierProvider<BookingInteractor, BookingState>(BookingInteractor.new);

/// The riblet's public entry — what the app router mounts at /book: the
/// navigation host (the feature's only navigation site) wrapping the view.
class BookingFlow extends StatelessWidget {
  const BookingFlow({super.key});

  @override
  Widget build(BuildContext context) =>
      const BookingNavigationHost(child: BookingView());
}
