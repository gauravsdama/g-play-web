#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_BUNDLE="$ROOT_DIR/.build/macos/G Play.app"
MACNESS_BIN="${MACNESS_BIN:-/Users/gauravsdama/git/macness/.build/release/macness}"

if [[ ! -x "$MACNESS_BIN" ]]; then
  swift build -c release --package-path /Users/gauravsdama/git/macness
fi

if [[ ! -d "$APP_BUNDLE" ]]; then
  "$ROOT_DIR/macos/scripts/build_app.sh"
fi

"$MACNESS_BIN" launch --app "$APP_BUNDLE" --fresh --wait 7
"$MACNESS_BIN" verify \
  --bundle-id com.gauravsdama.gplay \
  --expect-window "G Play" \
  --label gplay-native \
  --no-screenshot
