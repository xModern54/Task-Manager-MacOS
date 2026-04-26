#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/.build/debug/TaskMgmtMac.app"
EXECUTABLE="$ROOT_DIR/.build/debug/TaskMgmtMac"
HELPER_EXECUTABLE="$ROOT_DIR/.build/debug/TaskMgmtMacPrivilegedSensorHelper"
HELPER_PLIST_SOURCE="$ROOT_DIR/Resources/LaunchDaemons/com.xmodern.TaskMgmtMac.PrivilegedSensorHelper.plist"
PLIST="$APP_DIR/Contents/Info.plist"

cd "$ROOT_DIR"
swift build

pkill -x TaskMgmtMac 2>/dev/null || true

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Library/LaunchDaemons"
cp "$EXECUTABLE" "$APP_DIR/Contents/MacOS/TaskMgmtMac"
cp "$HELPER_EXECUTABLE" "$APP_DIR/Contents/MacOS/TaskMgmtMacPrivilegedSensorHelper"
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

codesign --force --sign - "$APP_DIR/Contents/MacOS/TaskMgmtMacPrivilegedSensorHelper"
codesign --force --sign - --deep "$APP_DIR"

open "$APP_DIR"
