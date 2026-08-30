# Passenger View — design change requests

Re: "passenger view Super FINAL" (29 boards).

We went through every board against what the platform can actually do. Most of it
maps cleanly — the fare breakdown, the vehicle cards, the settings toggles and the
saved/suggestion split all match real behaviour, which made this quick.

Below is what needs to change and why. Grouped by whether the screen goes away,
changes, or needs something new drawn.

---

## 1. Screens to remove (6)

### Choose your driver
Shows several drivers, each with their own price, rider picks one.

The system does not work that way — it matches a single best driver automatically
and assigns them. There is never a list to choose from. **Confirm Booking goes
straight to searching, then to the assigned driver.**

### OTP Confirmation · Reset Password · Expired-link
Password reset stays on the email side — the rider gets a link, taps it, and
resets in the browser. No code entry in the app, so these three flows never appear.

**Forgot Password stays**, but it now ends at a "check your inbox" confirmation
rather than continuing to a code screen. That end state needs drawing (see §3).

### Wallet (everywhere it appears)
Wallet row on Payment Methods, wallet option on Select Payment Method, and the
"refunded in your wallet" notification.

There is no in-app wallet — no balance, no credit, nothing to spend. Refunds go
back to the card they came from.

**Notification copy** should read something like *"£12.36 refunded to your Visa
••8901"*.

### PayPal
Card payments only. No PayPal integration exists or is planned near-term.

---

## 2. Screens that change

### Payment Methods — the Add Card sheet
The drawn form has four fields we control: Card Number, Card Holder Name, Expiry,
CVV.

We need to replace those with **Stripe's own single-line card input** (number,
expiry and CVC in one row). This is a compliance requirement, not a preference —
if a card number passes through fields we built, the whole app falls into a much
heavier PCI audit. Stripe's field keeps the card data entirely outside our code.

Practically:
- one card row instead of three fields
- **Card Holder Name goes** — Stripe doesn't need it and we never read it
- "Set as default" checkbox and the terms line stay
- everything around the sheet stays exactly as drawn

The sheet gets shorter. Worth a look to see if the spacing wants rebalancing.

### Select Payment Method — retitle
Drawn as a step during booking, implying you pick a card per ride. Payment always
uses your default card; there is no per-ride choice.

The screen still has a job — it's where you **set your default card**. Retitle to
something like "Default Payment Method", and it belongs in the account section
rather than mid-booking. (We still route here when someone tries to book with no
card saved.)

### Sign up — three changes
1. **Remove the line "Login using your credentials provided by the company."**
   That describes an invite flow. Riders sign themselves up.
2. **Phone Number stays but is optional** — please mark it as such. It can be
   added later in Personal Information.
3. The 18+ checkbox stays.

### Personal Information — two changes
1. **Remove the City field.** Not stored anywhere.
2. The notice *"Your full name and profile picture are verified. To update them,
   please contact Support"* contradicts the editable name field and Save button
   directly above it. Riders **can** edit their own name and photo. Either drop
   the notice, or make the fields read-only — your call, but the screen can't say
   both.

### Select Vehicle — six categories, and the numbers differ
The board shows four vehicles (Standard, Estate, MPV, Minibus) with seats/bags on
each. The live catalogue has **six**, and three of the four drawn have different
capacities:

| | Drawn | Live |
|---|---|---|
| Standard | 4 seats 2 bags | 4 seats 2 bags ✓ |
| Estate | 4 seats 4 bags | **5 seats 4 bags** |
| MPV | 6 seats 4 bags | **7 seats 5 bags** |
| Minibus | 16 seats 12 bags | **8 seats 6 bags** |
| MiniCar | — | 4 seats 2 bags |
| MiniTruck | — | 7 seats 2 bags |

We pull these from the system at runtime, so the numbers correct themselves — no
action needed there. What we do need is a **layout that holds six cards rather
than four**, since the current 2×2 grid fills exactly. And MiniCar / MiniTruck
have no illustrations yet.

