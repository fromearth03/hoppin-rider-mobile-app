# Hoppin Rider App — Milestone 1 Design Spec

**Date:** 2026-08-30 · **Status:** awaiting review
**Platform:** Flutter (iOS · Android) · **State:** Riverpod
**Backend:** `Go_ride_service` at `https://api.hoppin.tech`, routes under `/api/v1`

---

## 1. What this document is

The design authority for milestone 1 of the rider app. The Figma pack
(`passenger view Super FINAL`, 29 boards, 430×932) is a visual reference that this
spec supersedes where the two disagree.

Every screen below is bound to an endpoint verified by reading merged handlers in
`Go_ride_service`, not by trusting handover docs. This distinction is load-bearing:
the handover docs and `SCREEN-API-MATRIX.md` were found wrong on fifteen counts
during this design (see §9), and one of the backend's own source comments
contradicts its implementation (§10.2). **Where a comment and an implementation
disagree, read the implementation.**

### Standing rules

1. **The backend is the source of truth.** A screen with no endpoint behind it is
   not built. A *row* whose field the API does not return is not rendered — not
   filled with a zero, a placeholder, or a guess.
2. **Figma values are placeholders.** Bind them to real fields. Only rows with no
   backing field at all are dropped.
3. **Server-owned copy is rendered verbatim.** Anything stating a charge, a refusal
   or its reason is printed as received, never synthesised. This is not stylistic —
   `ACCOUNT_NOT_ELIGIBLE` carries two unrelated meanings distinguished only by the
   server's message (§6.1).
4. **Money is never a `double`.** A `Pence` value type wrapping `int`, formatted
   only at render.
5. **Models mirror Go structs exactly.** If the Go struct has no field, the Dart
   class has no field — the compiler enforces rule 1.
6. **No fakeness.** Nothing stubbed, mocked or faked. A screen that cannot be
   finished properly is out of the milestone, not shipped hollow.

---

## 2. Scope

Production build. Milestone 1 is the **ride loop end to end**, at production
quality. Later milestones add remaining screens without rewriting anything.

### In — 19 screens

| Group | Screens |
|---|---|
| Auth | Login · Sign Up |
| Booking | Home map · Route entry · Vehicle select · Fare details · Default card · Confirm booking |
| Active ride | Matching · Driver assigned · Driver arriving · Trip in progress · Trip complete + receipt · Rate driver |
| Support | Cancel ride · Chat · SOS |
| States | Booking refusals (§6.1), force-update / maintenance |

### Out — later milestones

Ride history · notifications centre · promotions · settings · help & support ·
saved locations · scheduled rides · activity feed (`/me/activity`) · personal
information · delete account.

### Cut entirely — no backend

Wallet (no in-app wallet exists; refunds return to the card) · PayPal · choose-your-driver
(dispatch returns one match) · in-app password reset (stays on the email side) ·
chat attachments, voice notes, presence, typing indicators · turn-by-turn
instruction banner · tipping · referrals · per-ride payment method choice ·
City field on personal info.

---

## 3. Architecture

Feature-first: a feature's screen, state and data live together, so a change is
local rather than spread across layer folders. Matches the driver app's house style.

```
lib/
├── main.dart
├── app.dart                        # MaterialApp, router, theme
│
├── core/
│   ├── api/
│   │   ├── api_client.dart         # Dio + auth + device-id interceptors, envelope parsing
│   │   ├── api_exception.dart      # {code, error, …extras} → typed failure
│   │   └── error_codes.dart        # rider-reachable codes → copy (§6)
│   ├── auth/
│   │   ├── auth_repository.dart    # Supabase GoTrue, session claim, refresh
│   │   ├── auth_state.dart
│   │   └── token_store.dart        # secure storage
│   ├── push/
│   │   ├── fcm_service.dart        # token registration, foreground/background
│   │   └── push_payload.dart       # typed ride_update payload
│   ├── device/device_id.dart       # stable X-Hoppin-Device-ID
│   ├── money.dart                  # Pence value type
│   ├── result.dart                 # Result<T> = Ok | Err
│   └── theme/                      # colors, typography — light AND dark
│
├── features/
│   ├── auth/                       # login, signup
│   ├── booking/                    # map, route, vehicle, fare, card, confirm
│   ├── trip/                       # live-trip engine + trip screens
│   ├── chat/                       # in-ride messaging
│   └── safety/                     # SOS, emergency contacts, share link
│
└── shared/
    ├── nav/                        # go_router config
    └── widgets/
```

