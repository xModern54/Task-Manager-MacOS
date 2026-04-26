#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/.build/debug/TaskMgmtMac.app"
EXECUTABLE="$ROOT_DIR/.build/debug/TaskMgmtMac"
HELPER_EXECUTABLE="$ROOT_DIR/.build/debug/TaskMgmtMacPrivilegedSensorHelper"
HELPER_PLIST_SOURCE="$ROOT_DIR/Resources/LaunchDaemons/com.xmodern.TaskMgmtMac.PrivilegedSensorHelper.plist"
PLIST="$APP_DIR/Contents/Info.plist"
HELPER_BUNDLE_ID="com.xmodern.TaskMgmtMac.PrivilegedSensorHelper"

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

pkill -x TaskMgmtMac 2>/dev/null || true

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Library/LaunchDaemons"
mkdir -p "$APP_DIR/Contents/Library/LaunchServices"
cp "$EXECUTABLE" "$APP_DIR/Contents/MacOS/TaskMgmtMac"
cp "$HELPER_EXECUTABLE" "$APP_DIR/Contents/Library/LaunchServices/TaskMgmtMacPrivilegedSensorHelper"
cp "$HELPER_PLIST_SOURCE" "$APP_DIR/Contents/Library/LaunchDaemons/com.xmodern.TaskMgmtMac.PrivilegedSensorHelper.plist"

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
  echo "         The privileged helper will build, but macOS will block it until the app is signed with a Team ID."
  SIGN_IDENTITY="-"
fi

codesign --force --sign "$SIGN_IDENTITY" --identifier "$HELPER_BUNDLE_ID" "$APP_DIR/Contents/Library/LaunchServices/TaskMgmtMacPrivilegedSensorHelper"
codesign --force --sign "$SIGN_IDENTITY" "$APP_DIR"

open "$APP_DIR"
