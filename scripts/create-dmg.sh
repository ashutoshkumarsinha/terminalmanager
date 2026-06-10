#!/usr/bin/env bash
# Build a release Terminal Manager.app and package it as a distributable DMG.
# Usage: scripts/create-dmg.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="Terminal Manager.app"
VERSION="$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$ROOT/Resources/Info.plist")"
DMG_NAME="Terminal Manager-${VERSION}.dmg"
DIST_DIR="$ROOT/dist"
DMG_PATH="$DIST_DIR/$DMG_NAME"
STAGING="$(mktemp -d)"

cleanup() {
  rm -rf "$STAGING"
}
trap cleanup EXIT

echo "Building release binary..."
swift build -c release

echo "Assembling app bundle..."
bash "$ROOT/scripts/package-app.sh" release

mkdir -p "$DIST_DIR"
rm -f "$DMG_PATH"

cp -R "$ROOT/$APP_NAME" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

echo "Creating DMG..."
hdiutil create \
  -volname "Terminal Manager" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

echo "Created $DMG_PATH"
