# ASK-1 — Rider app backend asks

**Status: answered 2026-08-27** — see `docs/BACKEND-FOR-RIDER-APP-2026-08-27.md`.
R2–R5 shipped (merged to `main`, pending redeploy); R1 is a Supabase dashboard
toggle still to be enabled.

We're building the new rider app against `Go_ride_service`. Four items below.

Nothing here is blocking — we build against these shapes behind a repository
layer and stub locally until they land. Items 2 and 3 are additive response
changes; every column they need already exists (verified against the live DB on
2026-08-27, so no migrations).

| # | Ask | Owner |
|---|---|---|
| 1 | Self-signup riders have no role in their JWT | Supabase project config |
| 2 | `GET /rides` — trip history list view | ride-service |
| 3 | `GET /rides/:id` — add geo, driver, fare | ride-service |
| 4 | Two schema findings (`testop` row, stale `.env`) | ride-service / infra |

---

## 1. Self-signup riders have no role in their JWT

**This is Supabase configuration, not a code bug.** Both the app and the backend
are written correctly around the gap.

### What happens

The rider app calls `supabase.auth.signUp()` directly. Supabase mints a JWT whose
only role field is `role: "authenticated"` — the Postgres-level role, identical
for every signed-in user. It does not set `user_role` or `app_metadata.role`,
because nothing tells it to.

The `on_auth_user_created` trigger (mig 086) then correctly writes
`public.users.role = 'rider'`. But that's a **database column**, and the JWT was
already minted. The column never flows back into the token — two separate systems.

Confirmed live: `user_role` enum is `rider, driver, admin`; 22 riders all carry
`role = 'rider'` in `public.users`. The data is right. It just isn't in the token.

So `extractRole()` (`internal/auth/verifier.go:139`) checks
`user_role` → `app_metadata.role` → `role`, finds only `"authenticated"`, and
every self-signup rider reads as role-less.

### It's already compensated for

`riderOnly()` (`internal/handler/ride_handler.go:461`):

```go
// riderOnly is DELIBERATELY LENIENT: it blocks only an explicit driver token,
// not "everyone who is not a rider". Self-signup riders often carry no
// user_role claim at all, so requiring role=="rider" would lock real riders out
```

### Why it's still worth fixing

`riderOnly()` is a **denylist** — it rejects only `role == "driver"`, so any
`"authenticated"` token in the project passes. Compare `driverOnly()` (`:444`),
a strict allowlist. Rider endpoints — booking, payments, promos, transactions —
are guarded by the weaker of the two.

### The fix

A Supabase **custom Access Token hook** stamping the role into the JWT from the
column the DB already has, so tokens carry `user_role: "rider"` (or
`app_metadata.role`). **No service code changes** — `extractRole` already reads
both. Once tokens carry it, `riderOnly()` can be tightened to an allowlist,
matching `driverOnly()`.

**Meanwhile** the app branches on nothing; "signed in" is our only client-side
auth state. Nothing is broken today.

---

## 2. `GET /api/v1/rides` — trip history needs a list view

### Problem

Returns a bare array of `models.Ride` — 11 fields, no fare, no place labels, no
rating. The history row needs origin, destination, fare and rating, so today it
costs **one `/receipt` call per ride**, and the place labels aren't retrievable
at any price.

### Columns this needs (all present)

`rides.pickup_label` / `dropoff_label` (mig 089) · `reviews.rating_score` ·
`fare_estimates.quoted_price` · `transactions.total_amount_charged` ·
`vehicle_categories.name/seats/bags`

Labels are populated on 29 of 66 live rides — NULL is the honest "not yet
resolved" state and we handle it.

### Requested response

```jsonc
{
  "trips": [
    {
      "id": "uuid",
      "status": "completed",
      "ride_category": "standard",
      "vehicle_category": { "id":"uuid", "name":"Standard", "seats":4, "bags":2 },

      "pickup_label":  "Wolverhampton City Centre",     // nullable
      "dropoff_label": "Wolverhampton Railway Station", // nullable

      "requested_at": "2026-02-16T11:50:00Z",   // rides.created_at
      "pickup_time":  "2026-02-16T11:52:10Z",   // nullable
      "dropoff_time": "2026-02-16T12:05:00Z",   // nullable

      "total_pence": 386,     // COALESCE(t.total_amount_charged, fe.quoted_price)*100
      "currency": "GBP",

      "driver": {             // null when never assigned
        "id": "uuid",
        "full_name": "George Oliver",
        "avatar_url": null,
        "rating": 4.3,
        "rating_count": 113
      },

      "my_rating": 5,         // reviews.rating_score by THIS rider; null if unrated
      "cancelled_by": null    // "rider" | "driver" | "system" | null
    }
  ],
  "next_cursor": "2026-02-13T09:12:00Z",   // null when no more
  "has_more": true
}
```

**Params:** `limit` (default 20, max 50), `cursor` (`created_at` DESC), optional
`status` filter (`completed` / `cancelled`) — those two are 60 of 66 live rides.

**Conventions:** integer pence, same as `/receipt` — never floats. snake_case.
Date grouping ("16 Feb") is client-side off `requested_at`.

**Why `my_rating`:** it's what distinguishes rated from unrated. Without it we
can't tell, so we can't prompt for a missing rating.

---

