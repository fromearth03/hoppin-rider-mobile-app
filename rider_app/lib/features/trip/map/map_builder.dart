import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'map_interactor.dart';
import 'map_state.dart';

/// Assembly for the rider map riblet (riblet anatomy, DOCS/05).
///
/// The riblet is ROUTER-FREE (embedded view, 06-CONTEXT lock): it is wired
/// as [MapInteractor] (this provider — 1 Hz seam poll, ladder, camera
/// intents) + the map view (map_view.dart — HopMap host, follow state,
/// recenter chip). No map_router.dart exists by design; every navigation on
/// the trip surface stays with TripNavigationHost.
///
/// Family-keyed by ride id and auto-disposed: leaving the trip screen tears
/// the poll loop down with the provider.
final mapInteractorProvider =
    NotifierProvider.autoDispose.family<MapInteractor, MapState, String>(
  MapInteractor.new,
);

/// Test seam: widget tests override this with a non-null sentinel so HopMap
/// suppresses the MapLibreMap platform view (no tile HTTP under flutter_test).
/// Production leaves it null and HopMap renders the real map.
///
/// Deliberately `dynamic`/Object?: the seam must stay import-free of
/// maplibre_gl in rider app code (the HopMap isolation gate).
final mapTileProvider = Provider<dynamic>((_) => null);
