import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'trip_interactor.dart';
import 'trip_state.dart';

/// Assembly for the trip riblet (riblet anatomy, DOCS/05).
///
/// The riblet is wired as: [TripInteractor] (this provider — polling brain,
/// phase mapping, actions, nav intents) + `TripNavigationHost`
/// (trip_router.dart — the ONLY place trip navigation happens) + the
/// smart-state view (trip_screen.dart — `TripScreen` keeps its name, path
/// and constructor so the app router's GoRoute line is untouched).
///
/// Family-keyed by ride id and auto-disposed: leaving the trip screen tears
/// the poll loop and every timer down with the provider.
final tripInteractorProvider =
    NotifierProvider.autoDispose.family<TripInteractor, TripState, String>(
  TripInteractor.new,
);
