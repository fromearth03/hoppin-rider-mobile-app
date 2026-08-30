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
Waypoints became readable in round 4, so a multi-stop trip survives a reload.

### Vehicle select — `Select Vehicle.png`

| Drawn | Building | Why |
|---|---|---|
| 4 categories, hardcoded seats/bags | **All 6 from `/vehicle-types`, live values** | Three of the four drawn are wrong (Estate 4/4 vs live 5/4, MPV 6/4 vs 7/5, Minibus 16/12 vs 8/6) and MiniCar + MiniTruck are bookable but undrawn. Rendering the API means the screen is right today and survives an admin adding a seventh category. *2026-08-30* |
| Custom illustration per card | **Drawn art for the four, generic vehicle for the rest** | The API has no image field. Assets are keyed by category `name` with a designed fallback — required anyway, since categories are admin-editable. Two illustrations requested from the designer. *2026-08-30* |

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
| "Take left after 1.5 mi" banner | **Deferred — backend ask R1** | No endpoint returns turn instructions; `/rides/:id` gives a polyline only. Ismail asked for it to be raised with backend rather than dropped. Until it lands the banner space carries trip status and ETA. *2026-08-30* |

---

## Payment — `Select Payment Method.png`

| Drawn | Building | Why |
|---|---|---|
| Visa Classic · **PayPal** · **Cash** | **Cards only** | Neither PayPal nor cash exists anywhere in the ride service or the payment service — searched both. Stripe cards are the only path money takes. *2026-08-30* |
| "Select Payment Method", presented as a booking step | **"Payment cards" — card management** | There is no per-ride payment selection in the API. Booking always charges the default card, so this was never a step in the booking flow; it is where a rider manages cards and sets a default. Wording must not imply a choice that does not exist. *2026-08-30* |
| Card number / CVV fields *(elsewhere in the pack)* | **Stripe SDK card element** | `setup-intent` → `clientSecret` → the SDK collects the card. A raw PAN in a `TextField` we control puts the app in PCI SAQ A-EP; the SDK element keeps it at SAQ A. |

`402 NO_PAYMENT_METHOD` blocks booking outright when no card is on file, so an
add-card path must exist inside the booking flow, not only in the drawer.

---

## Side navigation — `Side Nav Bar.png`

Profile header, eight destinations, logout.

| Drawn | Building | Why |
|---|---|---|
| Rider's own rating (4.31, 150) | **Deferred — backend ask R2** | `/me/profile` returns `full_name`, `phone_number`, `email`, `avatar_url`, `date_of_birth` and nothing else. Ismail asked for it to be raised with backend. Header shows name and avatar until it lands. *2026-08-30* |
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
