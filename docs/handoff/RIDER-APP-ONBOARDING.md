# Rider app — developer onboarding

Everything needed to build, run, and continue this app. Written for someone
with Flutter experience and zero context on this codebase.

## What this is

The Hoppin rider app (Flutter), built screen-by-screen against the Figma
pack in `docs/figma/` and the live Go backend at `https://api.hoppin.tech`.
Work happens on the **`feat/batch-1-auth`** branch.

## Setup — nothing to ask anyone for

1. Flutter stable (Dart SDK ≥ 3.12 per `app/pubspec.yaml`).
2. Clone, then from `app/`: `flutter pub get`.
3. Run the suite: `flutter test` (~10 min, 460+ tests, all green at handoff).
4. Run on web:
   `flutter build web --dart-define-from-file=../config/dev.json`
   then from the repo root: `powershell -File serve-web.ps1` →
   http://127.0.0.1:8080. (`flutter run -d chrome
   --dart-define-from-file=../config/dev.json` also works for hot reload.)
5. Android test build:
   `flutter build apk --debug --dart-define-from-file=../config/dev.json`.

`config/dev.json` is IN the repo and carries only client-safe publishable
values (Supabase anon key, Stripe pk_test, public URLs). Never add anything
secret to it — see the note in `.gitignore`.

**The one thing to request from Ismail: a test rider login** (email +
password) for signing into the live backend.

## The three documents that answer "why is it built like this"

1. **`docs/SCREEN-DECISIONS.md`** — every screen's deviations from the Figma
   and the reason. Anything not recorded there is supposed to match the
   frame exactly.
2. **`docs/handoff/ASK-3-FOR-BACKEND.md`** (and ASK-1/ASK-2) — what the
   backend owes us; the register at the bottom tracks status.
3. **`docs/superpowers/plans/`** — dated implementation plans, including the
   two most recent (booking-flow wiring, live-findings batch) which describe
   in-flight work task by task.

## House rules (non-negotiable, from the owner)

- **No demo fakeness.** Nothing stubbed or mocked in the product. A control
  with no backend renders genuinely disabled with a "Soon" badge — never a
  live-looking button wired to nothing, and NEVER fabricated data (no fake
  drivers, ratings, or fares).
- **Server-owned copy renders verbatim.** Error messages come from the API.
- **`Pence`, never a double, for money.** Models mirror the Go structs.
- **`Result<T>` over exceptions** at every repository boundary.
- **Read the Go source, not the handover docs.** The backend repos are the
  contract; the older docs were wrong on 14+ counts. Backend code lives in
  the `fromearth03` org (ask Ismail for access if you need it).
- **Design fidelity is verified by rendering**, not by reading: golden
  shots (`app/test/golden/`, run a file with `--run-skipped
  --update-goldens`) get put NEXT TO the frame PNGs in
  `docs/figma/extracted/` at 430px AND 320px. Zero of the ~15 real visual
  defects found so far were caught by unit tests.
- Full test-first (TDD). Frequent small commits, conventional messages.

## State at handoff (2026-09-01)

- 27 screens; booking flow wired end to end (home → route entry → fare
  quotes → book → live trip); Google Maps live on Android (key in the
  manifest, restricted); Poppins bundled; light theme default.
- **Driver-side is not live yet** — dispatch never assigns, so every booked
  ride sits honestly in "finding your driver". The moment the driver app
  accepts jobs, `GET /rides/:id` starts returning `driver` and the trip
  screens fill.
- Release APK is blocked by flutter_stripe 11.5 (its Google Pay dependency
  vanished from Google's Maven; upgrade to 14.x is the fix). Debug APK
  works: `app/build/app/outputs/flutter-apk/app-debug.apk`.
- In-flight plan: `docs/superpowers/plans/2026-09-01-live-findings-batch.md`
  — cancel-ride wiring (done), schedule-screen exit, scheduled rides
  (backend routes exist: `POST/GET/DELETE /scheduled-rides`, pickup ≥30 min
  ahead), ride-context repository (`GET /rides/:id`), Ride Details +
  payment sheet UI to frame.

## Known gaps that are NOT bugs

- Web map shows a placeholder — the committed key is Android-only by
  restriction; a Maps JavaScript API key would be a separate product.
- Open Ticket, Legal rows, Delete Account buttons, PayPal/Wallet: disabled
  because no endpoint/documents exist (ASK-3 / decisions doc).
- Footer logo says "Hoppin' Admin" — waiting on the wordmark vector.
- "Hello3"/"Hellotest2" vehicle categories are junk rows in the admin DB.
