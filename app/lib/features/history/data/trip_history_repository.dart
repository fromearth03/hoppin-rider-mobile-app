import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/money.dart';
import '../../../core/result.dart';

/// Empty-or-absent to null. Matches on the type rather than casting: `as
/// String?` throws on a non-string JSON value, which would make a hardening
/// helper the thing that crashes.
String? _orNull(Object? v) => switch (v) {
      String s when s.trim().isNotEmpty => s,
      _ => null,
    };

/// Never throws: an unexpected type parses as null rather than taking the
/// whole page of history down with it.
DateTime? _time(Object? raw) => switch (raw) {
      String s when s.isNotEmpty => DateTime.tryParse(s)?.toUtc(),
      _ => null,
    };

/// Rows the server sent that are not JSON objects at all.
///
/// `List.cast<Map<String, dynamic>>()` is LAZY in Dart: it validates nothing
/// at the call and throws a TypeError later, when `map` pulls an element. That
/// throw would escape a method whose signature promises a `Result`, and
/// `ApiClient` catches only `DioException`.
Iterable<Map<String, dynamic>> _objects(Object? raw) =>
    (raw is List ? raw : const []).whereType<Map<String, dynamic>>();

/// The vehicle the ride was quoted for.
class TripVehicleCategory {
  final String id;
  final String name;
  final int seats;
  final int bags;

  const TripVehicleCategory({
    required this.id,
    required this.name,
    required this.seats,
    required this.bags,
  });

  factory TripVehicleCategory.fromJson(Map<String, dynamic> json) =>
      TripVehicleCategory(
        id: _orNull(json['id']) ?? '',
        name: _orNull(json['name']) ?? '',
        seats: (json['seats'] as num?)?.toInt() ?? 0,
        bags: (json['bags'] as num?)?.toInt() ?? 0,
      );
}

/// The driver who took the trip.
class TripDriver {
  final String id;
  final String fullName;
  final String? avatarUrl;

  /// Null when the driver has never been rated. The backend is explicit that
  /// this stays null rather than becoming 0 — "no rating yet" and "rated zero"
  /// are different claims and only one of them is true.
  final double? rating;
  final int ratingCount;

  const TripDriver({
    required this.id,
    required this.fullName,
    required this.avatarUrl,
    required this.rating,
    required this.ratingCount,
  });

  factory TripDriver.fromJson(Map<String, dynamic> json) => TripDriver(
        id: _orNull(json['id']) ?? '',
        fullName: _orNull(json['full_name']) ?? '',
        avatarUrl: _orNull(json['avatar_url']),
        rating: (json['rating'] as num?)?.toDouble(),
        ratingCount: (json['rating_count'] as num?)?.toInt() ?? 0,
      );
}

/// One row of ride history, mirroring `tripHistoryItem` in
/// `Go_ride_service/internal/handler/rider_trips_read.go`.
///
/// Every nullable field on the Go struct is nullable here. The handler's own
/// note is the rule this model follows: "nullables stay null — never a fake 0".
class TripHistoryItem {
  final String id;

  /// Human-readable reference, e.g. "R-1042". Null on older rows.
  final String? ref;
  final String status;
  final String rideCategory;
  final TripVehicleCategory? vehicleCategory;
  final String? pickupLabel;
  final String? dropoffLabel;

  /// `requested_at` on the wire — the ride's `created_at`, and the field the
  /// server's cursor pages on. Never null; it is what the list groups by.
  final DateTime requestedAt;
  final DateTime? pickupTime;
  final DateTime? dropoffTime;

  /// Null until the ride is actually charged. The server COALESCEs the charged
  /// transaction to the quoted price, so a null here means neither exists.
  final Pence? totalPence;
  final String currency;

  /// Null until a driver was assigned — which, with dispatch not yet live,
  /// is every ride that was cancelled before assignment.
  final TripDriver? driver;

  /// The rating this rider left, 1-5. Null when they never rated the trip.
  final int? myRating;

  /// "rider", "driver" or "system" on a cancelled ride; null otherwise.
  final String? cancelledBy;

  const TripHistoryItem({
    required this.id,
    required this.ref,
    required this.status,
    required this.rideCategory,
    required this.vehicleCategory,
    required this.pickupLabel,
    required this.dropoffLabel,
    required this.requestedAt,
    required this.pickupTime,
    required this.dropoffTime,
    required this.totalPence,
    required this.currency,
    required this.driver,
    required this.myRating,
    required this.cancelledBy,
  });

