# Hoppin Rider — Screen ↔ Backend Matrix

Source of truth: the backend. Figma is "Passenger View Super FINAL" (29 boards,
430×932). Where the design shows something the backend cannot serve, the rule is
**skip it** — do not build a fake.

Backends in play:
- `Go_ride_service` `:8080` — the only Hoppin API the rider app calls. Supabase JWT.
- `Go_Dispatch_Engine` `:8081` — `POST /quote` only. Same rider JWT.
- Supabase GoTrue — all auth. Called by the client SDK, never via Hoppin.
- `hoppin_payment` `:8090` — **unreachable from the app.** Shared-secret only,
  no user identity. Everything is proxied by ride-service.

---

## 1. Auth — no Hoppin endpoints, Supabase SDK only

`086_signup_profile_autocreate.sql:3`: "the mobile rider app calls Supabase
`auth.signUp()` directly." A DB trigger mirrors `auth.users` → `public.users` +
`rider_profiles`, firing only when the signup carries no `role` in metadata.

**Password reset stays on the email side** — the emailed Supabase link handles it
in the browser. The app does not implement the reset chain.

| Screen | Status | Call |
|---|---|---|
| Sign In (signup) | **build** | `supabase.auth.signUp(email, password, data:{full_name})` — trigger creates profile |
| Login | **build** | `supabase.auth.signInWithPassword` |
| Forgot Password | **build** | `supabase.auth.resetPasswordForEmail` — fires the email, then shows "check your inbox". Journey ends there. |
| OTP Confirmation | **DROPPED** | No in-app OTP. Reset happens via the emailed link. |
| Reset Password | **DROPPED** | Handled in the browser off the emailed link. |
| Expired-link | **DROPPED** | Belonged to the in-app reset chain. |

3 auth screens, not 6. No Supabase email-template change needed — the default
link template is what we want.

**Build changes:**
- **Phone Number on signup is optional** — matches current behaviour. Leave the
  field, do not require it. When blank the trigger writes the
  `phone_number = 'pending-<uid>'` placeholder, and `/me/profile` hides it as `""`.
  When filled, pass it to `signUp(phone:)`. Note it is globally UNIQUE — a number
  already held by another account surfaces as `409 PHONE_TAKEN` on later edit.
- **Drop the line "Login using your credentials provided by the company."**
  Invite-flow copy; riders self-signup.
- The 18+ checkbox is client-side only at signup. `users.date_of_birth` exists
  (mig 018) and `CheckRiderEligible` enforces under-18 server-side at booking.
- **Never gate UI on the role claim.** Two different `role` fields exist and they
  do not agree:
  - `public.users.role` — Postgres enum `('rider','driver','admin')`
    (`001_initial.sql:9`); the trigger sets `'rider'`.
  - the **JWT** `role` claim — Supabase's own, `"authenticated"` for any signed-in
    user. Resolution order is `user_role` → `app_metadata.role` → `role`
    (`verifier.go:139`), and a self-signup rider has neither of the first two.

  So the token resolves to `"authenticated"`. `riderOnly()`
  (`ride_handler.go:461`) is lenient by design — it rejects only
  `role == "driver"`. Client-side, branch on nothing.

**Every** authed request needs `Authorization: Bearer <jwt>` and
`X-Hoppin-Device-ID` (DeviceBlacklistGate is the one fail-closed gate).

---

## 2. Booking

| Screen | Endpoints |
|---|---|
| Ride Type (home map) | `GET /api/v1/service-areas`, `GET /api/v1/vehicle-types` |
| Enter Your Route | `GET /api/v1/geocode/search?q=` (returns `source:"saved"\|"map"`, saved ranked first → this **is** the Suggestion/Saved split), `GET /api/v1/geocode/reverse`, `GET/POST/DELETE /api/v1/me/saved-locations` |
| Select Vehicle | `GET /api/v1/vehicle-types` → `seats`, `bags` render "4 Seats 2 Bags" verbatim |
| Ride Details | `POST /api/v1/rides/estimate` |
| Select Payment Method | `GET /api/v1/me/payment-methods` |
| Confirm Booking | `POST /api/v1/rides/request` → `202 {request_id}` |
| Schedule Ride | `POST /api/v1/scheduled-rides`, `GET/DELETE /api/v1/scheduled-rides[/:id]` |

`POST /rides/request` body: `{vehicle_category_id, pickup_lat, pickup_lng,
dropoff_lat, dropoff_lng, waypoints:[{lat,lng}]}`.