**Stack:** `flutter_riverpod` ^2.5.1 · `dio` ^5.4.0 · `go_router` ^14.2.0 ·
`supabase_flutter` ^2.8.0 · `intl` ^0.19.0 · `google_maps_flutter` ·
`flutter_stripe` · `firebase_messaging` · `sentry_flutter`.
Dev: `flutter_lints` ^4.0.0 · `mocktail` ^1.0.3.

### 3.1 API client

`Result<T>` rather than exceptions, so callers handle failure where it happens.
Non-2xx passes through Dio so the `{error, code}` envelope parses rather than
throwing; extra top-level keys (`reason`, `blockers`, `seconds`) are preserved on
the exception.

Two interceptors, both mandatory:
- `Authorization: Bearer <jwt>` from the token store
- `X-Hoppin-Device-ID` — a stable per-install identifier. **The device blacklist
  gate is skipped entirely when this header is absent**, so omitting it silently
  disables a security control.

Base URL `https://api.hoppin.tech/api/v1`.

---

## 4. Auth

Supabase `supabase_flutter` calls GoTrue directly. `Go_ride_service` has no auth
routes — it only verifies the JWT. A DB trigger mirrors `auth.users` into
`public.users` + `rider_profiles`.

**Screens:** Login (`signInWithPassword`), Sign Up (`signUp` with `full_name`;
phone optional; **date of birth required** — see §4.4). Password reset fires
`resetPasswordForEmail` and ends at "check your inbox" — the reset itself happens
in the browser. Reset is out of milestone 1.

### 4.1 Three backend behaviours the app must respect

**Single session.** `SingleSessionGate` keeps one live session per rider. After
login the app **must** `POST /me/session` to claim it; otherwise a previously
signed-in device keeps winning. Any request carrying a superseded session gets
`401 SESSION_REPLACED` — the app signs out cleanly and returns to login. It must
not attempt a token refresh loop.

**Device blacklist.** `DeviceBlacklistGate` checks `X-Hoppin-Device-ID` against
`device_fingerprints`. Returns `403 DEVICE_BLACKLISTED` when blocked, and
`503 DEVICE_STATUS_UNAVAILABLE` when the lookup itself fails — both need real
states. Fail-open on a missing header, fail-closed on a DB error.

**Account status.** `AccountStatusGate` rejects banned/suspended users on a
still-valid JWT, so a suspension takes effect immediately rather than at expiry.

### 4.2 Launch sequence

1. `GET /api/v1/app-status?platform=ios|android&version=<semver>` — **public,
   before login.** Force-update and maintenance screens. Honoured on every cold
   start.

   > **`platform` is required.** A bare call returns `400 VALIDATION_FAILED`
   > ("platform must be 'ios' or 'android'") — `ride_handler.go:1416-1420`.
   > An earlier draft of this spec described it as parameterless, which would
   > have failed on every launch. Verified live 2026-08-31.
2. Restore session from secure storage.
3. `POST /me/device` — device check-in.
4. `POST /me/session` — claim the single session.
5. `POST /me/device-tokens` — register FCM token.
6. `GET /me/active-ride` — if a ride is live, route straight to the trip screen.

### 4.3 Date of birth at signup

DOB is **required** on the sign-up form. Decision recorded 2026-08-30.

**Why it has to be collected.** `users.date_of_birth` is nullable and the booking
guard treats **no DOB as allowed** — so without collection the under-13 gate never
fires and the age restriction is unenforced. Collecting it is what makes the gate
real.

**It is a two-step write, and the gap matters.** Supabase `signUp()` has no DOB
field; `date_of_birth` lives on `PATCH /me/profile`. So:

1. `supabase.auth.signUp(email, password, data: {full_name})` — the DB trigger
   creates `public.users` + `rider_profiles`
2. `PATCH /me/profile { "date_of_birth": "YYYY-MM-DD" }`

