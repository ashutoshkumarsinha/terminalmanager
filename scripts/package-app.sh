#!/usr/bin/env bash
# Build terminalmanager and assemble Terminal Manager.app bundle.
# Usage: scripts/package-app.sh [debug|release]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIG="${1:-debug}"
PRODUCT=".build/$CONFIG/terminalmanager"
APP_NAME="Terminal Manager.app"
APP_DIR="$ROOT/$APP_NAME"
CONTENTS="$APP_DIR/Contents"

if [[ "$CONFIG" != "debug" && "$CONFIG" != "release" ]]; then
  echo "Usage: $0 [debug|release]" >&2
  exit 1
fi

if [[ ! -f "$PRODUCT" ]]; then
  echo "Building terminalmanager ($CONFIG)..."
  swift build -c "$CONFIG"
fi

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$PRODUCT" "$CONTENTS/MacOS/terminalmanager"
chmod +x "$CONTENTS/MacOS/terminalmanager"

if [[ "$CONFIG" == "release" ]]; then
  strip -x "$CONTENTS/MacOS/terminalmanager"
fi
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"

# Ship example config inside the bundle for reference.
cp "$ROOT/config.toml.example" "$CONTENTS/Resources/config.toml.example"
cp "$ROOT/docs/USER_GUIDE.md" "$CONTENTS/Resources/USER_GUIDE.md"

ICON_SRC="$ROOT/terminal.png"
if [[ -f "$ICON_SRC" ]]; then
  ICONSET="$(mktemp -d)/AppIcon.iconset"
  mkdir -p "$ICONSET"
  # macOS icon sizes; omit 1024@2x — rarely used and saves ~80 KB in the bundle.
  sips -z 16 16 "$ICON_SRC" --out "$ICONSET/icon_16x16.png" >/dev/null
  sips -z 32 32 "$ICON_SRC" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
  sips -z 32 32 "$ICON_SRC" --out "$ICONSET/icon_32x32.png" >/dev/null
  sips -z 64 64 "$ICON_SRC" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
  sips -z 128 128 "$ICON_SRC" --out "$ICONSET/icon_128x128.png" >/dev/null
  sips -z 256 256 "$ICON_SRC" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
  sips -z 256 256 "$ICON_SRC" --out "$ICONSET/icon_256x256.png" >/dev/null
  sips -z 512 512 "$ICON_SRC" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
  sips -z 512 512 "$ICON_SRC" --out "$ICONSET/icon_512x512.png" >/dev/null
  iconutil -c icns "$ICONSET" -o "$CONTENTS/Resources/AppIcon.icns"
  rm -rf "$(dirname "$ICONSET")"
else
  echo "Warning: $ICON_SRC not found; app will use the default icon." >&2
fi

echo "Created $APP_DIR ($CONFIG)"
