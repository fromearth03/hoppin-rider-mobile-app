# ASK-3 — account lifecycle and support tickets

Raised 2026-08-31 while building the new design-pack screens (Help & Support,
Logout, Delete Account, Support). None of these blocks the demo; they block
three drawn controls from going live.

## R1 — Deactivate account (temporary)

`Delete Account.png` offers "Temporarily Deletion": hide the account, keep the
data, block booking. No endpoint exists for this on the rider surface. The
screen ships with the button genuinely disabled until one does.

Suggested shape: `POST /me/deactivate` (idempotent), plus whatever sign-in
behaviour a deactivated rider should see (`403` with a distinct error code
would let the app say the right thing).

## R2 — Delete account (permanent)

Same frame, "Permanent Deletion": erase ride history and personal data,
irreversible. No endpoint exists. Same disabled-button treatment until one
does. This one likely has legal/GDPR shape decisions that belong to you — the
app just needs a call to make and a definitive success signal to sign out on.

## R3 — Support tickets

`Help & Support.png` draws an "Open Ticket" card and `Support.png` draws a
full ticket form (category, description, preferred resolution, recent issues
with statuses). There is no ticket endpoint anywhere in the rider API. The
card ships disabled; the form is not built.

Note before building anything: `Support.png` appears to be a **driver-app
frame** — "Preferred Resolution: Generate Payout" and "Low Rating Appeal"
are driver vocabulary. We have asked the designer for a rider version. If
tickets are wanted at all, the minimal rider shape is `POST /support/tickets`
(category, description) and `GET /support/tickets` for the list with status.

## Not asking for these

| Considered | Left alone because |
|---|---|
| Legal documents endpoint (terms, privacy) | Static documents; a hosted URL or bundled text decided at product level beats an API for two rows. |
| Email support | Already works — the screen shows Support@hoppin.com as plain text. |

## Register

| Ask | Items | Status |
|---|---|---|
| ASK-1 (`FOR-BACKEND.md`) | R1–R5 | Delivered |
| ASK-2 (`ASK-2-FOR-BACKEND.md`) | R1 turn-by-turn, R2 rider rating | Open, low priority |
| ASK-3 (this file) | R1 deactivate, R2 delete, R3 tickets | Sent to backend 2026-09-01 |