If step 2 fails the account exists with a null DOB — and a null DOB books freely.
The app therefore **retries the PATCH on next launch whenever `/me/profile`
returns `date_of_birth: null`**, blocking entry to the app until it succeeds.
An account is not considered fully registered until its DOB is stored.

**Client-side age check.** The server accepts any valid past date at PATCH and only
refuses at booking (`403 ACCOUNT_NOT_ELIGIBLE`, "riders must be 13 or older").
The app rejects an under-13 date **at the signup form**, before creating the
account. Letting someone register, add a card, then discover at booking that they
cannot ride is a worse experience than telling them immediately. The server gate
remains the authority — the client check is a courtesy, not a substitute.

**Validation, mirroring the server** (`profile_handler.go:70-82`): format
`YYYY-MM-DD`, must parse, must be in the past, year ≥ 1900. Plus the client-only
rule: age ≥ 13. On a server rejection, render its message verbatim
(`"date_of_birth must be a valid past date (YYYY-MM-DD)"`).

**Input control:** a date picker, not a free-text field — it makes the format
unrepresentable-if-wrong and avoids locale ambiguity between `DD/MM` and `MM/DD`.
Default the picker to a plausible adult year rather than today, so reaching a real
birth date is a short scroll.

### 4.4 The role claim

The Supabase `custom_access_token_hook` is now **enabled**, so riders carry
`user_role` in the JWT. `riderOnly()` on the backend rejects only
`role == "driver"`. The app still branches on nothing client-side — being signed
in is the only auth state the UI needs.

---

## 5. The live-trip engine

The one genuinely hard component. Isolated as its own unit under `features/trip/`,
owning transport, the state machine and the map marker. Everything else in the app
is CRUD by comparison.

### 5.1 Three transports, three jobs

These are not alternatives. The backend implements all three and each carries
different data.

| Transport | Carries | Endpoint |
|---|---|---|
| **FCM push** | ride *status* changes | `ride_update` payload `{type, ride_id, deep_link, status, notification_id}` |
| **SSE** | driver *position* | `GET /api/v1/rides/:id/driver-location/stream` |
| **Poll (~1 Hz)** | driver *position*, fallback | `GET /api/v1/rides/:id/driver-location` |

**FCM** works while backgrounded and is best-effort — failures are logged only — so
it is an enhancement, never the sole source of truth.

> **The push is a doorbell, not a delivery.** The payload carries `status`, and the
> backend offers it so clients can skip a re-fetch. We do not take that offer.
> A push can arrive late, duplicated, or out of order; rendering its `status` lets a
> stale push walk the UI backwards through the state machine. The typed payload
> therefore keeps **routing data only** — `type`, `ride_id`, `deep_link` — and every
> push triggers a `GET /rides/:id`. The push says something happened; the endpoint
> says what. This matches the driver app's `PushPayload` convention.
>
> The backend duplicates payload keys in both snake_case and camelCase.
> **snake_case is canonical**; read camelCase only as a fallback.

**SSE** is NATS-backed, sends one immediate fix on connect so the marker draws
without waiting, and emits a 25 s keepalive comment. It emits the **identical**
`DriverLocationView` shape as the poll, so one parser serves both. Not under the
header-auth group: `EventSource` cannot set headers, so the JWT goes as `?token=`
and is verified in the handler, which then applies the same participant check.

**Poll** is the documented reconnect fallback. If NATS is unavailable the SSE hub
stays empty and clients degrade to polling — which is why the poll is not optional.

Reconnect policy: exponential backoff on the stream; fall back to the poll while
disconnected; resume the stream when it recovers. Suspend both while backgrounded.

### 5.2 State machine

`matching → accepted → arriving → started → completed`, plus `cancelled` from any
non-completed state. `requested` and `assigned` are dead states, never written —
no UI for them.

`driver` is `null` while matching. That is the searching state, **not** an error.

### 5.3 One call renders the trip screen

`GET /api/v1/rides/:id` returns everything: existing ride keys plus `ref`, `geo`
(pickup, dropoff, readable waypoints, real OSRM road polyline), `driver` (identity,
rating, trips count, vehicle, live OSRM `eta_seconds`), `fare`, `timestamps`, and
`chat_unread`. Verified in `rider_ride_detail.go:70-80`.

No fan-out to `/geo` + `/driver-info`. No client-side aggregate.

---

