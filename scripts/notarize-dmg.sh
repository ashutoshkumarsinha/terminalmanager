#!/usr/bin/env bash
# Sign and notarize a release DMG (requires Apple Developer credentials).
# Usage:
#   export APPLE_ID="you@example.com"
#   export APPLE_TEAM_ID="XXXXXXXXXX"
#   export APPLE_ID_PASSWORD="@keychain:AC_PASSWORD"
#   bash scripts/notarize-dmg.sh [path/to.dmg]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DMG="${1:-dist/Terminal Manager-1.0.0.dmg}"
IDENTITY="${SIGNING_IDENTITY:-Developer ID Application}"

if [[ ! -f "$DMG" ]]; then
  echo "DMG not found: $DMG — run make dmg first" >&2
  exit 1
fi

if [[ -z "${APPLE_ID:-}" || -z "${APPLE_TEAM_ID:-}" || -z "${APPLE_ID_PASSWORD:-}" ]]; then
  echo "Set APPLE_ID, APPLE_TEAM_ID, and APPLE_ID_PASSWORD to notarize." >&2
  exit 1
fi

APP="$ROOT/Terminal Manager.app"
if [[ ! -d "$APP" ]]; then
  bash scripts/package-app.sh release
fi

echo "Signing app..."
codesign --force --deep --options runtime --sign "$IDENTITY" "$APP"

echo "Rebuilding DMG with signed app..."
bash scripts/create-dmg.sh

echo "Submitting for notarization..."
xcrun notarytool submit "$DMG" \
  --apple-id "$APPLE_ID" \
  --team-id "$APPLE_TEAM_ID" \
  --password "$APPLE_ID_PASSWORD" \
  --wait

echo "Stapling ticket..."
xcrun stapler staple "$DMG"

echo "Done: $DMG"
