# Backend — implemented (handover to the RIDER app dev)

**Date:** 2026-08-27 · **Service:** `Go_ride_service` (`:8080`)

Covers the rider-app asks in `FOR-BACKEND.md` / `BACKEND-CONTRACT-REQUEST.md`.
Everything below is **merged to `main`** and **takes effect once the ride-service
is redeployed** — build against these shapes now; they are stable.

Conventions: **money is integer `*_pence` (int64)**, **snake_case**, **nullables
stay `null`** (never a fake `0`).

---

## ✅ Implemented

### R2 · `GET /api/v1/rides` — enriched trip history
Params: `limit` (default 20, max 50), `cursor` (opaque; pass back `next_cursor`),
`status` (`completed` | `cancelled`, optional).

```jsonc
{
  "trips": [{
    "id": "uuid",
    "status": "completed",
    "ride_category": "standard",
    "vehicle_category": { "id":"uuid","name":"Standard","seats":4,"bags":2 }, // null if unset
    "pickup_label": "King Street, Wolverhampton",   // nullable
    "dropoff_label": "Oaks Crescent, Wolverhampton",// nullable
    "requested_at": "2026-06-05T08:04:59Z",         // rides.created_at — group by date client-side
    "pickup_time": "2026-06-05T08:05:00Z",          // nullable
    "dropoff_time": "2026-06-05T08:20:00Z",         // nullable
    "total_pence": 1238,                            // COALESCE(charged, quoted)*100; nullable
    "currency": "GBP",
    "driver": {                                     // null when never assigned
      "id":"uuid","full_name":"Driver Test","avatar_url":null,
      "rating":4.5,"rating_count":2 },              // rating nullable (no reviews yet)
    "my_rating": 5,                                 // this rider's score; null if unrated
    "cancelled_by": "rider"                         // rider|driver|system|null
  }],
  "next_cursor": "2026-02-13T09:12:00Z",            // null when no more
  "has_more": true
}
```
`my_rating` is what distinguishes rated from unrated — use it to prompt for a
missing rating.

### R3 · `GET /api/v1/rides/:id` — enriched single ride
**Backwards-compatible**: every existing `models.Ride` key is unchanged; four
blocks are **added**, so one call renders the whole trip screen — no more
`/rides/:id` + `/geo` + `/driver-info` fan-out (those endpoints still exist).

- **`driver` is `null` while matching** — a normal state, NOT the old
  `409 NO_DRIVER_ASSIGNED`. Treat null as "still searching".
- **`geo.waypoints` is now readable** (was write-only) — a multi-stop trip can
  display its own stops after a reload. `[]` when none.

```jsonc
{
  /* …existing ride keys unchanged… */
  "geo": {
    "pickup":  { "lat":52.586, "lng":-2.128, "label":"…" },  // label nullable
    "dropoff": { "lat":52.588, "lng":-2.120, "label":"…" },
    "waypoints": [ { "lat":52.587, "lng":-2.124, "label":null } ], // [] when none
    "route": [ { "lat":..,"lng":.. } ]              // may be null (straight-line today)
  },
  "driver": {                                       // null while matching
    "id":"uuid","full_name":"…","avatar_url":null,
    "rating":4.3,"rating_count":113,"trips_count":1130,
    "vehicle": { "make":"Toyota","model":"Prius","colour":"White",
                 "plate":"RV 20 OZT","seats":4,"bags":2 },
    "eta_seconds": 82                               // from quoted_pickup_eta_seconds; nullable
  },
  "fare": {
    "estimate_pence": 1250, "total_pence": null,    // total set once charged
    "currency":"GBP", "discount_pence": 0 },
  "timestamps": {
    "accepted_at": null, "arrived_at":"…",
    "started_at":"…",   "completed_at":null }        // arrived_at, pickup_time, dropoff_time
}
```

### R4 · FCM + notifications
- The rider `ride_update` push now carries **`status`** in its data payload —
  skip the `/rides/:id` re-fetch when only the status changed (this is the app's
  hottest path). Payload: `{ type:"ride_update", ride_id, deep_link, status,
  notification_id }`.
- A rider **self-cancel** now also pushes to the rider's **own** devices, so a
  cancel from one device no longer leaves a second device stale on the live-trip
  screen.

### R5 · `testop` removed from the vehicle picker
The `testop` test row is deactivated in `vehicle_categories`. The picker now shows
Standard, Estate, MPV, Minibus, MiniCar, MiniTruck only. You render from the API,
so nothing to change — it just won't appear anymore.

> Note (design, not backend): live seats/bags differ from the Figma for some
> categories (e.g. Minibus is configured 8/6, drawn 16/12). The app renders the
> API values — flag with design which is correct.

---

## ⏳ Config only (not code, not blocking)

- **R1 · rider JWT role** — self-signup riders currently carry no `user_role` in
  their token, so rider endpoints lean on the lenient `riderOnly()`. The
  `custom_access_token_hook` already stamps `user_role` from `public.users.role`;
  it just needs **enabling in Supabase → Auth → Hooks**. No app change — "signed
  in" stays your only client-side auth state today; nothing is broken.

---

## Verified as-is (per your doc)
No in-app wallet/credit endpoints. No demand/surge endpoint — surge is admin-set,
read via `GET :8081/pricing`. No turn-by-turn — hand off to the external map app.
`referral_tracking` is dropped from the live schema (not wanted).