## 6. Errors

Envelope is `{"error": "<message>", "code": "<CODE>"}`. **Map on `code`; display
the server's `error` string.** There is no rider error-code reference from the
backend — the table below was derived by reading handlers.

### 6.1 Booking refusals — `ride_handler.go:830-844`

| Code | HTTP | Server copy | Screen action |
|---|---|---|---|
| `ACCOUNT_NOT_ELIGIBLE` | 403 | "account is not active" | Contact support |
| `ACCOUNT_NOT_ELIGIBLE` | 403 | "riders must be 13 or older" | Age gate |
| `ACTIVE_TRIP_EXISTS` | 409 | "you already have an active trip" | Route to the live trip |
| `OUTSIDE_SERVICE_AREA` | 422 | "Hoppin is not available at this pickup location" | Move the pin |
| `NO_PAYMENT_METHOD` | 402 | "add a payment card to book a ride" | Add-card flow |
| `NO_ZONE` | 422 | "pickup is outside every configured pricing zone" | Move the pin |
| `NO_TARIFF` | 422 | "this zone has no active tariff configured" | Try again later |
| `IDEMPOTENT_REPLAY` | 409 | "idempotency key already used" | Treat as success |

> **`ACCOUNT_NOT_ELIGIBLE` is overloaded** — one code, two unrelated meanings,
> separable only by the server's message. This is why rule 3 exists.

**Age gate:** riders under 13 cannot book. `date_of_birth` is nullable and **no DOB
means allowed** — the gate only bites once the app collects it. Collecting DOB at
signup is therefore a compliance decision, not a UI one. *Open item — see §10.*

### 6.2 Promotions — `chat_handler.go:227-248`

`PROMO_NOT_FOUND` 404 · `PROMO_INACTIVE` 400 · `PROMO_EXHAUSTED` 409 ·
`PROMO_USED` 409 · `PROMO_INELIGIBLE` 400 · `PROMO_NOT_FOR_RIDERS` 400 ·
`PROMO_NO_FARE` 409 · `PROMO_MIN_RIDE` 400 · `PROMO_NEW_USERS_ONLY` 400 ·
`PROMO_BUDGET_EXHAUSTED` 409 · `PROMO_WRONG_ZONE` 400.

### 6.3 Global

`VALIDATION_FAILED` 400 · `FORBIDDEN` 403 · `RIDE_NOT_FOUND` 404 ·
`INTERNAL` 500 (retry with backoff) · `SESSION_REPLACED` 401 ·
`DEVICE_BLACKLISTED` 403 · `DEVICE_STATUS_UNAVAILABLE` 503 ·
`ACCOUNT_SUSPENDED` / `ACCOUNT_BANNED` 403.

Live-map: `NO_DRIVER_ASSIGNED` 409 (still matching — not an error) ·
`RIDE_NOT_ACTIVE` 409 · `POSITION_UNAVAILABLE` 409 (retry later) ·
`SHARE_LINK_INVALID` 404.

`VEHICLE_CATEGORY_MISMATCH` is **driver-reachable only** — it fires on accept and
arrive. A rider JWT cannot reach it, despite the driver doc listing it as rider-only.

---

## 7. Screens → endpoints

### 7.1 Booking

| Screen | Endpoints |
|---|---|
| Home map | `GET /service-areas`, `GET /vehicle-types` |
| Route entry | `GET /geocode/search` — see §7.1.1 · `GET /geocode/reverse` · `GET /me/saved-locations` |
| Vehicle select | `GET /vehicle-types` — see §7.1.2 |
| Fare details | `POST /rides/estimate` — one call, see below |
| Default card | `GET /me/payment-methods`, `POST /me/payment-methods/setup-intent`, `POST /me/payment-methods/:pmId/default` |
| Confirm booking | `POST /rides/request` → `202 {request_id}` |

#### 7.1.1 Route entry — address autocomplete

**Forward search works.** Verified at `service/geocode_search.go:16-104`. A comment
in `ride_handler.go:104-105` claims otherwise and is stale — see §10.2. Route entry
is a **search field**, not a map-pin picker. The pin picker remains as a secondary
way to set a point, backed by `/geocode/reverse`.

`GET /api/v1/geocode/search?q=&lat=&lng=&limit=` →
`{"results": [...], "query": "..."}`

