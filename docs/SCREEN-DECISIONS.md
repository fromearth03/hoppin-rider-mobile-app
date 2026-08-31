# Screen decisions — rider app

Running log of what each screen builds, where it diverges from the Figma pack
(`docs/figma/extracted`, 33 PNGs), and why. Decisions are dated and final unless
revisited explicitly.

**Rule:** where the design and the backend disagree, the backend wins — but the
divergence is recorded here so the designer can be told rather than surprised.

---

## Auth

### Sign up — `Sign In.png`

*(The file is named "Sign In" but the screen is headed "Sign up". Designer's
filename, kept as-is for traceability.)*

| Drawn | Building | Why |
|---|---|---|
| First Name + Last Name, two fields | **One "Full name" field** | The backend stores a single `full_name`. Two fields would be joined on submit and could never be reliably split back for the Personal Information screen — a compound surname breaks the guess. One field is honest about what is stored. *2026-08-30* |
| "I confirm I am 18 years or older" checkbox | **Date-of-birth picker; checkbox dropped** | A self-certification checkbox enforces nothing. A stored DOB makes the backend's gate real. Note the backend's actual threshold is **13**, not 18 — the drawn copy is wrong on both counts. *2026-08-30* |
| Phone Number field | **Kept, optional, stored, never verified** | No SMS provider. The number is a stored profile field for driver contact and support, not an authentication factor. Blank writes a `pending-<uid>` placeholder that `/me/profile` hides as `""`. *2026-08-30* |
| Primary button reads "Login" | **"Create account"** | Copy error in the design — this is the sign-up screen. |
| Back arrow, top left | **Pending** | Implies a preceding screen not yet identified in the pack. |

**Phone is globally UNIQUE and cannot be cleared once set** (`profile_handler.go:50-52`).
A number already held by another account returns `409 PHONE_TAKEN` on edit.

**DOB is a two-step write.** Supabase `signUp()` has no DOB field, so the account
is created first and `PATCH /me/profile` follows. A failure between the two leaves
an account with a null DOB — which the booking guard treats as *allowed*. The app
re-attempts the PATCH on launch until it lands. See spec §4.3.

### Sign-up can succeed and still leave no profile

Migration 124 (2026-08-30) fixed a typo in `assign_entity_ref()` that had broken
**every new signup since migration 119**. The detail that matters for this screen
is *how* it failed:

> the signup trigger's EXCEPTION handler swallowed the error into a WARNING,
> leaving the auth user with no `public.users`/profile row

So Supabase returned success, the rider was signed in, and every authenticated
call afterwards failed with `USER_NOT_FOUND`. The trigger is fixed, but **the
exception handler that hid the failure is still there**, so the shape of this
failure remains reachable if any future trigger change misbehaves.