Booking errors that need real UI states:
`403 ACCOUNT_NOT_ELIGIBLE|ACCOUNT_SUSPENDED|ACCOUNT_BANNED|DEVICE_BLACKLISTED`,
`409 ACTIVE_TRIP_EXISTS`, `422 OUTSIDE_SERVICE_AREA`, `402 NO_PAYMENT_METHOD`.

**Build changes:**
- **"Choose your driver" — screen dropped.** Dispatch runs Hungarian assignment
  and returns exactly one driver. Confirm Booking goes straight to matching.
- **Per-ride payment selection does not exist.** Booking always charges the
  default card. So "Select Payment Method" is not a booking step — it is
  *"set your default card"*, and must be worded that way. `402 NO_PAYMENT_METHOD`
  blocks booking when no card is set.
- **Waypoints are write-only.** Accepted at booking, never returned by any read
  endpoint (`RideGeoView` has pickup/dropoff only). Multi-stop must be held in
  client state for the life of the booking; after a reload the extra stops are gone.
- Fare breakdown comes from `/rides/estimate` (with `cancellation_policy` inlined).
  `POST :8081/quote` gives the richer breakdown — `{basePrice, distanceFare,
  timeFare, waitingFare, subtotal, surge, weatherMultiplier, trafficMultiplier}` —
  which is what the Figma "Base Fare / Surge 1.5x" card actually needs.
- **Surge is admin-controlled — keep the "Surge 1.5x" row.** Staff set the
  multiplier per category in the admin panel; it does not move on its own. The
  value is real and comes back on the quote breakdown, so render it as designed.
  What does not exist is a *demand map* — no "surge in your area" heat overlay
  (`surge_pricing_polygons` is unread by any service). Show the multiplier, not a map.

---

## 3. Active ride

| Screen | Endpoints |
|---|---|
| Accept Ride (driver details) | `GET /rides/:id/driver-info` |
| Driver Arrived | `GET /rides/:id/driver-location` (~1 Hz), `GET /rides/:id/geo` |
| Start Ride | same + `GET /rides/:id` for status |
| Cancel Ride | `GET /api/v1/cancellation-policy`, `GET /rides/:id/waiting-policy`, `PATCH /rides/:id/cancel` |
| Ride Complete | `GET /rides/:id/receipt`, `POST /rides/:id/rating` |
| SOS button | `POST /me/sos`, `GET/POST /me/emergency-contacts`, `POST /rides/:id/share-link` |

States (`models/ride.go:9`): `matching → accepted → arriving → started →
completed`, plus `cancelled` from any non-completed state. `requested` and
`assigned` are **dead** — never written. Do not build UI for them.

**No WebSocket, no SSE.** Confirmed absent from the codebase. Live updates are:
1. **FCM push** — data `{type:"ride_update", ride_id, deep_link:"/trip/<id>"}`,
   Android channel `ride_alerts`. Carries **no status field**, so every push must
   trigger a re-`GET /rides/:id`.
2. **Polling** — driver location ~1 Hz, chat via `?since=`, notifications as the
   durable catch-up channel (push is best-effort, failures only logged).

**Build changes:**
- `GET /rides/:id` is too thin for the trip screen — 11 fields, **no coordinates,
  no fare**. Rendering one trip screen needs 3 calls: `/rides/:id` + `/geo` +
  `/driver-info`. Build a single `TripSnapshot` aggregate in the repository layer.
- `/driver-info` returns `409 NO_DRIVER_ASSIGNED` during matching — that is the
  searching state, not an error.
- `heading` and `approach` are **always null**. No car-rotation on the map marker.
- Rider-initiated cancel notifies **only the driver** (`ride_service.go:1986`).
  The rider's own confirmation must be local.
- Turn-by-turn ("Take left after 1.5 mi") has **no backend**. `/geo` returns a
  polyline only. Either drop the instruction banner or hand off to the external
  nav app the Settings screen already selects. Do not fabricate instructions.

---

## 4. Account

| Screen | Endpoints |
|---|---|
| Side Nav Bar | `GET /me/profile` |
| Personal Information | `GET /me/profile`, `PATCH /me/profile` (`{full_name, phone_number}`), `POST /me/avatar/upload` |
| Ride History | `GET /rides?limit=` |
| Trip details | `GET /rides/:id/receipt` + `/geo` |
| Payments | `GET /me/transactions` |
| Payment Methods | `POST /me/payment-methods/setup-intent`, `GET /me/payment-methods`, `POST /me/payment-methods/:pmId/default`, `DELETE /me/payment-methods/:pmId` |
| Promotional | `GET /api/v1/promotions`, `GET /promotions/validate?code=`, `POST/GET/DELETE /rides/:id/promo` |
| Notifications | `GET /me/notifications`, `PATCH /me/notifications/:id/read`, `POST /me/notifications/read-all`, `DELETE /me/notifications[/:id]` |
| Settings | `GET /me/preferences`, `PATCH /me/preferences` |
| Help & Support | `POST/GET /me/support-tickets`, `GET /me/support-tickets/:id`, `.../messages` |
| Delete Account | `POST /me/delete-account` |