```jsonc
{ "label": "Molineux Stadium, Waterloo Road, Wolverhampton",
  "lat": 52.590, "lng": -2.130,
  "postcode": "WV1 4QR",   // omitted when empty
  "source": "saved" }      // "saved" | "map"
```

**Behaviour, and what the client must honour:**

- **Minimum query is 2 characters.** Below that the server returns `[]` — not an
  error. Do not call until the field holds 2+ characters.
- **Maximum 8 results**, which is also the default. `limit` above 8 is clamped.
- **`lat`/`lng` bias results, they do not bound them.** Pass the rider's position
  when available. Bounding is explicitly rejected upstream: someone booking to
  Birmingham Airport must not get zero results.
- **`source` distinguishes a saved place from a map hit** — style them differently.
  Saved places match first and always win; Photon fills the remainder.
  Deduplicated on coordinates to 5 decimal places.
- Debounce keystrokes (~250 ms). Photon carries a 4 s server-side timeout, so the
  client timeout must exceed that or it will cancel work the server would have
  completed.

> **An empty result set is ambiguous.** If Photon is unreachable the server returns
> the rider's saved places alone — silently, with no error and no flag. So `[]` can
> mean "no such place" or "the geocoder is down". Copy must not assert that no
> such place exists; "No matches — try a different search" is honest where
> "That place doesn't exist" is not.

Photon is used rather than Nominatim because Nominatim matches whole tokens, so
"molin" returns nothing where Photon returns Molineux. The app never talks to
Photon directly — the ride service fronts it, so the geocoder can be swapped
without an app release.

#### 7.1.2 Vehicle categories

`GET /api/v1/vehicle-types` → `{"vehicle_types": [...]}`. Verified at
`app_catalog_repo.go:225-236`. **Five fields, and no more:**

```jsonc
{ "id": "uuid", "name": "Standard",
  "seats": 4, "bags": 2,
  "price_multiplier": 1.0 }
```

- Filtered on `is_active` — a deactivated category (e.g. the old `testop` row)
  never appears. The client does no filtering of its own.
- **Ordered by `price_multiplier`, then `name`** — cheapest first. Render in the
  order received; never re-sort.
- `price_multiplier` is how the picker conveys relative cost before the estimate
  call resolves. Not previously documented anywhere.
- `seats`/`bags` are `COALESCE`d to `0`. A category configured with neither shows
  no seats/bags row rather than "0 Seats" (rule 1).

**There is no image, icon or description field.** The Figma draws an illustration
per category; the API cannot supply one. The app therefore ships **local assets
keyed by category `name`**, with a generic vehicle fallback for any name it does
not recognise — because categories are admin-editable, a new one can appear at any
time without an app release. The fallback is a designed state, not a placeholder.

**Live categories** (2026-08-27 verification): Standard 4s/2b · Estate 5s/4b ·
MPV 7s/5b · Minibus 8s/6b · MiniCar 4s/2b · MiniTruck 7s/2b. Six real categories,
where the Figma drew four. Figma disagrees on several counts (Estate 4/4, MPV 6/4,
Minibus 16/12) and omits MiniCar and MiniTruck entirely.

**Render API values, never Figma values.** Where the two disagree the data is
authoritative for the app — and because `vehicle_categories` is admin-editable, a
genuinely wrong row is fixed in the admin panel, not in this codebase. See §10.1.

**Per-ride payment choice does not exist.** Booking always charges the default
card, so this screen is *"set your default card"* and must be worded that way.

**`POST /rides/estimate` is the only pricing call.** It returns the fare
breakdown, distance, duration, the road polyline for the preview map, the
cancellation policy and the ETA tier — in one response.

> **Never call the dispatch engine (`:8081`) from the app.** Its README states it
> is not client-facing, and the ride service already asks it for the corrected
> trip ETA internally so the quote and the eventual charge price off identical
> numbers. Raw OSRM under-predicts local trips by ~40%, which previously showed
> as a 7% gap between quote and offer. An earlier draft of this spec had the app
> calling `:8081/quote` for a richer breakdown; that was wrong.

**Surge:** admin-set multiplier, real, rendered as designed. There is no demand
map for riders — `GET /demand-heatmap` exists but is a driver-facing overlay.

