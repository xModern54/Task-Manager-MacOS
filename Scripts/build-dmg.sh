#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

# Detect native architecture and target specific build
ARCH="$(uname -m)"
if [ "$ARCH" = "arm64" ]; then
    DMG_NAME="TaskMgmtMac-Darwin_aarch64-Shipping"
    SWIFT_ARCH="arm64"
    BINARY_SOURCE="$ROOT_DIR/.build/release/TaskMgmtMac"
    HELPER_BINARY_SOURCE="$ROOT_DIR/.build/release/TaskMgmtMacPrivilegedHelper"
else
    DMG_NAME="TaskMgmtMac-Darwin_amd64-Shipping"
    SWIFT_ARCH="x86_64"
    BINARY_SOURCE="$ROOT_DIR/.build/release/TaskMgmtMac"
    HELPER_BINARY_SOURCE="$ROOT_DIR/.build/release/TaskMgmtMacPrivilegedHelper"
fi

# Allow overriding arch via environment variables for building specific release targets
if [ -n "${RELEASE_ARCH:-}" ]; then
    if [ "$RELEASE_ARCH" = "arm64" ]; then
        DMG_NAME="TaskMgmtMac-Darwin_aarch64-Shipping"
        SWIFT_ARCH="arm64"
        # When compiling non-native architectures or multiple, SwiftPM puts them in apple/Products/Release
        BINARY_SOURCE="$ROOT_DIR/.build/apple/Products/Release/TaskMgmtMac"
        HELPER_BINARY_SOURCE="$ROOT_DIR/.build/apple/Products/Release/TaskMgmtMacPrivilegedHelper"
    elif [ "$RELEASE_ARCH" = "x86_64" ]; then
        DMG_NAME="TaskMgmtMac-Darwin_amd64-Shipping"
        SWIFT_ARCH="x86_64"
        BINARY_SOURCE="$ROOT_DIR/.build/apple/Products/Release/TaskMgmtMac"
        HELPER_BINARY_SOURCE="$ROOT_DIR/.build/apple/Products/Release/TaskMgmtMacPrivilegedHelper"
    fi
fi

# 1. Compile Release App with full compiler optimizations for target architecture
echo "==> Rebuilding release app in production mode ($SWIFT_ARCH)..."
if [ -n "${RELEASE_ARCH:-}" ]; then
    # Cross-compiling or explicit arch build
    swift build -c release --arch "$SWIFT_ARCH"
else
    # Standard native build
    swift build -c release
fi

# Prepare release bundle structure
RELEASE_APP_DIR="$ROOT_DIR/Task Manager.app"
rm -rf "$RELEASE_APP_DIR"
mkdir -p "$RELEASE_APP_DIR/Contents/MacOS"
mkdir -p "$RELEASE_APP_DIR/Contents/Resources"
mkdir -p "$RELEASE_APP_DIR/Contents/Library/LaunchDaemons"

echo "==> Copying binary and assets..."
cp "$BINARY_SOURCE" "$RELEASE_APP_DIR/Contents/MacOS/TaskMgmtMac"
cp "$HELPER_BINARY_SOURCE" "$RELEASE_APP_DIR/Contents/Resources/TaskMgmtMacPrivilegedHelper"
cp "$ROOT_DIR/Resources/LaunchDaemons/com.xmodern.TaskMgmtMac.PrivilegedHelper.plist" \
  "$RELEASE_APP_DIR/Contents/Library/LaunchDaemons/com.xmodern.TaskMgmtMac.PrivilegedHelper.plist"

if [ -f "$ROOT_DIR/Resources/AppIcon.icns" ]; then
  cp "$ROOT_DIR/Resources/AppIcon.icns" "$RELEASE_APP_DIR/Contents/Resources/AppIcon.icns"
fi

