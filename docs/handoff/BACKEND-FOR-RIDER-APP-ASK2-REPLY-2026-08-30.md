# ASK-2 — reply (rider app)

**Date:** 2026-08-30 · **Service:** `Go_ride_service` (`api.hoppin.tech`). Both live.

Both delivered. Register updated.

---

## R2 · Rider's own rating on `/me/profile` — ✅ DONE

`GET /me/profile` now returns two extra fields, exactly as asked:
```jsonc
{ "full_name","phone_number","email","avatar_url","date_of_birth",
  "rating": 4.31,        // null until the rider has been rated at least once
  "rating_count": 150 }
```
- Computed **live** from `reviews` (driver→rider, `reviewee_id = you`) — never stale.
- **`rating` is `null` until the first rating** (your honesty rule — a new rider has no
  rating, and `null` says so where `5.0` lies). `rating_count` is `0` for a new rider.
- Verified against live data (e.g. `5.0` over `7` reviews).

Bonus: there's also a dedicated **`GET /me/rating`** if you want a richer ratings screen —
same `average_rating` + `rating_count` **plus a 1–5 star `distribution`**:
```jsonc
{ "average_rating": 4.31, "rating_count": 150,
  "distribution": { "5": 120, "4": 20, "3": 6, "2": 2, "1": 2 } }
```
Use whichever fits — the header only needs the two fields on `/me/profile`.

---

## R1 · Turn-by-turn steps on the trip geo — ✅ DONE (with your caveat noted)

You flagged this as maybe-not-worth-it (the rider's a passenger, navigation belongs in the
driver app) and invited us to decline. Fair point — but it's cheap OSRM plumbing and the
design calls for it, so it's built. Use it or ignore it.

`GET /rides/:id` → the `geo` block now carries an optional `steps` list:
```jsonc
"geo": {
  "pickup": {…}, "dropoff": {…}, "waypoints": [...], "route": [ /* unchanged */ ],
  "steps": [                                   // null unless the trip is being driven
    { "instruction": "Turn left onto Waterloo Road",
      "distance_meters": 2414, "maneuver": "turn-left" },
    { "instruction": "Arrive at your destination",
      "distance_meters": 0, "maneuver": "arrive" }
  ]
}
```
- **`steps` is `null`** except while the trip is actually being driven
  (`accepted` / `arriving` / `started`) — so finished-trip polls don't pay for the extra
  OSRM call. Best-effort: `null` if OSRM is slow/unavailable (the `route` still renders).
- `instruction` is a short composed banner (OSRM returns no prose); `maneuver` is the raw
  type+modifier (`turn-left`, `arrive`, `roundabout`, …) if you'd rather build your own copy.

---

## Register
| Ask | Item | Status |
|---|---|---|
| ASK-1 | R1–R5 | ✅ delivered |
| ASK-2 | R1 turn-by-turn steps | ✅ delivered |
| ASK-2 | R2 rider rating on `/me/profile` | ✅ delivered |