**Zone discount** (2026-08-30). An admin can set an automatic percentage discount
on a zone; a ride is "in" a zone by its **pickup**. Applied inside the shared fare
engine, so estimate, charge, driver earnings and dispatch offer all reflect it
identically — **totals are correct with no app change**.

Optionally displayable: the `estimate` breakdown carries `gross`, `discount_pct`,
`discount` and `total`, so a "Zone discount −£2.40 (20%)" line is possible.
`discount_pct: 0` means none. Zone discounts **stack** with promo codes — the
discount is baked into the fare, a promo is subtracted on top.

**Promo codes can be zone-scoped**, which adds an eleventh promo error:
`400 PROMO_WRONG_ZONE`. Note the ordering trap: **`GET /promotions/validate` has
no pickup context**, so a code can validate successfully and still fail with
`PROMO_WRONG_ZONE` when applied to a ride. Both paths need handling; a successful
validate is not a guarantee.

### 7.2 Active ride

| Screen | Endpoints |
|---|---|
| Matching | `GET /rides/:id` (`driver: null`) |
| Driver assigned / arriving / in progress | `GET /rides/:id` + SSE stream + poll fallback |
| Cancel | `GET /cancellation-policy`, `GET /rides/:id/waiting-policy`, `GET /cancellation-reasons`, `PATCH /rides/:id/cancel` |
| Complete + receipt | `GET /rides/:id/receipt` |
| Rate driver | `POST /rides/:id/rating` |

Receipt returns `ride_id, ride_category, fare_pence, waiting_pence, total_pence,
currency, status, distance_miles, pickup_time, dropoff_time, provider_payment_id`.
`platform_commission_pence` was **removed** — it leaked the platform/driver split.
Do not render it.

Show `ref` (`R-1042`), never the UUID.

### 7.3 Chat

`POST /rides/:id/messages` (accepts `reply_to_id`) · `GET /rides/:id/messages?since=`.
Each message carries `status` on your own messages (`sent` → `read`) and a
`reply_to` preview when it is a reply. Opening the thread marks read and clears
`chat_unread` on `GET /rides/:id`.

Text only. Polling with a `since=` cursor. Scoped to an active ride — not a
standalone inbox.

### 7.4 Safety

`POST /me/sos` · `GET /me/sos` · `GET|POST|DELETE /me/emergency-contacts` ·
`POST|DELETE /rides/:id/share-link`. Support and emergency numbers come from
`GET /contacts` (public, admin-editable live, so a number change needs no release).

> **SOS is real.** It writes a row and surfaces on the admin safety dashboard.
> Firing it in a demo raises a genuine alert. Confirmed acceptable by the product
> owner, 2026-08-30.

---

## 8. External services

| Service | Use | Notes |
|---|---|---|
| **Google Maps** | **Rendering only** — map, route polyline, driver marker | Geocoding stays on the backend's Photon/Nominatim. Needs a Maps SDK key per platform with billing enabled. |
| **Stripe** | Card management, test mode | SDK card element via `setup-intent` → `clientSecret`. **Never raw card fields** — that is the difference between PCI SAQ A and SAQ A-EP. Publishable key ships as a `--dart-define`. |
| **Supabase** | Auth only | Client SDK direct to GoTrue. |
| **FCM** | Ride status push | Token registered after login. |
| **Sentry** | Crash and error reporting | From day one. |

Payment DTOs are **camelCase** (`{paymentMethodId, brand, last4, expMonth,
expYear, isDefault}`) while the rest of the API is snake_case — a deliberate
one-off mapping.

Card `brand`/`last4` **are** available (migration 117) on both
`GET /me/payment-methods` and `GET /me/transactions`.

---

## 9. Corrections to prior documentation

`SCREEN-API-MATRIX.md` and the 08-27 handover were verified wrong on these points.
Recorded so the errors are not re-inherited.

