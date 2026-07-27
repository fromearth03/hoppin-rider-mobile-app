import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'scheduled_interactor.dart';
import 'scheduled_state.dart';

/// Assembly for the scheduled riblet (riblet anatomy, DOCS/05).
///
/// The riblet is wired as: [ScheduledInteractor] (this provider — the
/// list/create/detail brain over the existing `/scheduled-rides` repo methods)
/// + the [ScheduledScreen] view (dumb list) + the [SchedulePicker] entry. The
/// `/scheduled` route that hosts the screen is registered by the convergence
/// lane (10-05, router.dart) — this lane only builds and exports the surface.
///
/// autoDispose is deliberately NOT used: the scheduled surface is entered from
/// the Book flow and should keep its loaded set while the rider dips into the
/// picker and back.
final scheduledInteractorProvider =
    NotifierProvider<ScheduledInteractor, ScheduledState>(
  ScheduledInteractor.new,
);
