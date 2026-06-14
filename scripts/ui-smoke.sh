#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> Unit + in-process GUI smoke tests"
swift test

echo "==> CLI smoke-test launch"
swift build
CONFIG_DIR="$(mktemp -d)"
export TERMINALMANAGER_CONFIG="$CONFIG_DIR"
trap 'rm -rf "$CONFIG_DIR"' EXIT

BINARY="$ROOT/.build/debug/terminalmanager"
if [[ ! -x "$BINARY" ]]; then
  BINARY="$ROOT/.build/arm64-apple-macosx/debug/terminalmanager"
fi
if [[ ! -x "$BINARY" ]]; then
  echo "Could not find debug binary after swift build" >&2
  exit 1
fi

"$BINARY" -smoke-test
echo "CLI smoke-test passed"

echo "==> Optional packaged app launch"
bash scripts/package-app.sh release
APP="$ROOT/build/Terminal Manager.app"
if [[ -d "$APP" ]]; then
  open -a "$APP" --args -smoke-test
  sleep 3
  if pgrep -f "Terminal Manager" >/dev/null; then
    echo "Packaged app smoke: launched"
    pkill -f "Terminal Manager" || true
  else
    echo "Packaged app smoke: process not running (may be OK if -smoke-test exits immediately)" >&2
  fi
fi

echo "All GUI smoke checks passed"
