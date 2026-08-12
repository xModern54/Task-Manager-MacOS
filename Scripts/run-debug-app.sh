#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
STAGING_APP_DIR="$ROOT_DIR/.build/debug/Task Manager.app"
APP_DIR="$ROOT_DIR/Task Manager.app"
EXECUTABLE="$ROOT_DIR/.build/debug/TaskMgmtMac"
HELPER_EXECUTABLE="$ROOT_DIR/.build/debug/TaskMgmtMacPrivilegedHelper"
HELPER_LABEL="com.xmodern.TaskMgmtMac.PrivilegedHelper"
HELPER_PLIST_SOURCE="$ROOT_DIR/Resources/LaunchDaemons/$HELPER_LABEL.plist"
HELPER_BUNDLE_EXECUTABLE="$STAGING_APP_DIR/Contents/Resources/TaskMgmtMacPrivilegedHelper"
PLIST="$STAGING_APP_DIR/Contents/Info.plist"

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

osascript -e 'tell application "Task Manager" to quit' 2>/dev/null || true
sleep 1
pkill -x TaskMgmtMac 2>/dev/null || true

rm -rf "$STAGING_APP_DIR"
mkdir -p "$STAGING_APP_DIR/Contents/MacOS"
mkdir -p "$STAGING_APP_DIR/Contents/Resources"
mkdir -p "$STAGING_APP_DIR/Contents/Library/LaunchDaemons"
cp "$EXECUTABLE" "$STAGING_APP_DIR/Contents/MacOS/TaskMgmtMac"
cp "$HELPER_EXECUTABLE" "$HELPER_BUNDLE_EXECUTABLE"
cp "$HELPER_PLIST_SOURCE" "$STAGING_APP_DIR/Contents/Library/LaunchDaemons/$HELPER_LABEL.plist"
if [ -f "$ROOT_DIR/Resources/AppIcon.icns" ]; then
  cp "$ROOT_DIR/Resources/AppIcon.icns" "$STAGING_APP_DIR/Contents/Resources/AppIcon.icns"
fi

plutil -create xml1 "$PLIST"
/usr/libexec/PlistBuddy \
  -c "Add :CFBundleExecutable string TaskMgmtMac" \
  -c "Add :CFBundleIdentifier string com.xmodern.TaskMgmtMac" \
  -c "Add :CFBundleName string Task Manager" \
  -c "Add :CFBundleDisplayName string Task Manager" \
  -c "Add :CFBundlePackageType string APPL" \
  -c "Add :CFBundleVersion string 1" \
  -c "Add :CFBundleShortVersionString string 0.1" \
  -c "Add :LSMinimumSystemVersion string 14.0" \
  -c "Add :CFBundleIconFile string AppIcon" \
  "$PLIST"

SIGN_IDENTITY="$(codesign_identity)"
if [ -z "$SIGN_IDENTITY" ]; then
    echo "Warning: no Apple Development/Developer ID signing identity found; using ad-hoc signing."
    SIGN_IDENTITY="-"
fi

codesign --force --options runtime --identifier "$HELPER_LABEL" --sign "$SIGN_IDENTITY" "$HELPER_BUNDLE_EXECUTABLE"
codesign --force --options runtime --sign "$SIGN_IDENTITY" "$STAGING_APP_DIR"

rm -rf "$APP_DIR"
mv "$STAGING_APP_DIR" "$APP_DIR"

open -n "$APP_DIR"
focus_app
