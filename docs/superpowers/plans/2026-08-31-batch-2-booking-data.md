# Batch 2 — Booking data layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every model, repository and piece of fare logic the booking screens need, built and tested against the real API shapes — so that when the Google Maps key arrives, only the map widgets remain.

**Architecture:** Feature-first under `lib/features/booking/`. Models mirror the Go structs exactly. Repositories return `Result<T>` through the existing `ApiClient`, which already attaches the auth and device headers.

**Tech Stack:** Flutter 3.44.4 · Dart 3.12.2 · flutter_riverpod 2.6.1 · dio 5.4.x · mocktail 1.0.5

**Spec:** `docs/superpowers/specs/2026-08-30-rider-app-milestone1-design.md`
**Screen decisions:** `docs/SCREEN-DECISIONS.md`

## Global Constraints

- **The backend is the source of truth.** A field the API does not return is not modelled; a row with no backing field is not rendered.
- **Models mirror Go structs exactly.** If the struct has no field, the Dart class has no field.
- **Money is never a `double`.** Use `Pence` (`lib/core/money.dart`). A fare that is not yet known stays `null` — "free" and "not yet charged" must not both render as £0.00.
- **Server-owned copy is rendered verbatim** via `RiderErrorCopy.messageFor`.
- **No fakeness.** No stubs, no placeholder values, no TODO screens.
- **TDD throughout**, tests before implementation.
- Run tests with `flutter test`; live tests with `--run-skipped --dart-define-from-file=../config/dev.json`.

## Why this batch stops short of the screens

`google_maps_flutter` needs an API key restricted per platform, which the product owner has not yet issued. Rather than block, this batch builds everything the booking screens consume. The screens themselves — which are mostly map, sheet and list widgets over these models — follow in batch 3 once the key exists.

---

### Task 1: Vehicle category model and repository

**Files:**
- Create: `app/lib/features/booking/data/vehicle_repository.dart`
- Test: `app/test/features/booking/data/vehicle_repository_test.dart`

**Interfaces:**
- Consumes: `ApiClient`, `apiClientProvider`, `Result`, `ApiException`.
- Produces: `VehicleCategory` (`id`, `name`, `seats`, `bags`, `priceMultiplier`) with `fromJson`; `VehicleRepository.list()` returning `Future<Result<List<VehicleCategory>>>`; `vehicleRepositoryProvider`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/api/api_client.dart';
import 'package:hoppin_rider/core/api/api_exception.dart';
import 'package:hoppin_rider/core/result.dart';
import 'package:hoppin_rider/features/booking/data/vehicle_repository.dart';
import 'package:mocktail/mocktail.dart';

class _MockApi extends Mock implements ApiClient {}

