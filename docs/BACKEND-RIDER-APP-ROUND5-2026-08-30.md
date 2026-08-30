# Backend — RIDER app (round 5)

**Date:** 2026-08-30 · **Service:** `Go_ride_service` (`api.hoppin.tech`). Live.
Money is integer `*_pence`; nullables stay `null`.

---

## 1. Delete my account (GDPR) — now actually erases

`POST /me/delete-account` (unchanged path) **no longer just flags** the account — it
**executes** the erasure immediately when the account is eligible.

- **Eligible → 200**
  ```jsonc
  { "message": "Your account has been deleted and your personal data erased.",
    "status": "deleted" }
  ```
  After this the session is dead (the account is in a terminal `deleted` state); send
  the user back to the signed-out screen. **Irreversible — show a confirm dialog
  before calling** (e.g. type DELETE / a "yes, delete everything" step).

- **Blocked → 409** (unchanged shape)
  ```jsonc
  { "error":"account cannot be deleted yet", "code":"DELETION_BLOCKED",
    "blockers":["active_trip","unresolved_dispute"] }
  ```
  Blocker codes a rider can hit: `active_trip`, `unresolved_dispute`. Show them and
  let the user resolve, then retry.

**What the backend does** (no app work beyond the confirm + call): scrubs all PII
(name, email, phone, DOB, avatar, address, saved places, emergency contacts, chat
messages, device fingerprints, notifications), and **keeps** your ride/payment
history de-identified for legal/tax retention. Policy: *anonymise + retain
financials*.

---

## 2. Receipt no longer exposes platform commission

`GET /rides/:id/receipt` **no longer returns `platform_commission_pence`**. It was an
internal platform/driver split figure that let a rider back out driver earnings. The
receipt now returns only rider-facing lines:
```jsonc
{ "ride_id","ride_category","fare_pence","waiting_pence","total_pence",
  "currency","status","distance_miles","pickup_time","dropoff_time","provider_payment_id" }
```
If your receipt screen referenced `platform_commission_pence`, remove that row.

---

## Already live (confirmed this round — no app change needed)

- **Notifications**: `GET /me/notifications` is cursor-paged (`cursor`/`limit`,
  `next_cursor`, `has_more`) **and** returns `unread_count` = unread across the whole
  feed (the badge), not just the current page. ✅
- **Scheduled rides dispatch**: a scheduled ride is auto-activated ~15 min before its
  pickup window and published to dispatch to find a driver (with retry) — the rider
  also gets a "we're finding a driver" push. ✅

_Round-4 items (DOB + age gate, `/me/activity`, R-/P- refs, ride-chat receipts +
reply, card management, promo errors) remain as delivered._