## 3. `GET /api/v1/rides/:id` — needs geo, driver, fare

### Problem

11 fields, no coordinates and no fare. One trip screen takes three calls:
`/rides/:id` + `/geo` + `/driver-info`. And since the FCM payload carries no
status, **every push forces a re-fetch** — making this the hottest path in the
app at 3× the necessary cost.

### Requested

Keep all existing keys (backwards-compatible), add four blocks:

```jsonc
{
  // … existing fields unchanged …

  "geo": {
    "pickup":  { "lat":52.586, "lng":-2.128, "label":"Wolverhampton City Centre" },
    "dropoff": { "lat":52.588, "lng":-2.120, "label":"Wolverhampton Railway Station" },
    "waypoints": [ { "lat":52.587, "lng":-2.124, "label":null } ],  // rides.waypoints; [] when none
    "route": [ { "lat":52.586, "lng":-2.128 } ]                     // polyline, may be null
  },

  "driver": {                       // null while matching
    "id": "uuid",
    "full_name": "George Oliver",
    "avatar_url": null,
    "rating": 4.3,
    "rating_count": 113,
    "trips_count": 1130,
    "vehicle": { "make":"Toyota", "model":"Prius", "colour":"White",
                 "plate":"RV 20 OZT", "seats":4, "bags":2 },
    "eta_seconds": 82               // nullable
  },

  "fare": {
    "estimate_pence": 886,
    "total_pence": null,            // set once charged
    "currency": "GBP",
    "discount_pence": 0             // applied promo, 0 when none
  },

  "timestamps": {
    "accepted_at":  null,                    // rides.accepted_at
    "arrived_at":   "2026-02-16T11:51:00Z",  // rides.arrived_at
    "started_at":   "2026-02-16T11:52:10Z",  // rides.pickup_time
    "completed_at": null                     // rides.dropoff_time
  }
}
```

All four timestamp columns already exist on `rides` (`accepted_at`, `arrived_at`,
`pickup_time`, `dropoff_time`), as do `waypoints`, `pickup_label`, `dropoff_label`
and `quoted_pickup_eta_seconds`.

### Two behavioural asks

1. **`driver: null` instead of `409 NO_DRIVER_ASSIGNED` while matching.**
   Searching for a driver is a normal state, not an error — a 409 forces the
   client to treat the searching screen as a failure.

2. **Make waypoints readable.** They're accepted at booking and written to
   `rides.waypoints` (mig 066), but no read endpoint returns them, so a
   multi-stop trip can't display its own stops after a reload.

   Worth checking the **write** path too: `rides.waypoints` and `ride_waypoints`
   are both empty across all 66 live rides, so multi-stop may never have run
   end-to-end.

`/geo` and `/driver-info` can stay as they are — this only removes the fan-out.

---

## 4. Lower priority

**Status in the FCM payload.** Currently `{type:"ride_update", ride_id, deep_link}`
with no status, so every push forces a re-fetch. Adding `"status": "arriving"`
lets us skip the round-trip when only the status changed.

**Notify the rider on their own cancel.** `internal/service/ride_service.go:1986`
notifies only the driver, so a cancel from another device leaves this one stale.

---

## 5. Two things noticed while verifying the schema

**A test row is live in `vehicle_categories`.** Active categories are Standard
(4s/2b), Estate (5s/4b), MPV (7s/5b), Minibus (8s/6b), MiniCar (4s/2b),
MiniTruck (7s/2b) — and **`testop`**. That will appear in the rider's vehicle
picker. Worth deactivating before launch.

*(The seats/bags also differ from the Figma — Estate 5/4 live vs 4/4 drawn,
Minibus 8/6 vs 16/12. We render from the API so nothing is needed on your side;
design has been flagged separately. Flagging Minibus in particular — 16 drawn vs
8 configured is a big enough gap that one of the two is wrong.)*

**Stale credential in `Go_Database/.env`.** It points at
`db.buoreyyxpzvwnxvzpfea.supabase.co:5432`, which no longer resolves. The working
connection is the pooler — `aws-1-ap-southeast-1.pooler.supabase.com`, user
`postgres.<ref>`. Anything still reading that file will fail to connect.

---

## Appendix — what we verified, so you don't re-check

Live DB, 2026-08-27, 84 public tables.

**Absent** (despite appearing in `001_initial.sql`): `referral_tracking`,
`rider_subscriptions`, `micromobility_assets`, `micromobility_rentals`,
`payment_methods` (correctly dropped by mig 088).

**Present but empty:** `rider_wallets`, `driver_tips`, `surge_pricing_polygons`,
`trip_messages` (`ride_messages` is the live one), `saved_locations`,
`ride_waypoints`.

**Live counts:** `user_notifications` 943 · `rides` 66 · `reviews` 24 ·
`promotions` 10 · `sos_events` 7 · `scheduled_rides` 5 · `ride_messages` 2.

**Ride statuses in use:** completed 36 · cancelled 24 · started 2 · arriving 2 ·
accepted 2. `requested` and `assigned` are never written — dead states, matching
what the code shows.

The rider app depends on **none** of the absent or empty tables. No wallet or
credit endpoints needed (no in-app wallet). No demand/surge endpoint — admin-set
surge via `GET :8081/pricing` is sufficient. No turn-by-turn — navigation hands
off to the external map app.