void main() {
  late _MockApi api;
  late VehicleRepository repo;

  setUp(() {
    api = _MockApi();
    repo = VehicleRepository(api);
  });

  group('VehicleCategory.fromJson', () {
    test('reads exactly the five fields the API sends', () {
      final v = VehicleCategory.fromJson(const {
        'id': 'abc-123',
        'name': 'Standard',
        'seats': 4,
        'bags': 2,
        'price_multiplier': 1.0,
      });

      expect(v.id, 'abc-123');
      expect(v.name, 'Standard');
      expect(v.seats, 4);
      expect(v.bags, 2);
      expect(v.priceMultiplier, 1.0);
    });

    test('a multiplier sent as an int still reads as a double', () {
      // JSON has one number type; 1 and 1.0 both arrive for a x1 category.
      final v = VehicleCategory.fromJson(const {
        'id': 'a', 'name': 'Standard', 'seats': 4, 'bags': 2,
        'price_multiplier': 1,
      });
      expect(v.priceMultiplier, 1.0);
    });

    test('zero seats or bags means the row is not rendered, not "0 Seats"', () {
      // The API COALESCEs both to 0 when a category has neither configured.
      final v = VehicleCategory.fromJson(const {
        'id': 'a', 'name': 'Odd', 'seats': 0, 'bags': 0,
        'price_multiplier': 1.0,
      });
      expect(v.hasCapacity, isFalse);
    });
  });

  group('list', () {
    test('preserves the order the API returned', () async {
      // The API orders by price_multiplier then name — cheapest first. The
      // client must not re-sort; doing so would reorder the picker.
      when(() => api.get<Map<String, dynamic>>(any()))
          .thenAnswer((_) async => const Ok({
                'vehicle_types': [
                  {'id': 'c', 'name': 'MiniCar', 'seats': 4, 'bags': 2,
                   'price_multiplier': 0.9},
                  {'id': 'a', 'name': 'Standard', 'seats': 4, 'bags': 2,
                   'price_multiplier': 1.0},
                  {'id': 'b', 'name': 'Estate', 'seats': 5, 'bags': 4,
                   'price_multiplier': 1.3},
                ],
              }));

      final result = await repo.list();

      final names =
          (result as Ok<List<VehicleCategory>>).value.map((v) => v.name);
      expect(names, ['MiniCar', 'Standard', 'Estate']);
    });

    test('an empty catalogue is a success, not an error', () async {
      when(() => api.get<Map<String, dynamic>>(any()))
          .thenAnswer((_) async => const Ok({'vehicle_types': []}));

      final result = await repo.list();

      expect(result, isA<Ok<List<VehicleCategory>>>());
      expect((result as Ok<List<VehicleCategory>>).value, isEmpty);
    });

    test('passes the error through untouched', () async {
      when(() => api.get<Map<String, dynamic>>(any())).thenAnswer(
          (_) async => Err(ApiException('INTERNAL', 'boom', 500)));

      final result = await repo.list();

      expect((result as Err).error.code, 'INTERNAL');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/features/booking/data/vehicle_repository_test.dart`
Expected: FAIL — URI does not exist.

- [ ] **Step 3: Write the implementation**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/result.dart';

/// One bookable vehicle class, mirroring `GET /api/v1/vehicle-types`.
///
/// Five fields and no more (`app_catalog_repo.go:225-236`). There is no image,
/// icon or description — artwork is a local asset keyed by [name], with a
/// generic fallback, because categories are admin-editable and a new one can
/// appear without an app release.
class VehicleCategory {
  final String id;
  final String name;
  final int seats;
  final int bags;

  /// Relative cost, used to convey price before an estimate resolves.
  final double priceMultiplier;

  const VehicleCategory({
    required this.id,
    required this.name,
    required this.seats,
    required this.bags,
    required this.priceMultiplier,
  });

  /// The API COALESCEs seats and bags to 0 when unconfigured. Rendering
  /// "0 Seats 0 Bags" would state something false, so the row is dropped.
  bool get hasCapacity => seats > 0 || bags > 0;

  factory VehicleCategory.fromJson(Map<String, dynamic> json) =>
      VehicleCategory(
        id: json['id'] as String,
        name: (json['name'] as String?) ?? '',
        seats: (json['seats'] as num?)?.toInt() ?? 0,
        bags: (json['bags'] as num?)?.toInt() ?? 0,
        priceMultiplier:
            (json['price_multiplier'] as num?)?.toDouble() ?? 1.0,
      );
}

class VehicleRepository {
  final ApiClient _api;
  const VehicleRepository(this._api);

  /// Active categories, cheapest first.
  ///
  /// The server orders by `price_multiplier, name` and filters on `is_active`.
  /// Render in the order received — re-sorting client-side would reorder the
  /// picker away from what the operator configured.
  Future<Result<List<VehicleCategory>>> list() async {
    final result = await _api.get<Map<String, dynamic>>('/vehicle-types');
    return switch (result) {
      Ok(:final value) => Ok(((value['vehicle_types'] as List?) ?? [])
          .cast<Map<String, dynamic>>()
          .map(VehicleCategory.fromJson)
          .toList(growable: false)),
      Err(:final error) => Err(error),
    };
  }
}

final vehicleRepositoryProvider = Provider<VehicleRepository>(
    (ref) => VehicleRepository(ref.watch(apiClientProvider)));
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/features/booking/data/vehicle_repository_test.dart`
Expected: PASS (6 tests)

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/booking/data/vehicle_repository.dart app/test/features/booking/data/vehicle_repository_test.dart
git commit -m "feat: vehicle category model and repository

Five fields, mirroring the API exactly. Renders in the order received
because the server sorts cheapest-first and re-sorting would reorder the
picker away from what the operator configured.

A category with no seats or bags configured reports hasCapacity false
rather than rendering '0 Seats 0 Bags', which would state something
untrue."
```

---

### Task 2: Place search for route entry

**Files:**
- Create: `app/lib/features/booking/data/places_repository.dart`
- Test: `app/test/features/booking/data/places_repository_test.dart`

**Interfaces:**
- Consumes: `ApiClient`, `Result`.
- Produces: `PlaceSuggestion` (`label`, `lat`, `lng`, `postcode`, `source`) with `fromJson` and `isSaved`; `PlacesRepository.search(String query, {double? lat, double? lng})`; `PlacesRepository.reverse(double lat, double lng)`; `placesRepositoryProvider`; `const kMinQueryLength = 2`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/api/api_client.dart';
import 'package:hoppin_rider/core/result.dart';
import 'package:hoppin_rider/features/booking/data/places_repository.dart';
import 'package:mocktail/mocktail.dart';

class _MockApi extends Mock implements ApiClient {}

void main() {
  late _MockApi api;
  late PlacesRepository repo;

  setUp(() {
    api = _MockApi();
    repo = PlacesRepository(api);
  });

  test('a saved place is distinguishable from a map hit', () {
    final saved = PlaceSuggestion.fromJson(const {
      'label': 'Home', 'lat': 52.58, 'lng': -2.12, 'source': 'saved',
    });
    final map = PlaceSuggestion.fromJson(const {
      'label': 'Molineux Stadium', 'lat': 52.59, 'lng': -2.13,
      'postcode': 'WV1 4QR', 'source': 'map',
    });

    expect(saved.isSaved, isTrue);
    expect(map.isSaved, isFalse);
    expect(map.postcode, 'WV1 4QR');
    expect(saved.postcode, isNull, reason: 'omitted when empty');
  });

  test('does not call the API below the minimum query length', () async {
    // The server returns [] under 2 characters. Calling anyway would burn a
    // request per keystroke for a guaranteed-empty answer.
    final result = await repo.search('m');

    expect((result as Ok<List<PlaceSuggestion>>).value, isEmpty);
    verifyNever(() => api.get<Map<String, dynamic>>(any(),
        query: any(named: 'query')));
  });

  test('sends position as a bias when it is known', () async {
    when(() => api.get<Map<String, dynamic>>(any(),
            query: any(named: 'query')))
        .thenAnswer((_) async => const Ok({'results': [], 'query': 'molin'}));

    await repo.search('molin', lat: 52.58, lng: -2.12);

    final q = verify(() => api.get<Map<String, dynamic>>('/geocode/search',
        query: captureAny(named: 'query'))).captured.single as Map;

    expect(q['q'], 'molin');
    expect(q['lat'], 52.58);
    expect(q['lng'], -2.12);
  });

  test('omits position entirely when unknown', () async {
    when(() => api.get<Map<String, dynamic>>(any(),
            query: any(named: 'query')))
        .thenAnswer((_) async => const Ok({'results': []}));

    await repo.search('molineux');

    final q = verify(() => api.get<Map<String, dynamic>>('/geocode/search',
        query: captureAny(named: 'query'))).captured.single as Map;

    expect(q.containsKey('lat'), isFalse,
        reason: 'sending lat=0 would bias every search to the Atlantic');
  });

  test('preserves server ranking — saved places already come first', () async {
    when(() => api.get<Map<String, dynamic>>(any(),
            query: any(named: 'query')))
        .thenAnswer((_) async => const Ok({
              'results': [
                {'label': 'Home', 'lat': 1.0, 'lng': 1.0, 'source': 'saved'},
                {'label': 'Holt Street', 'lat': 2.0, 'lng': 2.0,
                 'source': 'map'},
              ],
            }));

    final result = await repo.search('ho');

    final labels =
        (result as Ok<List<PlaceSuggestion>>).value.map((p) => p.label);
    expect(labels, ['Home', 'Holt Street']);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/features/booking/data/places_repository_test.dart`
Expected: FAIL — URI does not exist.

- [ ] **Step 3: Write the implementation**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/result.dart';

/// The server returns `[]` below this length rather than an error, so calling
/// is a guaranteed-empty round trip per keystroke.
const kMinQueryLength = 2;

/// One autocomplete row from `GET /api/v1/geocode/search`.
class PlaceSuggestion {
  final String label;
  final double lat;
  final double lng;

  /// Omitted by the server when empty.
  final String? postcode;

  /// `saved` (the rider's own place) or `map` (a Photon hit). Saved places
  /// rank first and are styled differently.
  final String source;

  const PlaceSuggestion({
    required this.label,
    required this.lat,
    required this.lng,
    required this.postcode,
    required this.source,
  });

  bool get isSaved => source == 'saved';

  factory PlaceSuggestion.fromJson(Map<String, dynamic> json) =>
      PlaceSuggestion(
        label: (json['label'] as String?) ?? '',
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        postcode: switch (json['postcode']) {
          String s when s.isNotEmpty => s,
          _ => null,
        },
        source: (json['source'] as String?) ?? 'map',
      );
}

class PlacesRepository {
  final ApiClient _api;
  const PlacesRepository(this._api);

  /// Address autocomplete.
  ///
  /// [lat]/[lng] BIAS the results toward the rider; they do not bound them.
  /// Bounding would return nothing for a trip to Birmingham Airport. When the
  /// position is unknown the parameters are omitted rather than sent as zero,
  /// which would bias every search to a point in the Atlantic.
  ///
  /// An empty result is ambiguous: the server answers with the rider's saved
  /// places alone when Photon is unreachable, silently. Copy must not assert
  /// that no such place exists.
  Future<Result<List<PlaceSuggestion>>> search(
    String query, {
    double? lat,
    double? lng,
  }) async {
    final trimmed = query.trim();
    if (trimmed.length < kMinQueryLength) {
      return const Ok(<PlaceSuggestion>[]);
    }

    final result = await _api.get<Map<String, dynamic>>(
      '/geocode/search',
      query: {
        'q': trimmed,
        if (lat != null && lng != null) 'lat': lat,
        if (lat != null && lng != null) 'lng': lng,
      },
    );

    return switch (result) {
      Ok(:final value) => Ok(((value['results'] as List?) ?? [])
          .cast<Map<String, dynamic>>()
          .map(PlaceSuggestion.fromJson)
          .toList(growable: false)),
      Err(:final error) => Err(error),
    };
  }

  /// Names a point the rider dropped a pin on.
  Future<Result<PlaceSuggestion>> reverse(double lat, double lng) async {
    final result = await _api.get<Map<String, dynamic>>(
      '/geocode/reverse',
      query: {'lat': lat, 'lng': lng},
    );
    return switch (result) {
      Ok(:final value) => Ok(PlaceSuggestion.fromJson(value)),
      Err(:final error) => Err(error),
    };
  }
}

final placesRepositoryProvider = Provider<PlacesRepository>(
    (ref) => PlacesRepository(ref.watch(apiClientProvider)));
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/features/booking/data/places_repository_test.dart`
Expected: PASS (5 tests)

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/booking/data/places_repository.dart app/test/features/booking/data/places_repository_test.dart
git commit -m "feat: place search for route entry

Refuses to call below two characters, because the server answers with an
empty list rather than an error and the call would burn a request per
keystroke for a guaranteed-empty answer.

Position is sent only when known. Sending lat=0 as a default would bias
every search toward a point in the Atlantic, and the parameters bias
rather than bound -- bounding would return nothing for a trip to
Birmingham Airport."
```

---

### Task 3: Fare estimate, including multi-stop

**Files:**
- Create: `app/lib/features/booking/data/fare_repository.dart`
- Test: `app/test/features/booking/data/fare_repository_test.dart`

**Interfaces:**
- Consumes: `ApiClient`, `Pence`, `Result`.
- Produces: `FareLeg` (`seq`, `toLabel`, `distanceMeters`, `durationSeconds`, `farePence`); `FareEstimate` (`totalPence`, `currency`, `distanceMeters`, `durationSeconds`, `legs`, `isMultiStop`, `stopsCount`, `route`, `discountPence`, `discountPct`, `etaSource`); `LatLng`; `FareRepository.estimate({required LatLng pickup, required LatLng dropoff, String? vehicleCategoryId, List<LatLng> waypoints})`; `fareRepositoryProvider`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/api/api_client.dart';
import 'package:hoppin_rider/core/money.dart';
import 'package:hoppin_rider/core/result.dart';
import 'package:hoppin_rider/features/booking/data/fare_repository.dart';
import 'package:mocktail/mocktail.dart';

class _MockApi extends Mock implements ApiClient {}

void main() {
  late _MockApi api;
  late FareRepository repo;

  const pickup = LatLng(52.586, -2.128);
  const dropoff = LatLng(52.593, -2.110);

  setUp(() {
    api = _MockApi();
    repo = FareRepository(api);
    registerFallbackValue(<String, dynamic>{});
  });

  group('single-stop', () {
    test('reads the estimate and keeps money as pence', () async {
      when(() => api.post<Map<String, dynamic>>(any(),
              body: any(named: 'body')))
          .thenAnswer((_) async => const Ok({
                'estimate': {'total': 12.50, 'gross': 12.50,
                             'discount': 0.0, 'discount_pct': 0},
                'distance_meters': 4700,
                'duration_seconds': 780,
                'route': [{'lat': 1.0, 'lng': 2.0}],
                'eta_source': 'model',
              }));

      final result = await repo.estimate(pickup: pickup, dropoff: dropoff);
      final fare = (result as Ok<FareEstimate>).value;

      expect(fare.totalPence, const Pence(1250),
          reason: 'the API sends pounds as a decimal; we store whole pence');
      expect(fare.isMultiStop, isFalse);
      expect(fare.legs, isEmpty);
      expect(fare.distanceMeters, 4700);
      expect(fare.etaSource, 'model');
    });

    test('omits waypoints from the body when there are none', () async {
      when(() => api.post<Map<String, dynamic>>(any(),
              body: any(named: 'body')))
          .thenAnswer((_) async => const Ok({
                'estimate': {'total': 5.0}, 'distance_meters': 100,
                'duration_seconds': 60,
              }));

      await repo.estimate(pickup: pickup, dropoff: dropoff);

      final body = verify(() => api.post<Map<String, dynamic>>(
          '/rides/estimate',
          body: captureAny(named: 'body'))).captured.single as Map;

      expect(body.containsKey('waypoints'), isFalse,
          reason: 'an empty array would switch the server to the multi-stop '
              'response shape for a single-leg trip');
    });
  });

  group('multi-stop', () {
    test('reads per-leg fares and the summed total', () async {
      when(() => api.post<Map<String, dynamic>>(any(),
              body: any(named: 'body')))
          .thenAnswer((_) async => const Ok({
                'multi_stop': true,
                'legs': [
                  {'seq': 0, 'to_label': 'Tesco', 'distance_meters': 1400,
                   'duration_seconds': 300, 'fare_pence': 3000},
                  {'seq': 1, 'to_label': 'Dropoff',
                   'distance_meters': 1800, 'duration_seconds': 360,
                   'fare_pence': 2000},
                ],
                'total_pence': 5000,
                'stops_count': 1,
                'distance_meters': 3200,
                'duration_seconds': 660,
              }));

      final result = await repo.estimate(
        pickup: pickup,
        dropoff: dropoff,
        waypoints: const [LatLng(52.580, -2.120)],
      );
      final fare = (result as Ok<FareEstimate>).value;

      expect(fare.isMultiStop, isTrue);
      expect(fare.legs, hasLength(2));
      expect(fare.legs.first.toLabel, 'Tesco');
      expect(fare.legs.first.farePence, const Pence(3000));
      expect(fare.totalPence, const Pence(5000));
      expect(fare.stopsCount, 1);
    });

    test('the total equals the sum of the legs', () async {
      // The rider is shown per-leg lines and a total; if they disagree the
      // screen looks like it is overcharging.
      when(() => api.post<Map<String, dynamic>>(any(),
              body: any(named: 'body')))
          .thenAnswer((_) async => const Ok({
                'multi_stop': true,
                'legs': [
                  {'seq': 0, 'to_label': 'A', 'distance_meters': 1,
                   'duration_seconds': 1, 'fare_pence': 3000},
                  {'seq': 1, 'to_label': 'B', 'distance_meters': 1,
                   'duration_seconds': 1, 'fare_pence': 9000},
                  {'seq': 2, 'to_label': 'C', 'distance_meters': 1,
                   'duration_seconds': 1, 'fare_pence': 2000},
                ],
                'total_pence': 14000, 'stops_count': 2,
                'distance_meters': 3, 'duration_seconds': 3,
              }));

      final fare = ((await repo.estimate(
        pickup: pickup,
        dropoff: dropoff,
        waypoints: const [LatLng(1, 1), LatLng(2, 2)],
      )) as Ok<FareEstimate>).value;

      final summed = fare.legs
          .map((l) => l.farePence.value)
          .reduce((a, b) => a + b);
      expect(Pence(summed), fare.totalPence);
    });

    test('sends the waypoints in the order given', () async {
      when(() => api.post<Map<String, dynamic>>(any(),
              body: any(named: 'body')))
          .thenAnswer((_) async => const Ok({
                'multi_stop': true, 'legs': [], 'total_pence': 0,
                'stops_count': 2, 'distance_meters': 0,
                'duration_seconds': 0,
              }));

      await repo.estimate(
        pickup: pickup,
        dropoff: dropoff,
        waypoints: const [LatLng(52.580, -2.120), LatLng(52.578, -2.101)],
      );

      final body = verify(() => api.post<Map<String, dynamic>>(any(),
          body: captureAny(named: 'body'))).captured.single as Map;
      final wp = body['waypoints'] as List;

      expect(wp, hasLength(2));
      expect((wp.first as Map)['lat'], 52.580,
          reason: 'stop order is the route; reordering changes the fare');
    });
  });

  group('zone discount', () {
    test('is read when present', () async {
      when(() => api.post<Map<String, dynamic>>(any(),
              body: any(named: 'body')))
          .thenAnswer((_) async => const Ok({
                'estimate': {'gross': 12.00, 'discount_pct': 20,
                             'discount': 2.40, 'total': 9.60},
                'distance_meters': 100, 'duration_seconds': 60,
              }));

      final fare = ((await repo.estimate(pickup: pickup, dropoff: dropoff))
          as Ok<FareEstimate>).value;

      expect(fare.discountPct, 20);
      expect(fare.discountPence, const Pence(240));
      expect(fare.totalPence, const Pence(960));
    });

    test('a zero discount is not rendered as a line', () async {
      when(() => api.post<Map<String, dynamic>>(any(),
              body: any(named: 'body')))
          .thenAnswer((_) async => const Ok({
                'estimate': {'total': 12.00, 'discount_pct': 0,
                             'discount': 0.0},
                'distance_meters': 100, 'duration_seconds': 60,
              }));

      final fare = ((await repo.estimate(pickup: pickup, dropoff: dropoff))
          as Ok<FareEstimate>).value;

      expect(fare.hasDiscount, isFalse);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/features/booking/data/fare_repository_test.dart`
Expected: FAIL — URI does not exist.

- [ ] **Step 3: Write the implementation**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/money.dart';
import '../../../core/result.dart';

class LatLng {
  final double lat;
  final double lng;
  const LatLng(this.lat, this.lng);

  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng};
}

/// One priced leg of a multi-stop trip.
class FareLeg {
  final int seq;
  final String toLabel;
  final int distanceMeters;
  final int durationSeconds;
  final Pence farePence;

  const FareLeg({
    required this.seq,
    required this.toLabel,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.farePence,
  });

  factory FareLeg.fromJson(Map<String, dynamic> json) => FareLeg(
        seq: (json['seq'] as num?)?.toInt() ?? 0,
        toLabel: (json['to_label'] as String?) ?? '',
        distanceMeters: (json['distance_meters'] as num?)?.toInt() ?? 0,
        durationSeconds: (json['duration_seconds'] as num?)?.toInt() ?? 0,
        farePence: Pence.fromJson(json['fare_pence']) ?? Pence.zero,
      );
}

/// A quote from `POST /api/v1/rides/estimate`.
///
/// One call carries everything the booking screens need: the fare, the
/// distance and duration, the road polyline for the preview map, and — for a
/// multi-stop trip — the per-leg breakdown.
class FareEstimate {
  final Pence totalPence;
  final String currency;
  final int distanceMeters;
  final int durationSeconds;

  /// Empty for a single-leg trip.
  final List<FareLeg> legs;
  final bool isMultiStop;
  final int stopsCount;

  /// Road geometry for the preview. Null when OSRM was unreachable, in which
  /// case the map draws a straight line.
  final List<LatLng>? route;

  /// Automatic per-zone discount, already inside [totalPence].
  final Pence discountPence;
  final int discountPct;

  /// Which ETA tier produced the duration: model, google or osrm.
  final String etaSource;

  const FareEstimate({
    required this.totalPence,
    required this.currency,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.legs,
    required this.isMultiStop,
    required this.stopsCount,
    required this.route,
    required this.discountPence,
    required this.discountPct,
    required this.etaSource,
  });

  bool get hasDiscount => discountPct > 0 && discountPence.value > 0;

  /// Pounds arrive as a JSON decimal on the single-stop breakdown; multi-stop
  /// sends integer pence directly. Rounding at the boundary keeps every later
  /// calculation in whole pence.
  static Pence _poundsToPence(Object? raw) =>
      Pence(((raw as num?)?.toDouble() ?? 0) * 100 ~/ 1);

  factory FareEstimate.fromJson(Map<String, dynamic> json) {
    final multi = json['multi_stop'] == true;
    final breakdown =
        (json['estimate'] as Map?)?.cast<String, dynamic>() ?? const {};

    return FareEstimate(
      totalPence: multi
          ? (Pence.fromJson(json['total_pence']) ?? Pence.zero)
          : _poundsToPence(breakdown['total']),
      currency: (json['currency'] as String?) ?? 'GBP',
      distanceMeters: (json['distance_meters'] as num?)?.toInt() ?? 0,
      durationSeconds: (json['duration_seconds'] as num?)?.toInt() ?? 0,
      legs: ((json['legs'] as List?) ?? const [])
          .cast<Map<String, dynamic>>()
          .map(FareLeg.fromJson)
          .toList(growable: false),
      isMultiStop: multi,
      stopsCount: (json['stops_count'] as num?)?.toInt() ?? 0,
      route: switch (json['route']) {
        List points => points
            .cast<Map<String, dynamic>>()
            .map((p) => LatLng(
                (p['lat'] as num).toDouble(), (p['lng'] as num).toDouble()))
            .toList(growable: false),
        _ => null,
      },
      discountPence: _poundsToPence(breakdown['discount']),
      discountPct: (breakdown['discount_pct'] as num?)?.toInt() ?? 0,
      etaSource: (json['eta_source'] as String?) ?? '',
    );
  }
}

class FareRepository {
  final ApiClient _api;
  const FareRepository(this._api);

  /// Quotes a trip.
  ///
  /// This is the ONLY pricing call the app makes. The dispatch engine on
  /// :8081 is not client-facing; the ride service consults it internally so
  /// the quote and the eventual charge price off the same corrected duration.
  ///
  /// Waypoints are omitted entirely when empty — sending `[]` switches the
  /// server to the multi-stop response shape for a single-leg trip.
  Future<Result<FareEstimate>> estimate({
    required LatLng pickup,
    required LatLng dropoff,
    String? vehicleCategoryId,
    List<LatLng> waypoints = const [],
  }) async {
    final result = await _api.post<Map<String, dynamic>>(
      '/rides/estimate',
      body: {
        'pickup_lat': pickup.lat,
        'pickup_lng': pickup.lng,
        'dropoff_lat': dropoff.lat,
        'dropoff_lng': dropoff.lng,
        if (vehicleCategoryId != null)
          'vehicle_category_id': vehicleCategoryId,
        if (waypoints.isNotEmpty)
          'waypoints': waypoints.map((w) => w.toJson()).toList(),
      },
    );

    return switch (result) {
      Ok(:final value) => Ok(FareEstimate.fromJson(value)),
      Err(:final error) => Err(error),
    };
  }
}

final fareRepositoryProvider = Provider<FareRepository>(
    (ref) => FareRepository(ref.watch(apiClientProvider)));
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/features/booking/data/fare_repository_test.dart`
Expected: PASS (8 tests)

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/booking/data/fare_repository.dart app/test/features/booking/data/fare_repository_test.dart
git commit -m "feat: fare estimate including multi-stop

One call carries the fare, distance, duration, the preview polyline and
the per-leg breakdown. The app never calls the dispatch engine directly:
it is not client-facing, and the ride service consults it internally so
the quote and the charge price off the same corrected duration.

Waypoints are omitted when empty rather than sent as an empty array,
which would switch the server to the multi-stop response shape for a
single-leg trip.

A test asserts the legs sum to the total. The rider sees both, and a
disagreement would read as overcharging."
```

---

### Task 4: Booking request

**Files:**
- Create: `app/lib/features/booking/data/booking_repository.dart`
- Test: `app/test/features/booking/data/booking_repository_test.dart`

**Interfaces:**
- Consumes: `ApiClient`, `LatLng`, `Result`, `ApiException`.
- Produces: `BookingRequest` (`requestId`); `BookingRepository.request({required LatLng pickup, required LatLng dropoff, required String vehicleCategoryId, List<LatLng> waypoints})`; `const kMaxWaypoints = 5`; `bookingRepositoryProvider`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/api/api_client.dart';
import 'package:hoppin_rider/core/api/api_exception.dart';
import 'package:hoppin_rider/core/result.dart';
import 'package:hoppin_rider/features/booking/data/booking_repository.dart';
import 'package:hoppin_rider/features/booking/data/fare_repository.dart';
import 'package:mocktail/mocktail.dart';

class _MockApi extends Mock implements ApiClient {}

void main() {
  late _MockApi api;
  late BookingRepository repo;

  const pickup = LatLng(52.586, -2.128);
  const dropoff = LatLng(52.593, -2.110);

  setUp(() {
    api = _MockApi();
    repo = BookingRepository(api);
  });

  test('returns the request id from a 202', () async {
    when(() => api.post<Map<String, dynamic>>(any(), body: any(named: 'body')))
        .thenAnswer((_) async => const Ok({'request_id': 'req-42'}));

    final result = await repo.request(
      pickup: pickup, dropoff: dropoff, vehicleCategoryId: 'cat-1');

    expect((result as Ok<BookingRequest>).value.requestId, 'req-42');
  });

  test('refuses more than five stops before calling', () async {
    // The server caps waypoints at 5. Failing here costs nothing; failing
    // server-side costs a round trip and a worse message.
    final result = await repo.request(
      pickup: pickup,
      dropoff: dropoff,
      vehicleCategoryId: 'cat-1',
      waypoints: const [
        LatLng(1, 1), LatLng(2, 2), LatLng(3, 3),
        LatLng(4, 4), LatLng(5, 5), LatLng(6, 6),
      ],
    );

    expect((result as Err).error.code, 'VALIDATION_FAILED');
    verifyNever(() => api.post<Map<String, dynamic>>(any(),
        body: any(named: 'body')));
  });

  test('accepts exactly five stops', () async {
    when(() => api.post<Map<String, dynamic>>(any(), body: any(named: 'body')))
        .thenAnswer((_) async => const Ok({'request_id': 'req-1'}));

    final result = await repo.request(
      pickup: pickup,
      dropoff: dropoff,
      vehicleCategoryId: 'cat-1',
      waypoints: const [
        LatLng(1, 1), LatLng(2, 2), LatLng(3, 3),
        LatLng(4, 4), LatLng(5, 5),
      ],
    );

    expect(result, isA<Ok<BookingRequest>>());
  });

  test('surfaces a booking refusal with its code intact', () async {
    // NO_PAYMENT_METHOD, ACTIVE_TRIP_EXISTS, OUTSIDE_SERVICE_AREA and the
    // rest each need a distinct screen response.
    when(() => api.post<Map<String, dynamic>>(any(), body: any(named: 'body')))
        .thenAnswer((_) async => Err(ApiException(
            'NO_PAYMENT_METHOD', 'add a payment card to book a ride', 402)));

    final result = await repo.request(
      pickup: pickup, dropoff: dropoff, vehicleCategoryId: 'cat-1');

    final err = (result as Err).error;
    expect(err.code, 'NO_PAYMENT_METHOD');
    expect(err.message, 'add a payment card to book a ride',
        reason: 'server copy is shown verbatim');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/features/booking/data/booking_repository_test.dart`
Expected: FAIL — URI does not exist.

- [ ] **Step 3: Write the implementation**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/result.dart';
import 'fare_repository.dart' show LatLng;

/// The server caps intermediate stops at five.
const kMaxWaypoints = 5;

/// The acknowledgement from `POST /api/v1/rides/request`.
///
/// Booking is fire-and-forget: a 202 means dispatch has the request, not that
/// a driver exists. The trip screen watches for the match.
class BookingRequest {
  final String requestId;
  const BookingRequest(this.requestId);

  factory BookingRequest.fromJson(Map<String, dynamic> json) =>
      BookingRequest((json['request_id'] as String?) ?? '');
}

class BookingRepository {
  final ApiClient _api;
  const BookingRepository(this._api);

  /// Requests a ride.
  ///
  /// The server prices every leg at this moment, while it still holds the
  /// rider's token, so the estimate, the driver's offer and the final charge
  /// all agree. Sending stops in a different order than they were quoted
  /// would change the fare.
  Future<Result<BookingRequest>> request({
    required LatLng pickup,
    required LatLng dropoff,
    required String vehicleCategoryId,
    List<LatLng> waypoints = const [],
  }) async {
    if (waypoints.length > kMaxWaypoints) {
      return Err(ApiException(
        'VALIDATION_FAILED',
        'A trip can have at most $kMaxWaypoints stops.',
        0,
      ));
    }

    final result = await _api.post<Map<String, dynamic>>(
      '/rides/request',
      body: {
        'pickup_lat': pickup.lat,
        'pickup_lng': pickup.lng,
        'dropoff_lat': dropoff.lat,
        'dropoff_lng': dropoff.lng,
        'vehicle_category_id': vehicleCategoryId,
        if (waypoints.isNotEmpty)
          'waypoints': waypoints.map((w) => w.toJson()).toList(),
      },
    );

    return switch (result) {
      Ok(:final value) => Ok(BookingRequest.fromJson(value)),
      Err(:final error) => Err(error),
    };
  }
}

final bookingRepositoryProvider = Provider<BookingRepository>(
    (ref) => BookingRepository(ref.watch(apiClientProvider)));
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/features/booking/data/booking_repository_test.dart`
Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/booking/data/booking_repository.dart app/test/features/booking/data/booking_repository_test.dart
git commit -m "feat: booking request

Refuses more than five stops before calling, since the server caps them
there and failing locally costs nothing while failing server-side costs
a round trip and a worse message.

Booking refusals pass through with their codes intact --
NO_PAYMENT_METHOD, ACTIVE_TRIP_EXISTS, OUTSIDE_SERVICE_AREA and the rest
each need a distinct response from the screen."
```

---

### Task 5: Live contract tests for the booking endpoints

**Files:**
- Modify: `app/test/integration/live_backend_test.dart`

**Interfaces:**
- Consumes: `AppConfig`.
- Produces: nothing — verification only.

- [ ] **Step 1: Add the tests**

Append inside the existing `group('live backend', ...)`:

```dart
    test('/geocode/search is JWT-gated', () async {
      final response = await get('/geocode/search?q=molineux');
      expect(response.statusCode, anyOf(401, 403),
          reason: 'autocomplete must not be an open geocoding service');
    });

    test('/rides/estimate rejects an unauthenticated caller', () async {
      final request =
          await client.postUrl(Uri.parse('${AppConfig.apiBaseUrl}/rides/estimate'));
      request.headers.set('X-Hoppin-Device-ID', 'integration-test');
      request.headers.contentType = ContentType.json;
      request.write('{"pickup_lat":52.586,"pickup_lng":-2.128,'
          '"dropoff_lat":52.593,"dropoff_lng":-2.110}');
      final response = await request.close();

      expect(response.statusCode, anyOf(401, 403),
          reason: 'pricing must not be free to anyone who asks');
    });

    test('/contacts is public, like /app-status', () async {
      // Support and emergency numbers are read live so they can change
      // without an app release, and the safety screen needs them before a
      // rider has necessarily signed in.
      final response = await get('/contacts');
      expect(response.statusCode, 200);
    });
```

- [ ] **Step 2: Run against the live backend**

Run: `cd app && flutter test test/integration --run-skipped --dart-define-from-file=../config/dev.json`
Expected: PASS (8 tests)

- [ ] **Step 3: Commit**

```bash
git add app/test/integration/live_backend_test.dart
git commit -m "test: live contract checks for the booking endpoints

Confirms autocomplete and pricing both refuse an unauthenticated caller
-- neither should be a free service to anyone who asks -- and that
/contacts is public, which the safety screen depends on.

These caught a real spec error last time: /app-status requires a
platform parameter where the spec described a bare call."
```

---

## What is NOT in this batch, and why

**The booking screens themselves.** `google_maps_flutter` needs an API key restricted per platform (Maps SDK for Android, Maps SDK for iOS — two keys, both restricted by application and by API). Until those exist the map cannot render, and the home, route-entry, vehicle-picker and fare screens are all map-shaped. They follow in batch 3, consuming exactly the models above.

**Card management.** Needs the Stripe publishable key. Batch 4.

---

## Self-review

**Spec coverage.** §7.1 booking endpoints are covered: `/vehicle-types` (Task 1), `/geocode/search` and `/geocode/reverse` (Task 2), `/rides/estimate` including the multi-stop and zone-discount shapes (Task 3), `/rides/request` (Task 4). §6.1 booking refusals surface with codes intact (Task 4). The multi-stop money model from `SCREEN-DECISIONS.md` is asserted (Task 3).

**Not covered, deliberately:** `/service-areas` and `/service-areas/check` — the home map consumes them and they land with it in batch 3. `/scheduled-rides` is out of milestone 1.

**Placeholders:** none. Every step carries its code.

**Type consistency:** `LatLng` is defined in Task 3 and imported by Task 4 via `show LatLng`. `Pence` comes from existing `core/money.dart`. `FareLeg`/`FareEstimate` are defined and used only in Task 3. `ApiClient.get` takes `query:`, `post` takes `body:` — matching the existing client.