| Prior claim | Verified reality |
|---|---|
| "No WebSocket, no SSE — confirmed absent" | **SSE exists** — `ride_location_stream.go`, NATS-backed, built to replace the 1 Hz poll |
| Trip screen needs 3 calls; build a client aggregate | One call — `rider_ride_detail.go:70-80` |
| `/driver-info` returns 409 during matching | `driver: null`; a normal state |
| FCM carries no status | Payload carries `status` |
| Waypoints write-only, lost on reload | Readable |
| Route is straight-line | Real OSRM road polyline; live OSRM ETA |
| JWT role resolves to `"authenticated"` | Hook enabled; `user_role` present |
| Under-18 age gate | **Under-13**, and only when DOB is collected |
| Receipt carries `platform_commission_pence` | Removed |
| Device gate is "the one fail-closed gate" | Fail-**open** on a missing header; fail-closed only on DB error |
| Single-session behaviour | Not mentioned at all; `SESSION_REPLACED` must be handled |
| `app-status`, `contacts` | Not mentioned; both are launch-path endpoints |
| `VEHICLE_CATEGORY_MISMATCH` is rider-only | Driver-only |
| No demand heatmap endpoint | `GET /demand-heatmap` exists (driver-facing) |
| Forward geocode search unavailable; drop a pin instead | **Forward search works** — `geocode_search.go` fronts Photon for prefix matching. The contradicting comment is stale (§10.2) |
| `/vehicle-types` returns seats and bags | Also returns `price_multiplier`, and results are ordered by it |

---

## 10. Open items

### 10.1 Minibus seats/bags — an ops fix, not a build decision

Live API says Minibus is 8 seats / 6 bags; the Figma draws 16/12. Estate and MPV
also disagree.

**This does not block the build.** The app renders API values either way (rule 1),
so it is correct with respect to its data at all times. `vehicle_categories` is
**admin-editable**, so if a row is genuinely wrong the fix is one edit in the admin
panel — no app release, no code change, no migration.

What is needed is someone who knows the fleet confirming which numbers are true.
Until then the app shows 8/6 and is not wrong to. Open since 2026-08-27.

### 10.2 Resolved

- **DOB at signup** — resolved 2026-08-30: collect it, required, with a
  client-side under-13 check. See §4.3.
- **`/geocode/search`** — resolved 2026-08-30 by reading
  `service/geocode_search.go`. **Forward search works**; the contradicting comment
  at `ride_handler.go:104-105` is stale. Route entry is a search field. Contract
  and behaviour in §7.1.1.

## 11. Dependencies on the product owner

Google Maps API key (billing enabled, per platform) · Stripe test publishable key ·
Sentry project DSN · Apple Developer account (signing, TestFlight) · Play Console
access · Supabase project facts as they arise.

## 12. Production readiness

In scope for milestone 1: Sentry · analytics (funnel events) · CI (tests and build
artifacts on push) · store readiness (icons, splash, bundle IDs, signing,
TestFlight / Play internal track).

### 12.1 Theme

**Light and dark from the start**, per the standing design preference. This
diverges from the driver app, which ships light only on the reasoning that drivers
use it in a car in daylight — a rider is as often in a dark cab at night, so dark
mode is not optional here. The backend also stores a `theme` preference
(`system|light|dark`) on `/me/preferences`, so the choice is persisted server-side.

**Shared brand tokens**, adopted from the driver app so both apps read as one
product. Never write a raw `Color()` in a widget.

| Token | Value | Use |
|---|---|---|
| `primary` | `#2E0B78` | deep indigo |
| `primaryDark` | `#1E0550` | |
| `accent` | `#F07A21` | orange, primary actions |
| `background` | `#F5F5F7` | app ground |
| `surface` | `#FFFFFF` | cards |
| `border` | `#E3E3E8` | |
| `textPrimary` | `#1A1A2E` | |
| `textSecondary` | `#6B6B7B` | |
| `textDisabled` | `#A0A0B0` | |
| `positive` | `#2BA84A` | credits, active |
| `negative` | `#D64545` | errors, cancelled |
| `warning` | `#E8A33D` | pending |
| `info` | `#3D7FE8` | |

The dark palette is a second token set in the same file, not a second set of
widgets. Both themes are tested visually before any screen is called done.

## 13. Demo dependency

The demo runs a real ride with a real driver on the driver app (under separate
construction). This means: the driver app must be working on the day, and dispatch
must match *that* driver rather than another who happens to be online. Controlling
which drivers are online at demo time is a demo-day concern that needs an owner —
it is not an app problem and cannot be solved in this codebase.