  bool get isCancelled => status == 'cancelled';

  /// The moment to show and group by: when the ride actually ran if it ran,
  /// otherwise when it was asked for. A cancelled ride has no pickup time.
  DateTime get displayTime => pickupTime ?? requestedAt;

  /// Null for a row that cannot be rendered or opened.
  ///
  /// The id is the whole reason a card is tappable — without it, tapping opens
  /// trip details for nothing. A row that cannot be opened is better absent
  /// than present-and-dead.
  static TripHistoryItem? tryFromJson(Map<String, dynamic> json) {
    final id = _orNull(json['id']);
    if (id == null) return null;

    final vehicle = json['vehicle_category'];
    final driver = json['driver'];

    return TripHistoryItem(
      id: id,
      ref: _orNull(json['ref']),
      status: _orNull(json['status']) ?? '',
      rideCategory: _orNull(json['ride_category']) ?? '',
      vehicleCategory: vehicle is Map<String, dynamic>
          ? TripVehicleCategory.fromJson(vehicle)
          : null,
      pickupLabel: _orNull(json['pickup_label']),
      dropoffLabel: _orNull(json['dropoff_label']),
      // Never null on the wire; an unparseable value falls back to the epoch
      // rather than dropping a row the rider genuinely took.
      requestedAt: _time(json['requested_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      pickupTime: _time(json['pickup_time']),
      dropoffTime: _time(json['dropoff_time']),
      totalPence: Pence.fromJson(json['total_pence']),
      currency: _orNull(json['currency']) ?? 'GBP',
      driver:
          driver is Map<String, dynamic> ? TripDriver.fromJson(driver) : null,
      myRating: (json['my_rating'] as num?)?.toInt(),
      cancelledBy: _orNull(json['cancelled_by']),
    );
  }
}

/// One cursor-paged page of history.
class TripHistoryPage {
  final List<TripHistoryItem> trips;

  /// RFC3339 timestamp to pass back as `cursor` for the next page.
  final String? nextCursor;
  final bool hasMore;

  const TripHistoryPage({
    required this.trips,
    required this.nextCursor,
    required this.hasMore,
  });
}

/// Ride history, read from `GET /api/v1/rides`.
///
/// Contract read from `Go_ride_service/internal/handler/rider_trips_read.go`
/// (GetMyTrips), not from the handover docs. The handler supports `limit`
/// (default 20, capped server-side at 50), `cursor` (RFC3339, created_at
/// descending), `status` (only "completed" or "cancelled"; anything else means
/// all trips) and a `from`/`to` timestamp range. Because the range filter is
/// real, a month filter is a SERVER-side query here rather than client-side
/// filtering over fetched pages.
class TripHistoryRepository {
  final ApiClient _api;
  const TripHistoryRepository(this._api);

  /// The server caps limit at 50; sending more just wastes the round trip.
  static const _maxLimit = 50;

  Future<Result<TripHistoryPage>> myTrips({
    int limit = 20,
    String? cursor,
    String? status,
    DateTime? from,
    DateTime? to,
  }) async {
    final result = await _api.get<dynamic>('/rides', query: {
      'limit': limit > _maxLimit ? _maxLimit : limit,
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
      // The handler ignores anything that is not one of these two, but sending
      // a value it will discard makes the request lie about its intent.
      if (status == 'completed' || status == 'cancelled') 'status': status,
      if (from != null) 'from': from.toUtc().toIso8601String(),
      if (to != null) 'to': to.toUtc().toIso8601String(),
    });

    return switch (result) {
      Ok(:final value) => Ok(_page(value)),
      Err(:final error) => Err(error),
    };
  }

  TripHistoryPage _page(Object? body) {
    final map = body is Map ? body : const {};
    return TripHistoryPage(
      trips: _objects(map['trips'])
          .map(TripHistoryItem.tryFromJson)
          .whereType<TripHistoryItem>()
          .toList(growable: false),
      nextCursor: _orNull(map['next_cursor']),
      // A truncated envelope must not make the list page forever.
      hasMore: map['has_more'] == true,
    );
  }
}

final tripHistoryRepositoryProvider = Provider<TripHistoryRepository>(
    (ref) => TripHistoryRepository(ref.watch(apiClientProvider)));