**Therefore signup does not trust Supabase's success alone.** The `PATCH
/me/profile` that writes the DOB doubles as the verification step: a
`404 USER_NOT_FOUND` there means the account exists in `auth.users` but has no
profile. The app must surface that as a real failure and offer a retry, rather
than dropping the rider into a signed-in app where nothing works. *2026-08-30*

### Login — `Login.png`

| Drawn | Building | Why |
|---|---|---|
| "Email or Phone Number" | **"Email"** | Supabase can only authenticate a phone it verified by SMS, and there is no SMS provider. A phone field on this screen would be a path that cannot work. *2026-08-30* |
| "Login using your credentials" | **Dropped** | Invite-flow copy. Riders self-signup; nobody issues them credentials. |
| Forgot Password link | **Kept** | Fires `resetPasswordForEmail`, ends at "check your inbox". The reset itself happens in the browser off the emailed link — out of milestone 1. |

---

## Booking

### Home / Ride Type — `Ride Type.png`

Full-bleed map, hamburger to the side nav, bottom sheet carrying a "Ride Type"
card, a schedule button, a search field and recent/saved locations.
`GET /service-areas` · `GET /vehicle-types` · `GET /me/saved-locations`.

### Route entry — `Enter Your Route.png`, `-1.png`

Pickup ("Active Location") + destination, with **Suggestion / Saved tabs**. The
tabs are a filter on one response, not two calls: `/geocode/search` returns
`source: "saved" | "map"` on every row.

The `-1` variant adds a **`+` button** on the destination field — multi-stop.

**Multi-stop is fully wired as of 2026-08-30** (`e77bb3e`, migration 121,
documented in `BACKEND-MULTISTOP-MOBILE-2026-08-30.md`). Round 4 had said
waypoints were *readable*; what nobody knew was that they were **silently dropped
at booking**, so multi-stop had never worked end to end. That attach bug is fixed
and three endpoints are new.

| Endpoint | Use |
|---|---|
| `POST /rides/estimate` + `waypoints` | Per-leg fares. Returns `multi_stop`, `legs[]` with `to_label` and `fare_pence`, `total_pence`, and a stitched whole-journey polyline |
| `POST /rides/request` + `waypoints` | Book with stops. **≤ 5 stops** |
| `GET /rides/:id/stops` | Live breakdown incl. per-stop waiting |
| `POST /rides/:id/stops` | Add a stop mid-trip; re-prices, pushes both parties |

**The money model has to be explained, not just displayed.** Fare is the sum of
per-leg fares plus per-stop waiting, and **platform deductions apply once on the
grand total, never per leg**. A rider seeing three legs may reasonably fear being
charged three times. Backend supplied copy for this and it should be used
close to verbatim:

> "Stops are priced per leg and added up. Fees are charged once on the total."

**Waiting is not in the estimate.** It accrues live — 3 minutes free per stop,
then 25p/min (configurable). The booking screen says waiting *may* apply; it must
not show a number it cannot know. The live figure appears on `/rides/:id/stops`
during the trip.

**Errors:** `422 NO_ZONE` when a *stop* falls outside every pricing zone, and
`422 NO_TARIFF`. The message must make clear which stop is the problem, since with
up to five the rider cannot guess.

> The backend's mobile checklist references `rides_repository.dart`,
> `seam_registry.dart` and a `MultiStopUnavailableNotice` to retire. **None exist
> here** — those belong to the previous rider app (`hoppin-rider-mobile-app/`).
> This is a greenfield build, so there is no notice to remove and no seam to flip;
> multi-stop is simply built correctly from the start.

### Vehicle select — `Select Vehicle.png`

| Drawn | Building | Why |
|---|---|---|
| 4 categories, hardcoded seats/bags | **All 6 from `/vehicle-types`, live values** | Three of the four drawn are wrong (Estate 4/4 vs live 5/4, MPV 6/4 vs 7/5, Minibus 16/12 vs 8/6) and MiniCar + MiniTruck are bookable but undrawn. Rendering the API means the screen is right today and survives an admin adding a seventh category. *2026-08-30* |
| Custom illustration per card | **Drawn art for the four, generic vehicle for the rest** | The API has no image field. Assets are keyed by category `name` with a designed fallback — required anyway, since categories are admin-editable. Two illustrations requested from the designer. *2026-08-30* |

**Contract** — `GET /api/v1/vehicle-types`, JWT-authed like every `/api/v1` route.
Verified in both services: `app_catalog_repo.go:225-236` (rider) and
`hoppin_admin/internal/api/vehicle_types.go:30-40` (admin). Same table, same five
columns, same `ORDER BY price_multiplier, name`.

```jsonc
{ "vehicle_types": [
    { "id": "uuid", "name": "Standard", "seats": 4, "bags": 2,
      "price_multiplier": 1.0 } ] }
