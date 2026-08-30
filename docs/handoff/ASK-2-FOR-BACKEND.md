# ASK-2 — rider app · ✅ CLOSED

> **Both items delivered the same day** (`3e9c4a8`, `b5f0f58`). Reply:
> `BACKEND-FOR-RIDER-APP-ASK2-REPLY-2026-08-30.md`. Verified against the merged
> handlers, not just the reply. Kept for the record; nothing here is outstanding.


**Date:** 2026-08-30 · **Service:** `Go_ride_service` (`api.hoppin.tech`)
**From:** rider app · **Previous:** ASK-1 (`FOR-BACKEND.md`) — fully delivered,
thank you.

Two requests, both surfaced by walking the Figma pack against the merged handlers.
Neither blocks milestone 1: the app renders honestly without them and will pick
them up when they land.

Numbered R1, R2 so replies stay traceable.

---

## R1 · Turn-by-turn steps — ✅ DELIVERED 2026-08-30

Built despite our caveat. Their answer: *"it's cheap OSRM plumbing and the design
calls for it, so it's built. Use it or ignore it."*

`GET /rides/:id` → `geo.steps`, verified at `rider_ride_detail.go:34,164-170`:

```jsonc
"steps": [ { "instruction": "Turn left onto Waterloo Road",
             "distance_meters": 2414, "maneuver": "turn-left" } ]
```

Two details better than what we asked for:

- **`null` unless the trip is actively being driven** (`accepted`/`arriving`/
  `started`), so a finished-trip poll does not pay for an OSRM steps call.
- **`null`, never `[]`** — `[]` would mean "no turns", `null` means "unavailable".
  The banner hides on null rather than rendering an empty state.
- `maneuver` carries the raw OSRM type (`turn-left`, `arrive`, `roundabout`) as
  well as composed prose, so we can write our own copy if theirs reads oddly.

*Original request follows for the record.*

**Priority:** low. Nice-to-have, not blocking.

**What the design shows.** The active-trip screen (`Start Ride.png`) draws a
navigation banner: *"Take left after 1.5 mi"*.

**What exists.** `GET /rides/:id` returns `geo.route` — an OSRM road polyline as
`[{lat,lng}]`. No instructions, no step boundaries, no distances-to-turn.

**The ask.** Optional step list on the ride's geo block, e.g.

```jsonc
"geo": {
  "route": [ /* unchanged */ ],
  "steps": [                                   // null when unavailable
    { "instruction": "Turn left onto Waterloo Road",
      "distance_meters": 2414,
      "maneuver": "turn-left" }
  ]
}
```

OSRM produces this natively (`steps=true` on the route request), so this is
plumbing rather than new computation.

**Worth saying plainly:** we are not sure this is a good use of your time. The
rider is a passenger, not the driver — they cannot act on a turn instruction, and
the driver app is where navigation belongs. We are raising it because the design
calls for it and the product owner asked us to ask rather than drop it. If you
think it is the wrong thing to build, say so and we will close it.

Until then the banner shows trip status and ETA, both of which we already have.

---

## R2 · Rider's own rating — ✅ DELIVERED 2026-08-30

Shipped **both ways**, verified at `profile_handler.go:29-50`:

**`GET /me/profile`** now carries the two fields exactly as asked — this is what
the side nav uses, so the header costs no extra call:

```jsonc
{ …, "rating": 4.31,      // null until rated at least once
      "rating_count": 150 }
```

**`GET /me/rating`** additionally exists for a richer ratings screen, adding a
1–5 star `distribution` we did not ask for.

Both compute live from `reviews` rather than a cached column, so neither goes
stale. The null-not-defaulted point was honoured in both.

*Original request follows for the record.*

**Priority:** low.

**What the design shows.** The side navigation header (`Side Nav Bar.png`) shows
the rider's own rating and review count — *4.31 (150)* — beside their name and
photo.

**What exists.** `GET /me/profile` returns exactly:

```jsonc
{ "full_name", "phone_number", "email", "avatar_url", "date_of_birth" }
```

No rating, no count. Drivers rate riders after a trip (the rider app already posts
the reverse via `POST /rides/:id/rating`), so the underlying data plausibly exists
in `reviews` — it is simply not exposed to the rider.

**The ask.** Two nullable fields on `/me/profile`:

```jsonc
{ "rating": 4.31,        // null until the rider has been rated at least once
  "rating_count": 150 }
```

**Please keep `rating` null rather than defaulting it.** `RideDriverInfoView`
already does exactly this and explains why: `driver_profiles.average_rating`
defaults to `5.00`, so serving it unconditionally fabricated a 5★ for every driver
who had never been rated. The same honesty rule should apply here — a new rider
has no rating, and `null` says so where `5.0` lies.

Until this lands the header shows name and avatar only.

---

## Not asking for these

Recorded so you know they were considered and deliberately left alone.

| Thing | Why we are not asking |
|---|---|
| **Cash payments** | The design draws a Cash option. It would change settlement, driver reconciliation and dispute handling — far beyond a field. A product decision first, if ever. |
| **PayPal** | Design draws it; Stripe is the only rail. No plans to change that. |
| **Driver phone / masked calling** | The design draws a call button. Deferred to phase 2 by the product owner rather than asked for now. |
| **Chat attachments and voice notes** | `ride_messages` is text-only. Phase 2. |
| **Driver presence ("Online" dot)** | Not tracked anywhere. Phase 2. |
| **Receipt fare breakdown** | The design draws base/distance/time/wait. Product owner's call: the rider does not need our accounting. `fare_pence` + `waiting_pence` + `total_pence` is enough. |
| **Multi-driver offers** | The design's "Choose a driver" implies a marketplace. Dispatch solves a Hungarian assignment and returns one match; we have built to that instead. |

---

## Register

| Ask | Item | Status |
|---|---|---|
| ASK-1 | R1–R5 | ✅ delivered (rounds 1–5) |
| ASK-2 | R1 turn-by-turn steps | ✅ delivered (`3e9c4a8`) |
| ASK-2 | R2 rider rating | ✅ delivered (`3e9c4a8` + `b5f0f58`) |

**Nothing outstanding. Next ask is ASK-3.**

---

## Also landed 2026-08-30, unasked

**Multi-stop rides are now fully wired** (`e77bb3e`, documented in
`BACKEND-MULTISTOP-MOBILE-2026-08-30.md`). We had not raised this — the round-4
note said waypoints were readable, and we did not know they were being **silently
dropped at booking**, so multi-stop had never actually worked end to end.

Now live: `waypoints` on `/rides/estimate` returning per-leg fares,
`waypoints` on `/rides/request` (attach bug fixed), `GET /rides/:id/stops`,
`POST /rides/:id/stops` to add a stop mid-trip, and driver-side per-stop
arrive/depart for waiting.

The `+` button on the route-entry screen is therefore buildable as drawn.
