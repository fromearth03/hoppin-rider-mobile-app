# Booking Flow Wiring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A rider can go home → route entry → fare quotes → confirm → live trip; every screen already exists, this plan wires them together.

**Architecture:** Route entry keeps the chosen `RoutePoint`s (label + LatLng) alongside its text fields and gains a Confirm Route button that pushes `/fare-confirm` with a `ChosenRoute` as go_router `extra`. A new `FareConfirmFlow` wrapper fetches vehicle categories, renders the existing `FareConfirmScreen`, and on confirm calls `BookingRepository.request`, then `context.go`es to `/live-trip?ride=<requestId>`. Home's search field becomes tappable and opens `/route`.

**Tech Stack:** Flutter, Riverpod 2, go_router 14, mocktail. No new dependencies.

**Spec:** `docs/SCREEN-DECISIONS.md` sections "Route entry", "Fare / driver selection", "Live trip"; frames `Enter Your Route.png`, `Pricing Details.png`, `Start Ride.png`.

## Global Constraints

- No demo fakeness: every control either works against the real backend or renders visibly disabled. Booking POSTs the real `/rides/request`.
- `Result<T>` over exceptions; `Pence` never a double; server-owned copy rendered verbatim; `RiderErrorCopy.messageFor` for API errors.
- Tests before implementation (TDD). Run targeted `flutter test <path>` per task (full suite ~10 min — leave for the end).
- All commands from `app/`. PowerShell, never bash. Long runs: background.
- Existing types (do NOT redefine): `RoutePoint(label, position)`, `ChosenRoute({pickup, dropoff, stops})` in `route_entry_screen.dart`; `PlaceSuggestion` has `.label`, `.lat`, `.lng`; `FareConfirmScreen({pickup, dropoff, waypoints, categories, onConfirm})`; `BookingRepository.request({pickup, dropoff, vehicleCategoryId, waypoints})` → `Result<BookingRequest>` with `.requestId`; `vehicleCategoriesProvider` in `home_screen.dart`; routes in `AppRoutes`.

---

### Task 1: Route entry keeps chosen points and confirms the route

**Files:**
- Modify: `app/lib/features/booking/presentation/route_entry_screen.dart`
- Test: `app/test/features/booking/presentation/route_entry_confirm_test.dart` (create)

**Interfaces:**
- Consumes: `PlaceSuggestion.lat/lng/label`, `ChosenRoute`, `AppRoutes.fareConfirm`.
- Produces: route entry pushes `AppRoutes.fareConfirm` with `extra` of type `ChosenRoute`. Task 2's router builder reads exactly that.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hoppin_rider/core/result.dart';
import 'package:hoppin_rider/core/theme/app_theme.dart';
import 'package:hoppin_rider/features/booking/data/places_repository.dart';
import 'package:hoppin_rider/features/booking/presentation/route_entry_screen.dart';
import 'package:hoppin_rider/shared/nav/app_router.dart';
import 'package:mocktail/mocktail.dart';

class _MockPlaces extends Mock implements PlacesRepository {}