**Settings maps almost exactly.** Server-owned whitelist
(`preferences_handler.go:22`): `push_trip_updates`, `push_promotions`,
`push_payouts`, `email_receipts`, `sms_trip_updates`, `sound_offer_chime`,
`marketing_consent`, `theme` (`system|light|dark`), `language` (BCP 47).
- "Notification" → `push_trip_updates`
- "Driver Arrived Sound" → `sound_offer_chime`
- "Promotional Offers" → `push_promotions`
- "Appearance" (Dark/Light/Default) → `theme` — exact enum match
- "Language" → `language`
- **"Do not lock the screen"** → no key. Device-local setting (wakelock), keep it
  in local storage.
- **"Distance Units" (Miles/Km)** → no key. Device-local. Note the backend returns
  `distance_miles` on receipts and the design shows "4.7 km" — conversion is
  client-side.
- **"Navigation" (Google/Apple Map)** → no key. Device-local; drives the external
  nav hand-off.

**Build changes:**
- **Ride History and the trip screen need richer responses.** `GET /rides` returns
  the thin 11-field `models.Ride` — no fare, no labels — and `GET /rides/:id` has
  no coordinates or fare either. Contracts requested in
  `docs/handoff/FOR-BACKEND.md`; both are additive, no migrations. Until they
  land, build against those shapes behind the repository layer and stub locally.
- Personal Information: **City** field has no backend column. Drop it.
  `users.address` exists but is not exposed by `/me/profile`.
- Personal Information: the "your name and picture are verified, contact support"
  notice contradicts `PATCH /me/profile`, which lets the rider change their own
  name. Drop the notice or drop the editability — pick one.
- Payment Methods: **use the Stripe SDK card element**, not the raw Card Number /
  CVV / Expiry fields drawn in Figma. Flow is `setup-intent` → `clientSecret` →
  SDK collects the card.

  *On the compliance question:* storage is genuinely clean — only
  `stripe_customer_id` and `default_stripe_payment_method_id` on `rider_profiles`,
  plus the censored `{brand, last4, expMonth, expYear}` Stripe returns. Zero PAN,
  zero CVV in the database.

  But PCI scope is set by what **transits the app**, not by what is persisted. A
  raw card number typed into a `TextField` we control is in our process memory and
  widget tree — that is SAQ A-EP/D territory even when it is POSTed straight to
  Stripe and never stored. The SDK element keeps the PAN out of our code entirely,
  which is **SAQ A**. Since `setup-intent` already returns a `clientSecret`, the
  SDK path is what the backend was built for and costs no extra screens — the
  Figma form is swapped for `CardField`.
- Payment DTOs are **camelCase** (`{paymentMethodId, brand, last4, expMonth,
  expYear, isDefault}`) while everything else is snake_case. One-off JSON mapping.
- Stripe's publishable key sits behind the internal token on `:8090`. Ship it as
  a build-time `--dart-define`, not a fetch.
- Notifications: `read_at` backs the Read/Unread tabs directly. `type` enum is
  `trip|compliance|payout|system`.
- Promotional: Active/Availed/Expired = `user_promo_redemptions` + `expires_at`.
  11 distinct error codes to surface (`PROMO_EXHAUSTED`, `PROMO_MIN_RIDE`,
  `PROMO_NEW_USERS_ONLY`, `PROMO_BUDGET_EXHAUSTED`, …).

---

## 5. Chat

`POST /rides/:id/messages`, `GET /rides/:id/messages?since=<RFC3339>`.
Table `ride_messages` (mig 026): `{id, ride_id, sender_id, sender_role, body, created_at}`.

**Build changes — the Conversation screen is mostly unbacked:**
- **Text only.** `body` is the only content column.
- **Attachments — skip.** No storage, no column.
- **Voice notes — skip.** Same.
- **Online/offline presence — skip.** Not tracked anywhere.
- **Call button — skip or hand off to the OS dialer.** No masked-calling service
  exists. No driver phone number is exposed by `/driver-info`.
