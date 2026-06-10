#!/usr/bin/env bash
# Seed ~/.terminalmanager (or TERMINALMANAGER_CONFIG directory) from config.toml.example
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXAMPLE="$ROOT/config.toml.example"

resolve_config_dir() {
  if [[ -n "${TERMINALMANAGER_CONFIG:-}" ]]; then
    local target="$TERMINALMANAGER_CONFIG"
    if [[ -f "$target" && "${target##*.}" == "toml" ]]; then
      dirname "$target"
    else
      echo "$target"
    fi
  else
    echo "$HOME/.terminalmanager"
  fi
}

CONFIG_DIR="$(resolve_config_dir)"
CONFIG_FILE="$CONFIG_DIR/config.toml"
SESSIONS_FILE="$CONFIG_DIR/sessions.json"

mkdir -p "$CONFIG_DIR"

if [[ ! -f "$CONFIG_FILE" ]]; then
  cp "$EXAMPLE" "$CONFIG_FILE"
  echo "Created $CONFIG_FILE"
else
  echo "Config already exists: $CONFIG_FILE"
fi

if [[ ! -f "$SESSIONS_FILE" ]]; then
  cat >"$SESSIONS_FILE" <<'EOF'
{
  "version": 1,
  "sessionTree": []
}
EOF
  echo "Created $SESSIONS_FILE"
fi

mkdir -p "$CONFIG_DIR/logs"
echo "Config directory ready: $CONFIG_DIR"