void main() {
  late _MockPlaces places;
  ChosenRoute? received;

  Widget harness() {
    final router = GoRouter(
      initialLocation: AppRoutes.route,
      routes: [
        GoRoute(
          path: AppRoutes.route,
          builder: (_, __) => const RouteEntryScreen(),
        ),
        GoRoute(
          path: AppRoutes.fareConfirm,
          builder: (_, state) {
            received = state.extra as ChosenRoute?;
            return const Scaffold(body: Text('fare screen'));
          },
        ),
      ],
    );
    return ProviderScope(
      overrides: [placesRepositoryProvider.overrideWithValue(places)],
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    );
  }

  const hanley = PlaceSuggestion(
    label: 'Hanley, Stoke-on-Trent',
    lat: 53.0235,
    lng: -2.1774,
    postcode: 'ST1',
    source: 'geocoder',
  );
  const keele = PlaceSuggestion(
    label: 'Keele University',
    lat: 53.0044,
    lng: -2.2734,
    postcode: 'ST5',
    source: 'geocoder',
  );

  setUp(() {
    places = _MockPlaces();
    received = null;
    when(() => places.search(any()))
        .thenAnswer((_) async => const Ok([hanley, keele]));
  });

  Future<void> pickInField(WidgetTester tester, String hint, String label,
      PlaceSuggestion suggestion) async {
    await tester.tap(find.widgetWithText(TextField, hint).first);
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, hint).first, label);
    await tester.pump(const Duration(milliseconds: 300)); // debounce
    await tester.pump(); // search resolves
    await tester.tap(find.text(suggestion.label).last);
    await tester.pump();
  }

  testWidgets('Confirm Route stays disabled until both ends are chosen',
      (tester) async {
    await tester.pumpWidget(harness());

    final button = find.widgetWithText(FilledButton, 'Confirm Route');
    expect(button, findsOneWidget);
    expect(tester.widget<FilledButton>(button).onPressed, isNull);

    await pickInField(tester, 'Active Location', 'Han', hanley);
    expect(tester.widget<FilledButton>(button).onPressed, isNull,
        reason: 'pickup alone cannot be quoted');

    await pickInField(tester, 'To', 'Kee', keele);
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
  });

  testWidgets('confirming pushes fare-confirm carrying the chosen route',
      (tester) async {
    await tester.pumpWidget(harness());
    await pickInField(tester, 'Active Location', 'Han', hanley);
    await pickInField(tester, 'To', 'Kee', keele);

    await tester.tap(find.widgetWithText(FilledButton, 'Confirm Route'));
    await tester.pumpAndSettle();

    expect(find.text('fare screen'), findsOneWidget);
    expect(received, isNotNull);
    expect(received!.pickup.label, hanley.label);
    expect(received!.pickup.position.lat, hanley.lat);
    expect(received!.dropoff.position.lng, keele.lng);
    expect(received!.stops, isEmpty);
  });

  testWidgets('editing a chosen field invalidates it and disables confirm',
      (tester) async {
    await tester.pumpWidget(harness());
    await pickInField(tester, 'Active Location', 'Han', hanley);
    await pickInField(tester, 'To', 'Kee', keele);

    final toField = find.widgetWithText(TextField, keele.label).first;
    await tester.enterText(toField, 'Keele Univ');
    await tester.pump();

    final button = find.widgetWithText(FilledButton, 'Confirm Route');
    expect(tester.widget<FilledButton>(button).onPressed, isNull,
        reason: 'typed text is not a geocoded place; booking it would send '
            'stale coordinates under a new label');
  });
}
```

Note: if `PlaceSuggestion` has no const constructor with those named
parameters, open `app/lib/features/booking/data/places_repository.dart`,
copy the real constructor, and adapt the two fixtures — do not change the
production class to fit the test.

- [ ] **Step 2: Run test to verify it fails**

Run (from `app/`): `flutter test test/features/booking/presentation/route_entry_confirm_test.dart`
Expected: FAIL — no `FilledButton` with text 'Confirm Route' exists.

- [ ] **Step 3: Implement in `route_entry_screen.dart`**

Add state fields next to the controllers in `_RouteEntryScreenState`:

```dart
  RoutePoint? _pickupPoint;
  RoutePoint? _dropoffPoint;
  final Map<int, RoutePoint> _stopPoints = {}; // key: stop index
```

Extend `_choose` to record the point for the active field (keep the
existing controller/text logic):

```dart
  void _choose(PlaceSuggestion place) {
    final point = RoutePoint(place.label, LatLng(place.lat, place.lng));
    switch (_activeField) {
      case 0:
        _pickup.text = place.label;
        _pickupPoint = point;
      case 1:
        _dropoff.text = place.label;
        _dropoffPoint = point;
      default:
        _stops[_activeField - 2].text = place.label;
        _stopPoints[_activeField - 2] = point;
    }
    setState(() => _results = const []);
    FocusScope.of(context).unfocus();
  }
```

In `_onChanged`, before the debounce logic, invalidate the active field's
point — typed text is not a geocoded place:

```dart
    setState(() {
      switch (_activeField) {
        case 0:
          _pickupPoint = null;
        case 1:
          _dropoffPoint = null;
        default:
          _stopPoints.remove(_activeField - 2);
      }
    });
```

In `_removeStop`, also fix up `_stopPoints` (delete the removed index and
shift the ones above it down by one):

```dart
      _stopPoints.remove(i);
      final shifted = <int, RoutePoint>{};
      _stopPoints.forEach((k, v) => shifted[k > i ? k - 1 : k] = v);
      _stopPoints
        ..clear()
        ..addAll(shifted);
