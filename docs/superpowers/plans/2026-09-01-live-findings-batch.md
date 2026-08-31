# Live Findings Batch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the three defects Ismail hit live (dead Cancel Ride, unwired scheduled rides, no exit from the schedule screen) and bring Ride Details + payment selection UI to frame fidelity.

**Architecture:** Two new repositories against contracts read from the Go source (`ride_handler.go`): `RideCancellationRepository` (PATCH /rides/:id/cancel + GET /cancellation-reasons) and `ScheduledRidesRepository` (POST/GET/DELETE /scheduled-rides). A `RideContextRepository` (GET /rides/:id) replaces the LiveTripSource placeholder's empty stream so driver data flows the day a driver accepts. UI: Ride Details bottom card and Select Payment Method sheet styled to `Ride Details.png` / `Select Payment Method.png`, real data only, disabled-honest where the backend has nothing.

**Tech Stack:** Flutter, Riverpod 2, Dio via ApiClient, mocktail. No new dependencies.

**Spec:** Contracts verified in `C:\Users\Hp\c2o\Hoppin\hoppin\Go_ride_service\internal\handler\ride_handler.go` (cancel: ~1065–1135; scheduled: ~1604–1770). Frames: `Ride Details.png`, `Select Payment Method.png`, `Schedule Ride.png`. House rules in docs/SCREEN-DECISIONS.md.

## Global Constraints

- Verified live contracts, copied from the Go source:
  - `PATCH /rides/:id/cancel` body `{"canceled_by_user_id": "<uuid>", "actor_type": "rider", "reason_id": "<uuid, optional>"}`; errors: `ILLEGAL_TRANSITION` (bad state / completed), `RIDE_NOT_FOUND`, `VALIDATION_FAILED` (reason issues); 200 → `{"message": "Ride cancelled"}`.
  - `GET /cancellation-reasons` — actor-scoped rows; row id feeds `reason_id`.
  - `POST /scheduled-rides` body `{"pickup_lat", "pickup_lng", "dropoff_lat", "dropoff_lng", "requested_pickup_time": "<RFC3339>", "vehicle_category_id": "<uuid, optional>"}`; server enforces pickup ≥ 30 min ahead (`VALIDATION_FAILED` with exact copy "pickup time must be at least 30 minutes in the future"); 201 → the scheduled ride row.
  - `GET /scheduled-rides` (list, enriched), `DELETE /scheduled-rides/:id` (cancel).
- `canceled_by_user_id` = the Supabase user id (`TokenStore`/Supabase `currentUser.id`), NOT anything from RiderProfile.
- Server-owned copy verbatim; `Result<T>`; `Pence` for money; TDD; PowerShell; targeted test runs, full suite at the end.
- Existing helpers: `ApiClient.get/post/patch/delete`, `RiderErrorCopy.messageFor`, route constants in `AppRoutes`.

---

### Task 1: Cancel Ride actually cancels

**Files:**
- Create: `app/lib/features/trip/data/ride_actions_repository.dart`
- Modify: `app/lib/features/trip/presentation/live_trip_screen.dart` (`_confirmCancel`, ~line 137)
- Test: `app/test/features/trip/data/ride_actions_repository_test.dart` (create), `app/test/features/trip/presentation/live_trip_screen_test.dart` (extend)

**Interfaces:**
- Consumes: `ApiClient` (`apiClientProvider`), Supabase user id via `Supabase.instance.client.auth.currentUser?.id` — expose it through the repository constructor as a `String? Function()` so tests inject it.
- Produces: `rideActionsRepositoryProvider`; `Future<Result<void>> cancelRide(String rideId)`; the live trip screen calls it on confirm, shows the server error verbatim on failure, and on success `context.go(AppRoutes.home)` with a "Ride cancelled" SnackBar.

Repository shape:

```dart
class RideActionsRepository {
  final ApiClient _api;
  final String? Function() _userId;
  const RideActionsRepository(this._api, this._userId);

  Future<Result<void>> cancelRide(String rideId) async {
    final userId = _userId();
    if (rideId.isEmpty || userId == null) {
      return const Err(ApiException(
          'VALIDATION_FAILED', 'This ride could not be cancelled.', 0));
    }
    final result = await _api.patch<Map<String, dynamic>>(
      '/rides/$rideId/cancel',
      body: {'canceled_by_user_id': userId, 'actor_type': 'rider'},
    );
    return switch (result) {
      Ok() => const Ok(null),
      Err(:final error) => Err(error),
    };
  }
}
```

Tests: repository sends exactly that body and path (capture the mock); an
`ILLEGAL_TRANSITION` error surfaces unchanged. Screen: confirming the dialog
calls `cancelRide` once; declining calls nothing; success leaves the trip
screen; failure shows the server message and stays.

Steps: failing tests → red → implement → green → commit
`fix: Cancel Ride sends the cancellation and leaves the trip`.

---

### Task 2: Schedule screen has an exit

**Files:**
- Modify: `app/lib/features/scheduling/presentation/schedule_ride_screen.dart`
- Test: extend its existing test file.