```

**What the admin panel confirms:**

- **The Minibus discrepancy is an admin edit**, not a code change. Someone with
  `vehicles:write` corrects the row — no migration, no release. See §10.1.
- **The generic-artwork fallback is load-bearing, not defensive.**
  `createVehicleType` accepts any name, so a category with no illustration can
  appear at any moment without an app release.
- There is **no image field on the admin write path either**, so artwork can only
  live in the app.
- Admin distinguishes `vehicle_categories` (physical car classes — seats, bags,
  multiplier) from `ride_categories` (pricing tiers). **Do not conflate them.**
  The vehicle picker reads the former.

### Fare / driver selection — `Pricing Details.png`, `Choose your driver.png`

**The cards are vehicle categories, not drivers.** Decision *2026-08-30*.

The screens draw two cards at different fares under a "Choose a driver" button,
which reads as a driver marketplace. It is not one: `Go_Dispatch_Engine` solves a
Hungarian assignment (`internal/matching/hungarian.go`) and publishes exactly one
match. There is no endpoint returning candidate drivers, and `Ride Details` — the
very next screen — shows a single already-assigned driver.

So the cards carry **category + fare**, one `POST /rides/estimate` per category,
and the button confirms the booking. The rider chooses a class and a price;
dispatch chooses the driver.

**`POST /rides/estimate` is the only call needed.** It returns the fare breakdown,
distance, duration, the **road polyline for the preview map**, the cancellation
policy and which ETA tier produced the duration — in one response.

> The app must **never** call the dispatch engine (`:8081`) directly. Its README
> is explicit that it is not client-facing, and the ride service already asks it
> for the corrected ETA internally so that the quote and the eventual charge
> price off the same numbers. Raw OSRM under-predicts local trips by ~40%, which
> previously showed as a 7% gap between quote and offer. This corrects spec §7.1,
> which had the app calling `:8081/quote` for a richer breakdown.

### Ride details — `Ride Details.png`

One assigned driver: name, rating with count, trips completed, plate, vehicle
type and capacity. Fare estimate (Base + Surge), the default card, cancellation
policy. Multi-stop route shown in the header.

`GET /rides/:id` serves all of it in one call. `driver` is `null` while matching —
a normal state, not an error.

Note `/rides/:id/driver-info` also returns `recent_comments`, which no screen
draws. Rating is deliberately nullable so a new driver is not shown a fabricated
5★.

---

## Active ride

### Live trip — `Driver Arrived.png`, `Start Ride.png`

Route with A/B/C waypoint pins, driver marker, per-leg distances, a status banner
("Driver is Waiting for You"), driver identity and a Cancel Ride action.

Transport is three-part and not a choice — see spec §5.1. FCM carries status, SSE
carries driver position, the 1 Hz poll is the fallback.

**Three drawn controls are deferred to phase 2** (decision *2026-08-30*): the
**call** button, and in chat the **attachments**, **voice notes** and **"Online"
presence** dot. None has a backend: `RideDriverInfoView` exposes no phone number
(`ride_context_repo.go:20-38`), `ride_messages` stores text only, and presence is
tracked nowhere. SOS remains as the real safety control in milestone 1.

### Ride complete — `Ride Complete.png`

| Drawn | Building | Why |
|---|---|---|
| Base / Distance / Time / Wait breakdown | **Final summary only** | `GET /rides/:id/receipt` returns `fare_pence`, `waiting_pence`, `total_pence`, `distance_miles` — there is no component split. Ismail: the rider does not need our accounting. Show total, waiting charge when non-zero, distance and duration. *2026-08-30* |
| "4.7 km" | **Miles** | The API sends `distance_miles` and this is a UK operator. |

Rating prompt follows on the same screen → `POST /rides/:id/rating`.

### Trip in progress — `Start Ride.png`

Route line, driver position, destination bar, driver identity, Cancel Ride.

| Drawn | Building | Why |
|---|---|---|
| "Take left after 1.5 mi" banner | **Build it — `geo.steps`** | Raised as ASK-2 R1 and **delivered the same day** (`3e9c4a8`), despite our caveat that a passenger cannot act on a turn instruction. Rendered as drawn. *2026-08-30* |

**`geo.steps` semantics matter here.** It is `null` — never `[]` — outside the
driving states (`accepted`/`arriving`/`started`), and also `null` when OSRM is
slow or unavailable. So:

- **Hide the banner on `null`.** It is not an empty state; it means "no
  instructions available", and an empty banner would read as a broken one.
- `[]` would mean "no turns remain" and is not what the API sends. Do not treat
  the two the same.
- The `route` polyline renders regardless, so a null `steps` degrades to a map
  without a banner rather than a broken screen.
- Each step carries `maneuver` (raw OSRM: `turn-left`, `arrive`, `roundabout`)
  alongside composed `instruction` prose. Use the prose; keep `maneuver` for the
  directional icon.

---

## Payment — `Select Payment Method.png`

| Drawn | Building | Why |
|---|---|---|
| Visa Classic · **PayPal** · **Cash** | **Cards only** | Neither PayPal nor cash exists anywhere in the ride service or the payment service — searched both. Stripe cards are the only path money takes. *2026-08-30* |
| "Select Payment Method", presented as a booking step | **"Payment cards" — card management** | There is no per-ride payment selection in the API. Booking always charges the default card, so this was never a step in the booking flow; it is where a rider manages cards and sets a default. Wording must not imply a choice that does not exist. *2026-08-30* |
| Card number / CVV fields *(elsewhere in the pack)* | **Stripe SDK card element** | `setup-intent` → `clientSecret` → the SDK collects the card. A raw PAN in a `TextField` we control puts the app in PCI SAQ A-EP; the SDK element keeps it at SAQ A. |

**Contract** — verified at `payments_handler.go:68-130` and
`payments/moneyloop.go:100-107`. Two quirks that are unique in this API and will
catch out anyone assuming the house style:

- **`GET /me/payment-methods` returns a BARE ARRAY**, not `{"cards": [...]}`.
  Every other list endpoint wraps its rows in a named key. Parsing this like the
  others yields nothing.
- **The card DTO is camelCase**, alone in a snake_case API:
  `paymentMethodId`, `brand`, `last4`, `expMonth`, `expYear`, `isDefault`.

Stripe test publishable key is in `config/dev.json` (git-ignored). It ships
inside the binary by design, so it is not a secret — but the Maps key is, in the
sense that an unrestricted one is billable by anyone who extracts it.

**Flow:** `POST /me/payment-methods/setup-intent` returns a `clientSecret`, the
Stripe SDK collects the card against it, then `GET /me/payment-methods` lists
what is saved. `POST /me/payment-methods/:pmId/default` sets the default;
`DELETE /me/payment-methods/:pmId` detaches one.

**Booking always charges the default card.** There is no per-ride payment
selection anywhere in the API, so this screen is card management, not a booking
step — and `402 NO_PAYMENT_METHOD` blocks booking outright when nothing is on
file, which is why an add-card path has to exist inside the booking flow too.

`402 NO_PAYMENT_METHOD` blocks booking outright when no card is on file, so an
add-card path must exist inside the booking flow, not only in the drawer.

---

## Side navigation — `Side Nav Bar.png`

Profile header, eight destinations, logout.

| Drawn | Building | Why |
|---|---|---|
| Rider's own rating (4.31, 150) | **Build it — `rating` + `rating_count` on `/me/profile`** | Raised as ASK-2 R2 and **delivered the same day** (`3e9c4a8`). The header needs no extra call. `rating` is null until the rider has been rated at least once — show the name alone in that case, never a fabricated score. A richer `GET /me/rating` with a star distribution also exists for a future ratings screen. *2026-08-30* |
| Eight destinations | **All eight rendered; out-of-scope ones disabled** | Seven are outside milestone 1. Showing them disabled keeps the app's real shape visible without pretending they work, and each becomes a self-contained addition later. *2026-08-30* |

In milestone 1: Logout, and the trip flow the drawer sits over.
Disabled until later: Personal Information · Schedule Rides · Promotional ·
Ride History · Payments · Notifications · Help & Support · Settings.

---

## Chat — `Conversation.png`

Text only. `POST|GET /rides/:id/messages`, polled with a `since=` cursor. Round 4
added `reply_to_id`, read receipts (`status` on your own messages) and a
`reply_to` preview. Opening the thread clears `chat_unread` on `GET /rides/:id`.

Attachments, voice notes, presence and call are **phase 2** — see above.

---

## Ride history — `Ride History.png` *(milestone 2, contract recorded now)*

`GET /api/v1/rides` — cursor paged, verified at `rider_trips_read.go:73-115`.

| Param | Behaviour |
|---|---|
| `status` | `completed` \| `cancelled`. **Anything else means "all trips"**, silently — not an error |
| `from` / `to` | ISO date or timestamp, both optional, cast to `timestamptz` (added 2026-08-31, `4211757`) |
| `limit` | Default 20, **capped at 50**. A malformed value falls back to 20 silently |
| `cursor` | RFC3339, from the previous page's `next_cursor` |

Returns `{ trips, next_cursor, has_more }`. Infinite scroll passes `next_cursor`
back until `has_more` is false.

**Two things the client must not rely on:**

- **Bad input fails silently.** `limit=abc` becomes 20; `status=pending` returns
  everything. Neither errors, so the app cannot detect a mistake by watching for
  a failure — it has to send valid values.
- **The cursor is `created_at`, not an opaque token**
  (`AND r.created_at < $n ORDER BY created_at DESC`). It works, but the app
  should treat it as opaque anyway and pass back exactly what it received, so a
  future change of cursor scheme does not break the client.

`has_more` is computed by fetching `limit+1` rows rather than a second `COUNT`,
so it is exact and cheap.

**The filter UI is ours to build** — status chips and a date-range picker wired
to these params. Nothing further is needed from the backend.

---

## Open questions for the designer

Collected as they arise, to be sent in one batch rather than piecemeal.

1. Sign-up button is labelled "Login".
2. Age gate drawn as an 18+ checkbox; the platform's real threshold is 13 and it
   is enforced on a stored date of birth.
3. "Email or Phone Number" on login implies SMS authentication that does not
   exist.
4. First/Last name split does not match the single stored `full_name`.
5. `Sign In.png` contains the Sign up screen — filename is misleading.
6. **Vehicle seats/bags are wrong on three of four cards**, and MiniCar and
   MiniTruck are missing entirely. Two illustrations needed. (Whether the *data*
   is wrong instead is an ops question — `vehicle_categories` is admin-editable.)
7. **"Choose a driver"** implies a driver marketplace. Dispatch assigns one
   driver; the cards are vehicle categories. Button copy should say "Confirm".
8. **Call, attachments, voice notes and the "Online" dot** have no backend.
   Deferred to phase 2 rather than removed.
9. Receipt draws a fare breakdown the receipt endpoint does not return.
10. Distances drawn in km; the API sends miles.

---

## Deferred to phase 2

Recorded so they are not silently lost.

| Item | What it needs |
|---|---|
| Call driver | A phone number on driver-info, or a masked-calling service. Neither exists. |
| Chat attachments | Object storage + a column on `ride_messages`. |
| Chat voice notes | Same, plus audio capture and playback. |
| Driver "Online" presence | Presence tracking that exists nowhere today. |