```

Add a `_routeComplete` getter and `_confirm` method:

```dart
  bool get _routeComplete =>
      _pickupPoint != null &&
      _dropoffPoint != null &&
      List.generate(_stops.length, (i) => i)
          .every(_stopPoints.containsKey);

  void _confirm() {
    context.push(
      AppRoutes.fareConfirm,
      extra: ChosenRoute(
        pickup: _pickupPoint!,
        dropoff: _dropoffPoint!,
        stops: [
          for (var i = 0; i < _stops.length; i++) _stopPoints[i]!,
        ],
      ),
    );
  }
```

Imports to add: `package:go_router/go_router.dart` and
`../../../shared/nav/app_router.dart`.

Add the button to the Scaffold as `bottomNavigationBar` (matches the
fare screen's pattern):

```dart
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: FilledButton(
          onPressed: _routeComplete ? _confirm : null,
          child: const Text('Confirm Route'),
        ),
      ),
```

- [ ] **Step 4: Run the new test and the existing route entry tests**

Run: `flutter test test/features/booking/presentation/route_entry_confirm_test.dart test/features/booking/presentation/route_entry_screen_test.dart`
(second file: whatever existing test file covers `RouteEntryScreen` — find
it with `Grep RouteEntryScreen app/test`; if none exists, run just the new file)
Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add app/lib/features/booking/presentation/route_entry_screen.dart app/test/features/booking/presentation/route_entry_confirm_test.dart
git commit -m "feat: route entry assembles and confirms a bookable route"
```

---

### Task 2: FareConfirmFlow — categories in, booking out

**Files:**
- Create: `app/lib/features/booking/presentation/fare_confirm_flow.dart`
- Modify: `app/lib/shared/nav/app_router.dart` (the `AppRoutes.fareConfirm` GoRoute)
- Test: `app/test/features/booking/presentation/fare_confirm_flow_test.dart` (create)

**Interfaces:**
- Consumes: `ChosenRoute` from Task 1 (via `state.extra`), `vehicleCategoriesProvider` (from `home_screen.dart`), `FareConfirmScreen.onConfirm`, `BookingRepository.request` → `Result<BookingRequest>` (`.requestId`).
- Produces: on booking success navigates `context.go('${AppRoutes.liveTrip}?ride=<requestId>')`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hoppin_rider/core/api/api_exception.dart';
import 'package:hoppin_rider/core/geo.dart';
import 'package:hoppin_rider/core/result.dart';
import 'package:hoppin_rider/core/theme/app_theme.dart';
import 'package:hoppin_rider/features/booking/data/booking_repository.dart';
import 'package:hoppin_rider/features/booking/data/fare_repository.dart';
import 'package:hoppin_rider/features/booking/data/vehicle_repository.dart';
import 'package:hoppin_rider/features/booking/presentation/fare_confirm_flow.dart';
import 'package:hoppin_rider/features/booking/presentation/home_screen.dart';
import 'package:hoppin_rider/features/booking/presentation/route_entry_screen.dart';
import 'package:hoppin_rider/features/booking/presentation/widgets/fare_category_card.dart';
import 'package:hoppin_rider/shared/nav/app_router.dart';
import 'package:mocktail/mocktail.dart';

class _MockFares extends Mock implements FareRepository {}

class _MockBooking extends Mock implements BookingRepository {}

const _standard = VehicleCategory(
  id: 'a',
  name: 'Standard',
  seats: 4,
  bags: 2,
  priceMultiplier: 1.0,
);

const _route = ChosenRoute(
  pickup: RoutePoint('Hanley', LatLng(53.0235, -2.1774)),
  dropoff: RoutePoint('Keele', LatLng(53.0044, -2.2734)),
);

const _estimate = FareEstimate(
  totalPence: 2500,
  currency: 'GBP',
  distanceMeters: 8000,
  durationSeconds: 900,
  legs: [],
  isMultiStop: false,
  stopsCount: 0,
  route: [],
  discountPence: 0,
  discountPct: 0,
  discountKnown: false,
  etaSource: 'osrm',
);
// If FareEstimate's constructor differs, copy the fixture builder from
// test/features/booking/presentation/fare_confirm_screen_test.dart instead
// of guessing parameters.