Minibus is the one worth a sanity check — 16 seats drawn vs 8 configured is a big
gap, so one of the two is wrong. Worth confirming what's actually being operated.

### Ride History — row content
The row shows origin, destination, fare and a rating. That data is available but
needs a backend change we've requested; it isn't guaranteed for the first build.

**A loading and a reduced state would help** — what the row looks like when the
addresses haven't resolved yet (they can legitimately be blank), and what it looks
like with date/time/status only.

### Conversation (chat) — strip to text
Drawn with attachments (paperclip), voice notes (mic), an "Online" presence
indicator and a call button. Messaging is **text only** — no file storage, no
voice, no presence tracking, and no phone number is exposed to the rider.

Please redraw as a plain text conversation: message bubbles, text input, send.

**The call button** — we can open the phone dialer, but we have no number to dial
and no masked-calling service, so it would be a dead button. Suggest removing it.
If riders need to reach drivers by phone, that's a platform decision worth raising
separately.

### Start Ride — the instruction banner
"Take left after 1.5 mi" implies turn-by-turn navigation. We can draw the route
line, but we get no turn instructions — and the rider isn't driving, so it's the
driver's app that needs those.

Suggest replacing that banner with trip status ("On the way to your destination"),
ETA, or removing it. The "Active Ride – Navigating to Destination" banner above it
already covers the intent.

---

## 3. Things we need drawn

### Searching for a driver
The gap left by removing "Choose your driver". Between Confirm Booking and the
driver being assigned there's a real wait — the system is matching. Needs a state:
map, some indication of searching, and a way to cancel.

### Forgot Password — sent confirmation
"We've emailed you a reset link" end state.

### No payment method
Booking is blocked when no card is saved. Needs an empty state on Payment Methods
prompting to add one, and something for the blocked-booking moment.

### Booking error states
Real cases the rider can hit at Confirm Booking:
- outside our service area
- already has an active trip
- account suspended
- no payment method

Currently there's nowhere for these to surface. Even one reusable error sheet
would cover them.

### Dark mode
Settings offers Dark / Light / Default and we're building all three, but only
light is drawn. We'd rather not invent the dark palette ourselves — even tokens
(surfaces, text, borders, elevation) plus two or three key screens would be enough
to derive the rest.

### Empty states
Ride History, Notifications, Promotional and Payment Methods can all be empty on
day one. Currently all four are drawn full.

---

## 4. Things that were right (no change)

Worth saying, since it saved us guesswork:

- **Fare breakdown** — Base Fare / Distance / Time / Wait Time is exactly how
  pricing computes. Surge too: it's set by staff in the admin panel, so "Surge
  1.5x" is a real, correct label.
- **Vehicle cards** — the "4 Seats 2 Bags" pattern is exactly right; the card
  design works as-is. (The specific numbers and the count need a tweak — see above.)
- **Suggestion / Saved tabs** on Enter Your Route match how search actually
  behaves — saved places really do rank above map results.
- **Settings toggles** map almost one-to-one onto stored preferences, including
  Appearance's Dark/Light/Default.
- **Notifications** Read/Unread tabs work as drawn.
- **Promotional** Active/Availed/Expired are the real three states.
- **Multi-stop** (the A → B midpoint → C route, and the `+` on Enter Your Route)
  is genuinely supported.
- **Cancellation policy card**, including the timing tiers and fees, matches the
  real rules.
- **Trip receipt Download** works.

---

## Summary

| | |
|---|---|
| Remove | Choose your driver · OTP · Reset Password · Expired-link · Wallet (3 places) · PayPal |
| Change | Add Card sheet (Stripe field) · Select Payment Method (retitle + move) · Sign up (copy, optional phone) · Personal Information (City, notice) · Select Vehicle (six cards) · Ride History (states) · Chat (text only) · Start Ride (banner) |
| Draw | Searching for driver · Forgot Password sent · No payment method · Booking errors · Dark mode · Empty states · MiniCar + MiniTruck illustrations |

Happy to walk through any of these — particularly the driver-matching change and
the chat one, since those are the biggest departures from what's drawn.
