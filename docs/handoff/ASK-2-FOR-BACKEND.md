# ASK-2 — rider app

**Date:** 2026-08-30 · **Service:** `Go_ride_service` (`api.hoppin.tech`)
**From:** rider app · **Previous:** ASK-1 (`FOR-BACKEND.md`) — fully delivered,
thank you.

Two requests, both surfaced by walking the Figma pack against the merged handlers.
Neither blocks milestone 1: the app renders honestly without them and will pick
them up when they land.

Numbered R1, R2 so replies stay traceable.

---

## R1 · Turn-by-turn steps for the rider's trip screen

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

Shipped as **`GET /me/rating`** (`b5f0f58`) rather than fields on `/me/profile`,
which is the better shape — the side nav does not pay for a distribution query it
will not render, and a future ratings screen uses the same endpoint.

```jsonc
{ "average_rating": 4.31,     // null until at least one review
  "rating_count": 150,
  "distribution": { "5": 120, "4": 20, "3": 6, "2": 3, "1": 1 } }
```

The null-not-defaulted point was honoured exactly (`rating_handler.go:40,44`), and
a star distribution we did not ask for was added. Nothing further needed.

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
| ASK-2 | R1 turn-by-turn steps | open |
| ASK-2 | R2 rider rating | ✅ delivered as `GET /me/rating` (`b5f0f58`) |

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