void main() {
  late _MockFares fares;
  late _MockBooking booking;
  String? location;

  Widget harness() {
    final router = GoRouter(
      initialLocation: AppRoutes.fareConfirm,
      routes: [
        GoRoute(
          path: AppRoutes.fareConfirm,
          builder: (_, __) => const FareConfirmFlow(route: _route),
        ),
        GoRoute(
          path: AppRoutes.liveTrip,
          builder: (_, state) {
            location = state.uri.toString();
            return const Scaffold(body: Text('live trip'));
          },
        ),
      ],
    );
    return ProviderScope(
      overrides: [
        vehicleCategoriesProvider.overrideWith((ref) async => [_standard]),
        fareRepositoryProvider.overrideWithValue(fares),
        bookingRepositoryProvider.overrideWithValue(booking),
      ],
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    );
  }

  setUp(() {
    fares = _MockFares();
    booking = _MockBooking();
    location = null;
    when(() => fares.estimate(
          pickup: any(named: 'pickup'),
          dropoff: any(named: 'dropoff'),
          vehicleCategoryId: any(named: 'vehicleCategoryId'),
          waypoints: any(named: 'waypoints'),
        )).thenAnswer((_) async => const Ok(_estimate));
  });

  testWidgets('quotes the fetched categories for the chosen route',
      (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(find.byType(FareCategoryCard), findsOneWidget);
    final captured = verify(() => fares.estimate(
          pickup: captureAny(named: 'pickup'),
          dropoff: any(named: 'dropoff'),
          vehicleCategoryId: any(named: 'vehicleCategoryId'),
          waypoints: any(named: 'waypoints'),
        )).captured;
    expect((captured.single as LatLng).lat, _route.pickup.position.lat);
  });

  testWidgets('confirm books the ride and lands on the live trip',
      (tester) async {
    when(() => booking.request(
          pickup: any(named: 'pickup'),
          dropoff: any(named: 'dropoff'),
          vehicleCategoryId: any(named: 'vehicleCategoryId'),
          waypoints: any(named: 'waypoints'),
        )).thenAnswer((_) async => const Ok(BookingRequest('req-42')));

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FareCategoryCard));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await tester.pumpAndSettle();

    expect(find.text('live trip'), findsOneWidget);
    expect(location, contains('ride=req-42'));
    verify(() => booking.request(
          pickup: any(named: 'pickup'),
          dropoff: any(named: 'dropoff'),
          vehicleCategoryId: 'a',
          waypoints: any(named: 'waypoints'),
        )).called(1);
  });

  testWidgets('a booking failure surfaces the server message and stays put',
      (tester) async {
    when(() => booking.request(
          pickup: any(named: 'pickup'),
          dropoff: any(named: 'dropoff'),
          vehicleCategoryId: any(named: 'vehicleCategoryId'),
          waypoints: any(named: 'waypoints'),
        )).thenAnswer((_) async => const Err(
          ApiException('NO_PAYMENT_METHOD', 'Add a payment card first.', 402),
        ));

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FareCategoryCard));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await tester.pumpAndSettle();

    expect(find.text('live trip'), findsNothing);
    expect(find.textContaining('card'), findsWidgets);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/booking/presentation/fare_confirm_flow_test.dart`
Expected: FAIL — `fare_confirm_flow.dart` does not exist.

- [ ] **Step 3: Create `fare_confirm_flow.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/error_codes.dart';
import '../../../core/result.dart';
import '../data/booking_repository.dart';
import '../data/vehicle_repository.dart';
import 'fare_confirm_screen.dart';
import 'home_screen.dart' show vehicleCategoriesProvider;
import 'route_entry_screen.dart' show ChosenRoute;

/// Owns the fare-confirm step of the booking flow: fetches the categories,
/// hands them to [FareConfirmScreen], books the chosen one, and moves the
/// rider to the live trip.
///
/// Booking is fire-and-forget on the server (a 202 with a request id means
/// dispatch has it, not that a driver exists), so success navigates straight
/// to the trip screen's honest "finding your driver" state with that id.
class FareConfirmFlow extends ConsumerStatefulWidget {
  final ChosenRoute route;

  const FareConfirmFlow({super.key, required this.route});

  @override
  ConsumerState<FareConfirmFlow> createState() => _FareConfirmFlowState();
}

class _FareConfirmFlowState extends ConsumerState<FareConfirmFlow> {
  bool _booking = false;

