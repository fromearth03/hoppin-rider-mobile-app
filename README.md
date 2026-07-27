# Hoppin Rider — Mobile App

The rider-facing Flutter app for Hoppin, a UK ride-hailing platform (West
Midlands / Wolverhampton licensing area). Builds for web and mobile; the demo
runs as a web build.

## Layout

A Dart pub **workspace** — the app and its shared packages side by side:

```
pubspec.yaml           workspace root
rider_app/             the Flutter app (lib, web, test)
packages/
  hoppin_shared/       API client, repositories, models, providers
  hoppin_ui/           design system (tokens, components)
  hoppin_demo/         offline demo world + fake repositories
```

The three packages are vendored copies shared with the driver app; keep changes
to them in sync across the two repos.

## Setup

1. Install Flutter (3.12+).
2. Copy the config template and fill in real values:
   ```
   cp rider_app/riderdefines.example.json rider_app/riderdefines.json
   ```
   `riderdefines.json` holds the Supabase key + demo credentials and is
   git-ignored — never commit it.
3. Resolve dependencies from the repo root:
   ```
   flutter pub get
   ```

## Build & run

```
cd rider_app
flutter run -d chrome --dart-define-from-file=riderdefines.json     # web
flutter build web --release --dart-define-from-file=riderdefines.json
```

## Test

```
flutter test
```
