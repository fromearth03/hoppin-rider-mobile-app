# Backend — RIDER app handover (complete)

**Date:** 2026-08-30 · **Service:** `Go_ride_service` (`:8080`) · Supersedes the 08-27 rider doc.

Everything below is **merged and deployed live**. Conventions: **money is integer
`*_pence` (int64)**, **snake_case**, **nullables stay `null`** (never a fake `0`).

---

## Trips

### `GET /api/v1/rides` — history (enriched, paged)
Params: `limit` (default 20, max 50) · `cursor` (opaque, pass back `next_cursor`) ·
`status` (`completed`|`cancelled`, optional).
```jsonc
{ "trips": [{
    "id":"uuid","status":"completed","ride_category":"standard",
    "vehicle_category":{"id":"uuid","name":"Standard","seats":4,"bags":2}, // null if unset
    "pickup_label":"King Street, Wolverhampton",   // nullable
    "dropoff_label":"Oaks Crescent, Wolverhampton",// nullable
    "requested_at":"…","pickup_time":"…","dropoff_time":"…", // last two nullable
    "total_pence":1238,"currency":"GBP",           // total nullable
    "driver":{"id":"uuid","full_name":"…","avatar_url":null,"rating":4.5,"rating_count":2}, // null if unassigned
    "my_rating":5,        // this rider's score; null if unrated
    "cancelled_by":"rider"// rider|driver|system|null
  }],
  "next_cursor":"2026-02-13T09:12:00Z","has_more":true }
```

### `GET /api/v1/rides/:id` — single ride (enriched, backwards-compatible)
Existing `models.Ride` keys unchanged; added blocks render the whole trip screen in
one call. **`driver` is `null` while matching** (not a 409). Waypoints readable.
```jsonc
{ /* …existing ride keys… */
  "geo":{ "pickup":{"lat":..,"lng":..,"label":"…"}, "dropoff":{…},
          "waypoints":[{"lat":..,"lng":..,"label":null}],
          "route":[{"lat":..,"lng":..}] }, // A16: real OSRM road polyline (straight-line fallback)
  "driver":{ "id":"uuid","full_name":"…","avatar_url":null,"rating":4.3,"rating_count":113,
             "trips_count":1130,
             "vehicle":{"make":"Toyota","model":"Prius","colour":"White","plate":"RV 20 OZT","seats":4,"bags":2},
             "eta_seconds":82 },   // live OSRM ETA; nullable
  "fare":{ "estimate_pence":1250,"total_pence":null,"currency":"GBP","discount_pence":0 },
  "timestamps":{ "accepted_at":null,"arrived_at":"…","started_at":"…","completed_at":null },
  "chat_unread": 2 }               // messages from the driver since you last opened chat
```

### `GET /api/v1/me/active-ride` — "am I on a ride?" (NEW)
For a mid-trip relaunch. Returns the current non-terminal ride, or nulls; then load
`GET /rides/:id`.
```jsonc
{ "active_ride_id":"uuid"|null, "status":"arriving"|null }
```

## Notifications — `GET /api/v1/me/notifications`
Now a full envelope (was a bare `{notifications:[…]}` with no badge, no paging).
Params: `limit` (1-100) · `cursor`.
```jsonc
{ "notifications":[{ "id","type","title","body","ride_id","deep_link","read_at","read":false,"created_at" }],
  "unread_count": 941,          // whole-feed badge
  "next_cursor":"…"|null, "has_more":true }
```
Push already delivers these via FCM (foreground stream feeds the bell); this endpoint
backs the centre + the Read/Unread tabs + the badge.

## Promotions — `GET /api/v1/promotions`
Now rider-aware — the Active / Availed / Expired tabs all work.
```jsonc
{ "promotions":[{ "promo_code":"FIVER","title":"…","description":"…",
    "discount_type":"…","discount_value":5.0,"max_discount_cap":null,"min_ride_amount":null,
    "new_users_only":false,"expires_at":"…",
    "availed":true,               // this rider redeemed it
    "state":"active"|"availed"|"expired" }] }  // server-owned; use for the tab
```
Expired promos are **no longer filtered out** server-side (so the Expired tab fills).

## Scheduled rides — `GET /api/v1/scheduled-rides`
Enriched from the thin geoms-only row.
```jsonc
{ "scheduled_rides":[{ "id","status",
    "pickup":{"lat":..,"lng":..,"label":"…"}, "dropoff":{…}, // labels reverse-geocoded, best-effort
    "requested_pickup_time":"…","estimate_pence":1250,"currency":"GBP",
    "vehicle_category":"Standard","active_ride_id":null }] }
```

## Payments — `GET /api/v1/me/transactions`
```jsonc
[{ "id","ride_id","amount_pence":865,"currency":"GBP","status","provider","provider_payment_id",
   "created_at",
   "pickup_label":"Queen Square, Wolverhampton","dropoff_label":"…", // nullable
   "card_brand":"visa","card_last4":"8901" }] // nullable on legacy/unconfirmed rows
```
The Recent Payments row now has everything: amount, place label, and the card used
(`card_brand` + `card_last4` → "Visa ••8901"). The payment service captures the card
from Stripe at charge time; rows charged before this change (or a fresh-card flow not
yet confirmed) have null card fields — render the card line only when present.

## Saved locations — `PATCH /api/v1/me/saved-locations/:id` (NEW)
Rename in place (add/list/delete existed; a rename was delete+recreate, losing the id).
Body `{ "label":"Home" }` → `200 { "id","label" }`.

## Notifications transport + misc
- Rider `ride_update` FCM now carries **`status`** — skip the `/rides/:id` re-fetch
  when only the status changed. Payload `{type,ride_id,deep_link,status,notification_id}`.
- A rider **self-cancel** now also pushes to the rider's own other devices.
- `testop` is gone from the vehicle picker.
- **Rider JWT role**: the Supabase `custom_access_token_hook` is **enabled** — self-
  signup riders now carry `user_role` in their token.