PLIST="$RELEASE_APP_DIR/Contents/Info.plist"
plutil -create xml1 "$PLIST"
/usr/libexec/PlistBuddy \
  -c "Add :CFBundleExecutable string TaskMgmtMac" \
  -c "Add :CFBundleIdentifier string com.xmodern.TaskMgmtMac" \
  -c "Add :CFBundleName string Task Manager" \
  -c "Add :CFBundleDisplayName string Task Manager" \
  -c "Add :CFBundlePackageType string APPL" \
  -c "Add :CFBundleVersion string 1" \
  -c "Add :CFBundleShortVersionString string 1.2" \
  -c "Add :LSMinimumSystemVersion string 14.0" \
  -c "Add :CFBundleIconFile string AppIcon" \
  "$PLIST"

# Ad-hoc sign release app
codesign_identity() {
  security find-identity -v -p codesigning 2>/dev/null \
    | awk -F '"' '/Apple Development|Developer ID Application/ { print $2; exit }'
}
SIGN_IDENTITY="$(codesign_identity)"
if [ -z "$SIGN_IDENTITY" ]; then
    echo "Warning: No Apple Developer identity found; using ad-hoc signing."
    SIGN_IDENTITY="-"
fi

echo "==> Code-signing the release bundle..."
codesign --force --options runtime \
  --identifier "com.xmodern.TaskMgmtMac.PrivilegedHelper" \
  --sign "$SIGN_IDENTITY" \
  "$RELEASE_APP_DIR/Contents/Resources/TaskMgmtMacPrivilegedHelper"
codesign --force --options runtime --sign "$SIGN_IDENTITY" "$RELEASE_APP_DIR"

# 2. Package into premium custom DMG
DMG_VOLNAME="TaskMgmtMac"
FINAL_DMG="$ROOT_DIR/${DMG_NAME}.dmg"
TEMP_DMG="/tmp/${DMG_NAME}-temp.dmg"
MOUNT_DIR="/Volumes/$DMG_VOLNAME"

# Ensure clean state and force unmount any leftover mount of the same name
hdiutil detach "$MOUNT_DIR" -force 2>/dev/null || true
rm -f "$FINAL_DMG" "$TEMP_DMG"

echo "==> Creating temporary writable disk image..."
hdiutil create -size 100m -fs HFS+ -volname "$DMG_VOLNAME" -o "$TEMP_DMG" -quiet

echo "==> Mounting image..."
hdiutil attach "$TEMP_DMG" -noautoopen -quiet

echo "==> Copying app and setting up Applications shortcut..."
cp -R "$RELEASE_APP_DIR" "$MOUNT_DIR/"
ln -s /Applications "$MOUNT_DIR/Applications"

echo "==> Setting custom volume icon..."
if [ -f "$ROOT_DIR/Resources/AppIcon.icns" ]; then
  cp "$ROOT_DIR/Resources/AppIcon.icns" "$MOUNT_DIR/.VolumeIcon.icns"
  SetFile -c icnC "$MOUNT_DIR/.VolumeIcon.icns"
  SetFile -a C "$MOUNT_DIR"
fi

echo "==> Configuring Finder style and visual layout..."
sleep 2

# Stylize the DMG Finder window layout via AppleScript
osascript <<APPLESCRIPT || echo "Warning: Could not configure Finder visual style, continuing with default layout."
tell application "Finder"
    tell disk "$DMG_VOLNAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        -- Size window: width=600, height=380
        set the bounds of container window to {400, 100, 1000, 480}
        set theViewOptions to the icon view options of container window
        set icon size of theViewOptions to 128
        set arrangement of theViewOptions to not arranged
        set position of item "Task Manager.app" of container window to {160, 160}
        set position of item "Applications" of container window to {440, 160}
        update items of container window
        close
    end tell
end tell
APPLESCRIPT

sleep 1

echo "==> Unmounting image..."
hdiutil detach "$MOUNT_DIR" -quiet

echo "==> Converting to final compressed, read-only DMG..."
hdiutil convert "$TEMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$FINAL_DMG" -quiet

echo "==> Cleaning up temporary files..."
rm -f "$TEMP_DMG"

echo "==> Done! DMG created successfully at: $FINAL_DMG"
