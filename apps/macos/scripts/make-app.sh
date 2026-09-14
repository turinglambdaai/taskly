#!/bin/bash
# Builds Taskly.app from the Swift package (release) and optionally a DMG.
# Usage: scripts/make-app.sh [output-dir]
set -euo pipefail

cd "$(dirname "$0")/.."
OUT_DIR="${1:-.build/app}"
APP="$OUT_DIR/Taskly.app"
CONTENT="$APP/Contents"
MACOS="$CONTENT/MacOS"
RES="$CONTENT/Resources"

echo "▶ swift build -c release"
swift build -c release

rm -rf "$APP"
mkdir -p "$MACOS" "$RES"

cp .build/release/Taskly "$MACOS/Taskly"
cp -R .build/release/Taskly_Taskly.bundle "$RES/TasklyResources.bundle" 2>/dev/null || true

# Icon: icon_512.png → .icns (via iconset)
ICONSET="$OUT_DIR/taskly.iconset"
mkdir -p "$ICONSET"
SRC_ICON="../../assets/icon_512.png"
for size in 16 32 64 128 256 512; do
  sips -z $size $size "$SRC_ICON" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z $double $double "$SRC_ICON" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$RES/Taskly.icns"
rm -rf "$ICONSET"

cat > "$CONTENT/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Taskly</string>
    <key>CFBundleIdentifier</key><string>app.taskly.Taskly</string>
    <key>CFBundleName</key><string>Taskly</string>
    <key>CFBundleDisplayName</key><string>Taskly</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleIconFile</key><string>Taskly</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>© 2026 Taskly Team</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

# Minimum deployment target: swift build may default to the host OS.
vtool -set-build-version macos 14.0 14.0 "$MACOS/Taskly" 2>/dev/null || true

codesign --force --deep --sign - "$APP" 2>/dev/null || true

echo "✔ Built $APP"
echo "  Launch: open $APP"
echo "  CLI:    $APP/Contents/MacOS/Taskly list --json"