  Future<void> _book(VehicleCategory category) async {
    if (_booking) return; // double-tap on Confirm must not book twice
    setState(() => _booking = true);

    final result = await ref.read(bookingRepositoryProvider).request(
          pickup: widget.route.pickup.position,
          dropoff: widget.route.dropoff.position,
          vehicleCategoryId: category.id,
          waypoints: [
            for (final stop in widget.route.stops) stop.position,
          ],
        );
    if (!mounted) return;
    setState(() => _booking = false);

    switch (result) {
      case Ok(:final value):
        context.go('${AppRoutesForFlow.liveTrip}?ride=${value.requestId}');
      case Err(:final error):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(RiderErrorCopy.messageFor(error))),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(vehicleCategoriesProvider);

    return categories.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, __) => Scaffold(
        appBar: AppBar(title: const Text('Pricing Details')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Could not load vehicle options.',
                    style: Theme.of(context).textTheme.bodyLarge),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => ref.invalidate(vehicleCategoriesProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
      data: (list) => FareConfirmScreen(
        pickup: widget.route.pickup.position,
        dropoff: widget.route.dropoff.position,
        waypoints: [for (final stop in widget.route.stops) stop.position],
        categories: list,
        onConfirm: _book,
      ),
    );
  }
}
```

`AppRoutesForFlow.liveTrip` is a deliberate compile error placeholder-check:
replace it with the real `AppRoutes.liveTrip` and add the import
`../../../shared/nav/app_router.dart`. (If that import creates a cycle —
app_router imports this file in Step 4 — keep the string literal
`'/live-trip'` with a comment pointing at `AppRoutes.liveTrip`, and assert
equality in the router test instead.)

- [ ] **Step 4: Wire the router**

In `app/lib/shared/nav/app_router.dart`, import the flow and change the
fare-confirm route:

```dart
      GoRoute(
        path: AppRoutes.fareConfirm,
        builder: (_, state) {
          // A deep link or refresh has no route to price — the screen's
          // empty state says so honestly.
          final route = state.extra;
          return route is ChosenRoute
              ? FareConfirmFlow(route: route)
              : const FareConfirmScreen();
        },
      ),
