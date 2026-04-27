#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/.build/debug/TaskMgmtMac.app"
EXECUTABLE="$ROOT_DIR/.build/debug/TaskMgmtMac"
PLIST="$APP_DIR/Contents/Info.plist"

focus_app() {
  local attempts="${TASKMGMT_FOCUS_ATTEMPTS:-8}"
  local delay_seconds="${TASKMGMT_FOCUS_DELAY_SECONDS:-0.5}"

  for ((attempt = 1; attempt <= attempts; attempt++)); do
    sleep "$delay_seconds"
    osascript >/dev/null 2>&1 <<'APPLESCRIPT' || true
tell application id "com.xmodern.TaskMgmtMac" to activate
tell application "System Events"
    set frontmost of first process whose bundle identifier is "com.xmodern.TaskMgmtMac" to true
end tell
APPLESCRIPT
  done
}

codesign_identity() {
  if [ -n "${TASKMGMT_CODESIGN_IDENTITY:-}" ]; then
    printf '%s\n' "$TASKMGMT_CODESIGN_IDENTITY"
    return
  fi

  security find-identity -v -p codesigning 2>/dev/null \
    | awk -F '"' '/Apple Development|Developer ID Application/ { print $2; exit }'
}

cd "$ROOT_DIR"
swift build

osascript -e 'tell application "TaskMgmtMac" to quit' 2>/dev/null || true
sleep 1
pkill -x TaskMgmtMac 2>/dev/null || true

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
cp "$EXECUTABLE" "$APP_DIR/Contents/MacOS/TaskMgmtMac"

plutil -create xml1 "$PLIST"
/usr/libexec/PlistBuddy \
  -c "Add :CFBundleExecutable string TaskMgmtMac" \
  -c "Add :CFBundleIdentifier string com.xmodern.TaskMgmtMac" \
  -c "Add :CFBundleName string TaskMgmtMac" \
  -c "Add :CFBundlePackageType string APPL" \
  -c "Add :CFBundleVersion string 1" \
  -c "Add :CFBundleShortVersionString string 0.1" \
  -c "Add :LSMinimumSystemVersion string 14.0" \
  "$PLIST"

SIGN_IDENTITY="$(codesign_identity)"
if [ -z "$SIGN_IDENTITY" ]; then
    echo "Warning: no Apple Development/Developer ID signing identity found; using ad-hoc signing."
    SIGN_IDENTITY="-"
fi

codesign --force --options runtime --sign "$SIGN_IDENTITY" "$APP_DIR"

open "$APP_DIR"
focus_app
