import '../../../core/geo.dart';
import '../../../core/money.dart';

/// Empty-or-absent to null. Matches the pattern used by every other
/// repository in this app (`safety_repository.dart`, `receipts_repository.dart`):
/// a type match rather than `as String?`, because the latter throws on a
/// non-string JSON value instead of treating it as absent.
String? _orNull(Object? v) => switch (v) {
      String s when s.trim().isNotEmpty => s,
      _ => null,
    };

/// Where a ride is in its live lifecycle.
///
/// The decisions doc (`docs/SCREEN-DECISIONS.md`, "Trip in progress") names
/// `accepted`/`arriving`/`started` as the driving states where `geo.steps` can
/// be populated. `matching` covers the pre-assignment state where `driver` is
/// null -- a normal state, not an error.
enum LiveTripStatus { matching, accepted, arriving, started, completed, cancelled }

LiveTripStatus _statusFromJson(Object? raw) => switch (raw) {
      'accepted' => LiveTripStatus.accepted,
      'arriving' => LiveTripStatus.arriving,
      'started' => LiveTripStatus.started,
      'completed' => LiveTripStatus.completed,
      // Terminal: dispatch found no driver (auto-cancel) or someone
      // cancelled. The screen must say so, never spin on "matching".
      'cancelled' => LiveTripStatus.cancelled,
      // An unrecognised or missing status degrades to "still matching" rather
      // than throwing -- the screen already has a real rendering for that
      // state, so this is the safest unknown to fall into.
      _ => LiveTripStatus.matching,
    };

/// The assigned driver, rating with count, trips completed, plate, vehicle
/// type and capacity -- per `GET /rides/:id` as described in
/// docs/SCREEN-DECISIONS.md ("Ride details").
///
/// Rating is deliberately NULLABLE. A driver with no ratings yet must never be
/// shown a fabricated 5 stars, so [rating] stays null until the server sends
/// one and callers must branch on [hasRating] rather than defaulting it.
class TripDriver {
  final String name;

  /// Photo URL from the ride detail's driver block; null renders as the
  /// initial-letter avatar rather than a broken image.
  final String? avatarUrl;

  final double? rating;
  final int ratingCount;
  final int tripsCompleted;
  final String? plate;
  final String? vehicleType;
  final int seats;
  final int bags;

  const TripDriver({
    required this.name,
    this.avatarUrl,
    required this.rating,
    required this.ratingCount,
    required this.tripsCompleted,
    required this.plate,
    required this.vehicleType,
    required this.seats,
    required this.bags,
  });

  bool get hasRating => rating != null;

  /// The API COALESCEs seats/bags to 0 when unconfigured, mirroring
  /// `VehicleCategory.hasCapacity`. Rendering "0 Seats 0 Bags" would state
  /// something false, so the row is dropped instead.
  bool get hasCapacity => seats > 0 || bags > 0;

  /// A row with no name is not a driver the app can show -- there would be
  /// nothing to put on the card. Every other field degrades independently.
  static TripDriver? tryFromJson(Map<String, dynamic> json) {
    final name = _orNull(json['name']);
    if (name == null) return null;

    return TripDriver(
      name: name,
      avatarUrl: _orNull(json['avatar_url']),
      rating: (json['rating'] as num?)?.toDouble(),
      ratingCount: (json['rating_count'] as num?)?.toInt() ?? 0,
      tripsCompleted: (json['trips_completed'] as num?)?.toInt() ?? 0,
      plate: _orNull(json['plate']),
      vehicleType: _orNull(json['vehicle_type']),
      seats: (json['seats'] as num?)?.toInt() ?? 0,
      bags: (json['bags'] as num?)?.toInt() ?? 0,
    );
  }
}

/// One turn-by-turn instruction from `geo.steps`.
///
/// `maneuver` is the raw OSRM token (`turn-left`, `arrive`, `roundabout`) kept
/// for the directional icon; `instruction` is the composed prose the banner
/// actually displays, per the decisions doc's instruction to "use the prose,
/// keep maneuver for the icon".
class TripStep {
  final String maneuver;
  final String instruction;

  const TripStep({required this.maneuver, required this.instruction});

  /// A step with no instruction text has nothing to show on the banner, so it
  /// is dropped rather than rendered blank.
  static TripStep? tryFromJson(Map<String, dynamic> json) {
    final instruction = _orNull(json['instruction']);
    if (instruction == null) return null;
    return TripStep(
      maneuver: _orNull(json['maneuver']) ?? '',
      instruction: instruction,
    );
  }
}

/// A waypoint pin on the live-trip map: pickup (A), a mid-point stop (B, …),
/// or the destination.
class TripWaypoint {
  final String label;
  final String? distanceLabel;
  final LatLng? position;

  const TripWaypoint({
    required this.label,
    required this.distanceLabel,
    required this.position,
  });
}

/// The live state of one ride, as `GET /rides/:id` is documented to return in
/// docs/SCREEN-DECISIONS.md: driver identity, rating with count, trips
/// completed, plate, vehicle type and capacity, a fare estimate (base +
/// surge), and the cancellation policy, all in one call.
///
/// **No repository for this endpoint exists yet** (searched
/// `features/booking/data/` and the rest of `lib/`; only `/rides/estimate`,
/// `/rides/request` and `/rides/:id/receipt` are wired). See [LiveTripSource]
/// below for how this screen is driven until one lands.
class LiveTripInfo {
  final String rideId;
  final LiveTripStatus status;

  /// Null while matching -- a normal state, not an error. Never fabricated.
  final TripDriver? driver;