- Polling only, `?since=` cursor. No typing indicators, no read receipts.
- Scoped to a ride: chat exists only for an active ride, not as a standalone inbox.

---

## 6. Cut from the build (no backend)

Per the rule — backend is the source of truth.

| Cut | Evidence |
|---|---|
| **Wallet — entirely** (payment-methods row, select-payment row, "refunded in your wallet" notification) | There is no in-app wallet. `rider_wallets` is declared dead in code (`app_catalog_repo.go:151`). Do not build a wallet row, a balance, or a wallet payment option anywhere. `GET /me/credit-balance` exists as an endpoint but has no wallet behind it — **do not wire it**. Refund copy must say the refund goes back to the card. |
| **PayPal** | Stripe only. No PayPal anywhere in `hoppin_payment`. |
| **Choose your driver** (multi-offer) | Dispatch returns one match. Screen dropped by decision. |
| **OTP Confirmation, Reset Password, Expired-link** | Password reset stays on the email side — the emailed link handles it in the browser. No in-app reset chain. |
| **Attachments / voice notes / presence in chat** | `ride_messages.body` is text-only |
| **Turn-by-turn instruction banner** | `/geo` returns a polyline; no instructions |
| **Demand / surge heat map** | `surge_pricing_polygons` unread; no demand route. The admin-set surge **multiplier itself stays** — see Booking. |
| **Tipping** | No tip endpoint on any service. `driver_tips` exists in the live DB but is **empty (0 rows)** and Ryft-shaped. |
| **Referrals** | **`referral_tracking` does not exist in the live DB** (verified 2026-08-27). No referral logic in any service. |
| **Per-ride payment method choice** | Booking uses the default card only |
| **City field on Personal Information** | Not in `/me/profile` |

Kept, previously miscounted as cut: the **phone field on signup** stays (optional),
and the **admin-set surge multiplier** stays.

### Live DB verification — 2026-08-27

Introspected the live Supabase DB (84 public tables). Corrections to earlier
migration-derived claims:

| Table | Migration said | **Live DB** |
|---|---|---|
| `referral_tracking` | exists | **DOES NOT EXIST** |
| `micromobility_assets` / `_rentals` | exist | **DO NOT EXIST** |
| `rider_subscriptions` | exists | **DOES NOT EXIST** |
| `payment_methods` | dropped by 088 | correctly absent |
| `rider_wallets` | exists, dead | exists, **0 rows** |
| `driver_tips` | exists, dead | exists, **0 rows** |
| `surge_pricing_polygons` | exists, unread | exists, **0 rows** |
| `trip_messages` | legacy duplicate | exists, **0 rows** — `ride_messages` is the live one |

Lesson: migrations are append-only, so a table in `001_initial.sql` proves
nothing about today. All table claims in this doc are now live-verified.

**Live row counts** (rider-relevant): `user_notifications` 943 · `rides` 66 ·
`reviews` 24 · `promotions` 10 · `sos_events` 7 · `scheduled_rides` 5 ·
`ride_messages` 2 · `saved_locations` 0 · `ride_waypoints` 0.

**Role, settled.** `user_role` enum is `rider, driver, admin` — no `user` value.
Live counts: driver=32, admin=25, rider=22. Riders do carry `role = 'rider'` in
`public.users`; the gap is only that this never reaches the JWT (see §1).

**Vehicle catalogue differs from Figma.** Live active categories:
Standard (4s/2b) · Estate (**5s/4b**) · MPV (**7s/5b**) · Minibus (**8s/6b**) ·
MiniCar (4s/2b) · MiniTruck (7s/2b) · testop (test row).
Figma shows Estate 4s/4b, MPV 6s/4b, Minibus 16s/12b, and omits MiniCar and
MiniTruck. **Render seats/bags from the API, never hardcode the Figma numbers**,
and expect 6 real categories rather than 4. `testop` should be deactivated before
launch.

All contract columns in `handoff/FOR-BACKEND.md` were confirmed present —
those requests are genuinely additive.

---

## 7. Backend asks

Full schemas in **`docs/handoff/FOR-BACKEND.md`**. Both are additive — no new
tables, no migrations; every field already exists as a column.

1. `GET /rides` — trip-history list-view with labels, fare, driver and `my_rating`.
2. `GET /rides/:id` — add `geo` (incl. readable waypoints), `driver`, `fare`,
   `timestamps`; return `driver: null` while matching instead of `409`.

Lower priority: status in the FCM payload; notify the rider on their own cancel.

Not blocking — build against these shapes behind the repository layer and stub
locally until they land.
