# Payment Methods — Stripe integration spec

Goal: keep the card screen clean and keep the PCI audit at **SAQ A**, by never
letting a raw card number touch our code.

## Why SAQ A

Storage is already clean — the DB holds only `rider_profiles.stripe_customer_id`
and `.default_stripe_payment_method_id`, plus the censored
`{brand, last4, expMonth, expYear}` Stripe returns. No PAN, no CVV, ever.

But PCI scope is set by what **transits the app**, not by what is persisted. A
card number typed into a `TextField` we own sits in our process memory and widget
tree — that is SAQ A-EP/D territory even when it is sent straight to Stripe and
never stored. Using Stripe's own SDK field keeps the PAN entirely outside our
code: **SAQ A**, the smallest audit.

The Figma card form (Card Number / Card Holder Name / Expiry / CVV as our own
inputs) is therefore replaced by the Stripe SDK field. Same screen, same layout,
one widget swapped.

## Package

`flutter_stripe` — the official Stripe Flutter SDK. `CardField` renders a
single-line, PCI-safe input Stripe controls.

Init once at boot, publishable key injected at build time:

```dart
// main.dart
Stripe.publishableKey = const String.fromEnvironment('STRIPE_PUBLISHABLE_KEY');
await Stripe.instance.applySettings();
```

```
flutter run --dart-define=STRIPE_PUBLISHABLE_KEY=pk_test_…
```

The key is public by design and safe to ship. It is **not** fetched at runtime:
`GET :8090/api/payments/config` sits behind the shared internal token and is
unreachable from the app. If the define is empty, disable "Add card" and say card
entry is unavailable in this build — do not fail silently.

## Endpoints

All on `Go_ride_service :8080`, rider JWT + `X-Hoppin-Device-ID`.
The app never talks to `:8090`.

| Call | Purpose |
|---|---|
| `POST /api/v1/me/payment-methods/setup-intent` | → `{setupIntentId, clientSecret, customerId, provider}` |
| `GET /api/v1/me/payment-methods` | → `[{paymentMethodId, brand, last4, expMonth, expYear, isDefault}]` (bare array) |
| `POST /api/v1/me/payment-methods/:pmId/default` | → `{payment_method_id, default:true}` |
| `DELETE /api/v1/me/payment-methods/:pmId` | remove |
| `GET /api/v1/me/transactions` | Recent Payments list |

**These DTOs are camelCase** while the rest of the API is snake_case — the
payment service's shapes are passed through verbatim. Isolate that in the
payment models; do not let camelCase leak into the app's other models.

## Add-card flow

```
1. POST /me/payment-methods/setup-intent      → clientSecret
2. Stripe.instance.confirmSetupIntent(...)    → SDK collects the card
3. GET /me/payment-methods                    → refresh the list
4. (optional) POST /me/payment-methods/:id/default
```

```dart
final res = await api.createSetupIntent();
await Stripe.instance.confirmSetupIntent(
  paymentIntentClientSecret: res.clientSecret,
  params: const PaymentMethodParams.card(
    paymentMethodData: PaymentMethodData(),
  ),
);
await refreshCards();
```

Step 2 handles 3-D Secure on its own — no extra screen. Nothing about the card is
POSTed by us; the SDK talks to Stripe directly using the `clientSecret`.

## Screen — Payment Methods

Keep the Figma layout. Saved cards list, then Recent Payments, then a primary
"Add Payment Method" action.

**Sheet contents (replaces the four drawn inputs):**
- one `CardField` (number, expiry, CVC in a single Stripe-owned row)
- "Set as default" checkbox
- the terms line
- Save / Cancel

Drop **Card Holder Name** — Stripe does not require it for card setup and the
backend never reads it. One field fewer, nothing lost.

**Card rows** render `brand` + `•••• last4` from the API. The green check is
`isDefault`. Tap sets default; swipe or overflow removes.

**Wallet and PayPal rows are not built.** There is no in-app wallet and no PayPal
integration. Cards only.

**Refund copy** says the refund returns to the card — never "to your wallet".

## States to build

| State | Trigger |
|---|---|
| Empty | no cards — prompt to add, since `402 NO_PAYMENT_METHOD` blocks booking |
| Loading | during setup-intent and confirm |
| Card declined | Stripe `StripeException` from `confirmSetupIntent` — show `error.localizedMessage` |
| `503 PAYMENTS_DISABLED` | payments off — "not available right now", keep the list readable |
| `502 PAYMENT_ERROR` | provider failure — generic retry; the real cause is server-logged |
| Key missing | `STRIPE_PUBLISHABLE_KEY` empty — disable Add, explain |

`paymentError` (`payments_handler.go:52`) only ever returns those two codes, so
those are the only server failures to handle here.

## Booking interaction

There is **no per-ride payment selection** — booking always charges the default
card. So "Select Payment Method" is not a booking step; it is *set your default
card*, and must be worded that way. `402 NO_PAYMENT_METHOD` on
`POST /rides/request` routes the rider here.

## Rules

- Never build our own PAN/CVV/expiry inputs. The SDK field or nothing.
- Never log, store or pass card data — we only ever hold `paymentMethodId`.
- Never call `:8090` from the app.
- The publishable key ships in the binary; the secret key never leaves the server.
