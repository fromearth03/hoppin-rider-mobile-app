# Backend — RIDER app (round 4)

**Date:** 2026-08-30 · **Service:** `Go_ride_service` (`api.hoppin.tech`). All live.
Conventions: integer `*_pence`, snake_case, nullables stay `null`.

---

## New / changed

### Profile — date of birth + age gate
`GET`/`PATCH /me/profile` now carry **`date_of_birth`** (`"YYYY-MM-DD"`, validated as
a real past date; nullable).
```jsonc
PATCH /me/profile { "date_of_birth": "2005-04-12" }
GET   /me/profile -> { "full_name","phone_number","email","avatar_url","date_of_birth" }
```
**Age gate:** a rider **under 13** cannot book — booking returns
`403 ACCOUNT_NOT_ELIGIBLE "riders must be 13 or older"`. Collect DOB at signup and
PATCH it, or the gate can't evaluate (no DOB = allowed).

### `GET /me/activity` — enriched money timeline (NEW)
The "where did my money go / why was I charged / which promo" feed. Rider ledger
(charges/refunds/credits/fees) **plus** promo redemptions, server-owned copy, paged.
```jsonc
{ "activity": [{
    "id","created_at","amount_pence":-1257,   // signed: neg = you paid, pos = credited
    "kind":"rider_charge",
    "display_title":"Trip payment","display_reason":"Payment for your trip.",
    "ride_id":"uuid"|null,"promo_code":"FIVER"|null }],
  "next_cursor":"…"|null,"has_more":true }
```
Params: `limit` (≤100), `cursor`.

### Human-readable ref (R-/P-)
`GET /rides` and `GET /rides/:id` now include **`ref`** (e.g. `"R-1042"`);
`GET /me/transactions` includes **`ref`** (e.g. `"P-42"`). Show these instead of UUIDs.

### Ride chat — WhatsApp receipts + reply
- `POST /rides/:id/messages` accepts **`reply_to_id`** (quote a message).
- `GET /rides/:id/messages` — each message has **`status`** on YOUR OWN messages
  (`sent` → `read` once the other party opened the thread) and a **`reply_to`**
  preview `{id, body, sender_role}` when it's a reply. Opening the thread marks it
  read (clears `chat_unread` on `GET /rides/:id`).

---

## Already live (confirmed — from earlier rounds)

- **Card management:** `POST /me/payment-methods/setup-intent` (add a card),
  `GET /me/payment-methods` (list — `brand`/`last4`/`expMonth`/`expYear`/`isDefault`),
  `POST /me/payment-methods/:pmId/default` (set default),
  `DELETE /me/payment-methods/:pmId` (remove). Multiple cards, choose default. ✅
- **Promo invalid code:** `GET /promotions/validate?code=` and apply return clear
  errors — `PROMO_NOT_FOUND "promo code not found"`, `PROMO_INACTIVE`,
  `PROMO_EXHAUSTED`, `PROMO_USED`. ✅
- **Recent payments:** `GET /me/transactions` — amount, status, place labels,
  **card brand/last4** ("Visa ••8901"), and now `ref`. ✅
- **Notifications** badge + cursor, **promotions** rider-aware (availed/state),
  **scheduled rides** enriched (coords/fare/labels), **`/me/active-ride`**,
  **`PATCH /me/saved-locations/:id`** (rename). ✅

## Pagination
Every list is cursor-paged: `/me/activity`, `/rides`, `/me/notifications`,
`/me/transactions` (limit/offset). Pattern: pass back `next_cursor` until
`has_more:false`.
