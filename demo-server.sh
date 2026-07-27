#!/usr/bin/env bash
# HOPPIN Rider — build the web app and serve it locally.
#
#   bash demo-server.sh          # build + serve on :8100
#   bash demo-server.sh --serve  # serve an existing build (skip the rebuild)
#
# Rider -> http://localhost:8100
#
# Adapted from the monorepo demo server for this standalone repo (the app now
# lives at ./rider_app rather than ./apps/rider).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLUTTER="${FLUTTER:-flutter}"
APP_DIR="$ROOT/rider_app"
DEFINES="$APP_DIR/riderdefines.json"
PORT=8100

if [ ! -f "$DEFINES" ]; then
  echo "ERROR: $DEFINES not found."
  echo "       cp rider_app/riderdefines.example.json rider_app/riderdefines.json"
  echo "       then fill in the real Supabase values."
  exit 1
fi

if [ "${1:-}" != "--serve" ]; then
  echo "Building rider web (release)..."
  ( cd "$APP_DIR" && "$FLUTTER" build web --release \
      --dart-define-from-file=riderdefines.json )
fi

echo "Serving http://localhost:$PORT  (Ctrl-C to stop)"
cd "$APP_DIR/build/web" && python -m http.server "$PORT"