  final Pence? baseFarePence;
  final double? surgeMultiplier;
  final Pence? surgePence;
  final Pence? totalPence;
  final String currency;

  final String? cancellationPolicy;

  final List<TripWaypoint> waypoints;
  final List<LatLng>? route;

  /// Turn-by-turn instructions. `null` OUTSIDE the driving states
  /// (`accepted`/`arriving`/`started`), and also `null` when OSRM is slow or
  /// unavailable -- meaning "no instructions available". An empty list is a
  /// distinct, meaningful state: "no turns remain". The two must never be
  /// treated the same; a null degrades the screen to a map with no banner
  /// rather than an empty, broken-looking one.
  final List<TripStep>? steps;

  final String? destinationLabel;

  /// The note the rider left for their driver at booking, echoed back so they
  /// can see it was actually carried onto the trip. Null when they left it
  /// blank.
  final String? riderNote;

  const LiveTripInfo({
    required this.rideId,
    required this.status,
    required this.driver,
    required this.baseFarePence,
    required this.surgeMultiplier,
    required this.surgePence,
    required this.totalPence,
    required this.currency,
    required this.cancellationPolicy,
    required this.waypoints,
    required this.route,
    required this.steps,
    required this.destinationLabel,
    this.riderNote,
  });

  /// The honest "nothing to show yet" state: matching, no driver, nothing
  /// priced. Used both as the placeholder default and as a safe fallback.
  factory LiveTripInfo.awaiting(String rideId) => LiveTripInfo(
        rideId: rideId,
        status: LiveTripStatus.matching,
        driver: null,
        baseFarePence: null,
        surgeMultiplier: null,
        surgePence: null,
        totalPence: null,
        currency: 'GBP',
        cancellationPolicy: null,
        waypoints: const [],
        route: null,
        steps: null,
        destinationLabel: null,
      );

  static List<TripStep>? _parseSteps(Object? raw) {
    if (raw is! List) return null;
    return raw
        .whereType<Map>()
        .map((m) => TripStep.tryFromJson(m.cast<String, dynamic>()))
        .whereType<TripStep>()
        .toList(growable: false);
  }

  static List<LatLng>? _parseRoute(Object? raw) {
    if (raw is! List) return null;
    final points = <LatLng>[];
    for (final p in raw) {
      if (p is! Map) return null;
      final lat = p['lat'], lng = p['lng'];
      if (lat is! num || lng is! num) return null;
      points.add(LatLng(lat.toDouble(), lng.toDouble()));
    }
    return points;
  }

  static List<TripWaypoint> _parseWaypoints(Object? raw) {
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((m) {
      final lat = m['lat'], lng = m['lng'];
      return TripWaypoint(
        label: _orNull(m['label']) ?? '',
        distanceLabel: _orNull(m['distance_label']),
        position:
            (lat is num && lng is num) ? LatLng(lat.toDouble(), lng.toDouble()) : null,
      );
    }).toList(growable: false);
  }

  factory LiveTripInfo.fromJson(Map<String, dynamic> json) {
    final driverJson = json['driver'];
    return LiveTripInfo(
      rideId: _orNull(json['id']) ?? '',
      status: _statusFromJson(json['status']),
      driver: driverJson is Map
          ? TripDriver.tryFromJson(driverJson.cast<String, dynamic>())
          : null,
      baseFarePence: Pence.fromJson(json['base_fare_pence']),
      surgeMultiplier: (json['surge_multiplier'] as num?)?.toDouble(),
      surgePence: Pence.fromJson(json['surge_pence']),
      totalPence: Pence.fromJson(json['total_pence']),
      currency: _orNull(json['currency']) ?? 'GBP',
      cancellationPolicy: _orNull(json['cancellation_policy']),
      waypoints: _parseWaypoints(json['waypoints']),
      route: _parseRoute(json['route']),
      steps: _parseSteps(json['steps']),
      destinationLabel: _orNull(json['destination_label']),
      riderNote: _orNull(json['rider_note']),
    );
  }
}

/// Feeds [LiveTripScreen] with the live state of one ride.
///
/// **This is an explicit, honestly-named placeholder, not a repository.**
/// docs/SCREEN-DECISIONS.md documents `GET /rides/:id` as the call that would
/// serve everything this screen needs in one shot, but no such method exists
/// anywhere in `lib/` today -- `booking_repository.dart` only has `request()`,
/// and the only per-ride reads that exist are `/rides/:id/receipt`
/// (post-trip) and `/rides/:id/stops` (multi-stop waiting, not driver info).
///
/// Inventing an endpoint call here would silently 404 or, worse, be mistaken
/// for a real integration later. Instead this returns the honest "still
/// finding your driver" state ([LiveTripInfo.awaiting]) so the screen has
/// something real to render by default. Swapping in a real repository is a
/// one-class change: replace [watch] with a call to the real endpoint and
/// nothing in [LiveTripScreen] needs to change, since it already renders
/// every state [LiveTripInfo] can describe.
class LiveTripSource {
  const LiveTripSource();

  /// A single honest snapshot: matching, no driver, nothing priced.
  ///
  /// Real transport for this screen is meant to be three-part (FCM for
  /// status, SSE for driver position, a 1Hz poll as fallback -- spec §5.1),
  /// which is exactly why this is a `Stream`: a future repository can swap in
  /// live pushes without changing this method's signature or any caller.
  Stream<LiveTripInfo> watch(String rideId) async* {
    yield LiveTripInfo.awaiting(rideId);
  }
}

const liveTripSource = LiveTripSource();