The screen is a sheet-over-map like home but is PUSHED — it needs a close
affordance. Add the same circled X used by route entry's AppBar (copy that
pattern) positioned top-right over the map, `onPressed: () =>
Navigator.of(context).maybePop()`. Test: pump inside a two-route GoRouter
(same pattern as the settings navigation test), tap the close icon, assert
the previous screen is back.

Commit: `fix: the schedule screen can be left the way it was entered`.

---

### Task 3: Scheduled rides are real

**Files:**
- Create: `app/lib/features/scheduling/data/scheduled_rides_repository.dart`
- Modify: `app/lib/features/scheduling/presentation/schedule_ride_screen.dart`
- Test: `app/test/features/scheduling/data/scheduled_rides_repository_test.dart` (create), the screen's test file (extend)

**Interfaces:**
- Consumes: `ApiClient`; `ChosenRoute` (route entry, Task 1 of the booking plan) for coordinates; `vehicleCategoriesProvider` for the category.
- Produces: `scheduledRidesRepositoryProvider` with:
  - `Future<Result<ScheduledRide>> create({required LatLng pickup, required LatLng dropoff, required DateTime pickupTime, String? vehicleCategoryId})` — POSTs the contract body, `requested_pickup_time` in `pickupTime.toUtc().toIso8601String()`.
  - `Future<Result<List<ScheduledRide>>> list()`
  - `Future<Result<void>> cancel(String id)` — DELETE.
- `ScheduledRide` model mirrors the enriched list row: id, pickup/dropoff labels+coords when present, requested_pickup_time, status, fare when present. Parse defensively (`tryFromJson`, drop rows with no id) like `PlaceSuggestion`.

Screen wiring: "Choose a date and time" opens the existing picker; From/To
fields push route entry for coordinates (reuse `ChosenRoute` via
`context.push(AppRoutes.route)` result or an inline copy of the field
pattern — match what the screen already stubs); a Schedule button submits
and renders the server's own validation copy verbatim on rejection (the
30-minute rule especially); below, the rider's scheduled rides list with a
cancel affordance per row. Follow the frame `Schedule Ride.png` for layout.

Tests: repository body/path capture incl. RFC3339 UTC format; a
`VALIDATION_FAILED` on a too-soon time surfaces the server copy; list
parses the enriched row and drops idless rows; screen submits and renders
the created state.

Commit: `feat: scheduled rides are booked, listed and cancellable for real`.

---

### Task 4: Ride context repository — the trip screen stops pretending

**Files:**
- Create: `app/lib/features/trip/data/ride_context_repository.dart`
- Modify: `app/lib/features/trip/presentation/live_trip_screen.dart` (`liveTripInfoProvider`), `app/lib/features/trip/data/live_trip_source.dart` (parsing stays; the fake stream goes)
- Test: `app/test/features/trip/data/ride_context_repository_test.dart` (create); live trip screen tests keep passing.

**Interfaces:**
- Consumes: `ApiClient`; `LiveTripInfo.fromJson` already in `live_trip_source.dart` (parsing exists, lines ~220–247).
- Produces: `rideContextRepositoryProvider`; `Stream<LiveTripInfo> watch(String rideId)` that polls `GET /rides/:id` at the documented 1 Hz fallback cadence (SSE/FCM come later — the poll is the documented fallback transport, not an invention), emitting parsed `LiveTripInfo`; on fetch error emits the previous value or `LiveTripInfo.awaiting`. `liveTripInfoProvider` switches from `LiveTripSource` to this.

Tests: a 200 with a driver renders driver name through the provider; while
`driver` is null the awaiting state shows; a transport error degrades to
awaiting (existing behaviour preserved).

Commit: `feat: the live trip screen watches the real ride`.

---

### Task 5: Ride Details card and payment sheet to the frame

**Files:**
- Modify: `app/lib/features/history/presentation/ride_details_screen.dart` (or the trip-details sibling the frame maps to — whichever renders mid-ride details; verify with the router)
- Create: `app/lib/features/payments/presentation/widgets/payment_method_sheet.dart`
- Test: goldens + widget tests per screen convention.

Ride Details per `Ride Details.png`: dark rounded route header (pickup/stop/
dropoff rows with icons), floating card — driver row (avatar/initials, name,
rating ★ count, vehicle thumbnail slot), spec rows (Complete Rides, Driver
Review, Vehicle Number, Vehicle Type, Capacity) fed from `LiveTripInfo`,
fare section (Base Fare, Surge multiplier row only when the field is
non-null, Total), the rider's real default card chip, navy full-width
Cancel Booking pill wired to Task 1's `cancelRide`. Null-driver renders the
same card with the awaiting row — no fabricated driver, ever.

Payment sheet per `Select Payment Method.png`: header, the rider's real
saved cards from the payments repository with brand icon + masked digits +
tick on default; PayPal and Wallet rows drawn but visibly "Soon"-disabled
(no backend — cards only, per rider-app-backend-truths). Opening it from
the fare screen's card icon button replaces that button's dead `onTap`.

Golden-beside-frame at 430 AND 320 before calling either done; sample frame
pixels for the dark header and chip colours.

Commit: `feat: ride details and payment sheet match the frames`.

---

### Task 6: Verification

Full suite → analyze → regen affected goldens (LOOK at them beside the
frames) → web rebuild with dart-defines → commit goldens → push.
