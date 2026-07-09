#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MACOS_DIR="$ROOT_DIR/macos"
SWIFT_PACKAGE_DIR="$MACOS_DIR/GPlayMac"
APP_BUILD_DIR="$ROOT_DIR/.build/macos"
APP_BUNDLE="$APP_BUILD_DIR/vantabeat.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
BACKEND_DIR="$ROOT_DIR/backend"
PYTHON_BIN="${PYTHON_BIN:-}"

if [[ -z "$PYTHON_BIN" ]]; then
  if command -v python3.12 >/dev/null 2>&1; then
    PYTHON_BIN="$(command -v python3.12)"
  elif command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN="$(command -v python3)"
  else
    echo "python3 is required" >&2
    exit 1
  fi
fi

echo "==> Building native shell"
swift build -c release --package-path "$SWIFT_PACKAGE_DIR"

echo "==> Assembling app bundle"
rm -rf "$APP_BUNDLE"
mkdir -p "$CONTENTS_DIR/MacOS" "$RESOURCES_DIR"
cp "$SWIFT_PACKAGE_DIR/.build/release/GPlayMac" "$CONTENTS_DIR/MacOS/vantabeat"
cp "$MACOS_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"

rsync -a --delete \
  --exclude '__pycache__' \
  "$BACKEND_DIR/" "$RESOURCES_DIR/backend/"

if [[ "${VANTABEAT_DEV_DATA_ROOT:-0}" == "1" ]]; then
  printf '%s\n' "$ROOT_DIR" > "$RESOURCES_DIR/vantabeat-project-root.txt"
fi

echo "==> Creating bundled Python environment"
"$PYTHON_BIN" -m venv "$RESOURCES_DIR/venv"
"$RESOURCES_DIR/venv/bin/python" -m pip install --upgrade pip
"$RESOURCES_DIR/venv/bin/python" -m pip install -r "$BACKEND_DIR/requirements.txt"

cat > "$CONTENTS_DIR/PkgInfo" <<'PKGINFO'
APPL????
PKGINFO

echo "Built: $APP_BUNDLE"
echo "Run:   open '$APP_BUNDLE'"
