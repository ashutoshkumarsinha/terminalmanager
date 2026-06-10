#!/usr/bin/env bash
# Build Terminal Manager.app (debug) and open it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIG="${1:-debug}"
BOOTSTRAP="${BOOTSTRAP_CONFIG:-1}"

if [[ "$BOOTSTRAP" == "1" ]]; then
  "$ROOT/scripts/bootstrap-config.sh"
fi

"$ROOT/scripts/package-app.sh" "$CONFIG"
open "$ROOT/Terminal Manager.app"