```

Imports: `../../features/booking/presentation/fare_confirm_flow.dart` and
`../../features/booking/presentation/route_entry_screen.dart` is already
imported (ChosenRoute lives there).

- [ ] **Step 5: Run the tests**

Run: `flutter test test/features/booking/presentation/fare_confirm_flow_test.dart test/shared/nav`
Expected: PASS.

- [ ] **Step 6: Commit**

```powershell
git add app/lib/features/booking/presentation/fare_confirm_flow.dart app/lib/shared/nav/app_router.dart app/test/features/booking/presentation/fare_confirm_flow_test.dart
git commit -m "feat: fare confirm books the ride and hands off to the live trip"
```

---

### Task 3: Home search field opens route entry

**Files:**
- Modify: `app/lib/features/booking/presentation/home_screen.dart` (`_SearchField`, ~line 263)
- Test: `app/test/features/booking/presentation/home_screen_test.dart` (extend the existing file, matching its harness)

**Interfaces:**
- Consumes: `AppRoutes.route` (already imported? check; add `../../../shared/nav/app_router.dart` + `package:go_router/go_router.dart` if not).
- Produces: tapping the search bar pushes `/route`.

- [ ] **Step 1: Write the failing test** — add to the existing home screen test file, reusing its provider overrides for `vehicleCategoriesProvider`. Wrap the screen in a minimal real-path GoRouter exactly like the settings navigation test in `app/test/features/settings/presentation/settings_screen_test.dart` (`initialLocation: AppRoutes.home`, real `HomeScreen` builder, `AppRoutes.route` builder returning `const RouteEntryScreen()` with `placesRepositoryProvider` mocked or simply a `Scaffold(body: Text('route entry'))` marker):

```dart
  testWidgets('tapping the search bar opens route entry', (tester) async {
    // reuse this file's existing category stubbing
    final router = GoRouter(
      initialLocation: AppRoutes.home,
      routes: [
        GoRoute(path: AppRoutes.home, builder: (_, __) => const HomeScreen()),
        GoRoute(
            path: AppRoutes.route,
            builder: (_, __) => const Scaffold(body: Text('route entry'))),
      ],
    );
    await tester.pumpWidget(/* this file's ProviderScope overrides */
        ProviderScope(
      overrides: [/* same overrides the neighbouring tests use */],
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Where to & for how much?'));
    await tester.pumpAndSettle();

    expect(find.text('route entry'), findsOneWidget);
  });
```

The `/* */` markers are for the implementer to copy the exact overrides
already present in that test file — read the file first; its `setUp` and
harness show which providers the home screen needs stubbed.

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/booking/presentation/home_screen_test.dart`
Expected: the new test FAILS (tap hits nothing navigable); old tests still pass.

- [ ] **Step 3: Make `_SearchField` tappable**

```dart
class _SearchField extends StatelessWidget {
  const _SearchField();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.push(AppRoutes.route),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Icon(Icons.search,
                  color: theme.textTheme.bodyMedium?.color, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Where to & for how much?',
                  style: theme.textTheme.bodyMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

(The `Container` becomes `Material` + `InkWell` so the tap has ink and the
radius clips it; imports: `package:go_router/go_router.dart`,
`../../../shared/nav/app_router.dart` — check which are already present.)

- [ ] **Step 4: Run the home screen tests**

Run: `flutter test test/features/booking/presentation/home_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add app/lib/features/booking/presentation/home_screen.dart app/test/features/booking/presentation/home_screen_test.dart
git commit -m "feat: home search bar opens route entry"
```

---

### Task 4: Screens with no ride id skip the doomed request

**Files:**
- Modify: `app/lib/features/chat/presentation/chat_screen.dart`, `app/lib/features/payments/presentation/ride_complete_screen.dart`, `app/lib/features/history/presentation/trip_details_screen.dart`, `app/lib/features/history/presentation/ride_details_screen.dart` — whichever of these fetch by ride id (verify with `Grep "rideId" app/lib`)
- Test: each screen's existing test file gains one test

**Interfaces:**
- Consumes: each screen's existing empty-id rendering (they already render "invalid ride id"-style states when the server rejects).
- Produces: with `rideId == ''` the screen renders its error/empty state WITHOUT calling the repository — no more `GET /rides//receipt` 400s in the network log.

- [ ] **Step 1: For each screen, add a failing test** asserting the repository is never called when the id is empty. Shape (adapt to each file's existing harness and mocks — every one of these test files already has a mocked repository and a pump helper):

```dart
  testWidgets('an empty ride id never hits the network', (tester) async {
    await tester.pumpWidget(harness(rideId: ''));
    await tester.pumpAndSettle();

    verifyZeroInteractions(repository);
    // and the screen still stands (no crash):
    expect(find.byType(Scaffold), findsOneWidget);
  });
```

- [ ] **Step 2: Run each file, verify the new test fails** (repository currently called).

- [ ] **Step 3: Guard each fetch** at the point the screen (or its provider) starts loading:

```dart
    if (rideId.isEmpty) {
      // A missing id can only come from a hand-typed URL. The request it
      // would send — /rides//receipt — is malformed; skip straight to the
      // error state the screen already renders for a failed load.
      return; // or the provider's Err(...) equivalent, matching the file
    }
```

The exact placement differs per screen (some fetch in a provider family,
some in initState); match each file's own pattern, keep its existing
error rendering as the visible result.

- [ ] **Step 4: Run those four test files.** Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add app/lib/features/chat app/lib/features/payments app/lib/features/history app/test
git commit -m "fix: screens opened without a ride id no longer fire malformed requests"
```

---

### Task 5: Full verification and web rebuild

**Files:** none new.

- [ ] **Step 1: Full suite** — `flutter test` (background, ~10 min). Expected: everything passes.
- [ ] **Step 2: Analyze** — `flutter analyze lib`. Expected: clean.
- [ ] **Step 3: Golden regen for changed screens** — `flutter test test/golden/profile_and_booking_render_test.dart test/golden/fidelity_pass_render_test.dart --run-skipped --update-goldens`, then LOOK at the changed shots beside `Enter Your Route.png` and `Pricing Details.png` (430px and 320px). The new Confirm Route button must not overflow at 320px.
- [ ] **Step 4: Web rebuild** — `flutter build web --dart-define-from-file=../config/dev.json`.
- [ ] **Step 5: Commit any golden updates** —

```powershell
git add app/test/golden
git commit -m "test: goldens for the wired booking flow"
```
