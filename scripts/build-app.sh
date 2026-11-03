#!/bin/bash
# Builds build/coTs.app (menu bar app + bundled `cots` CLI), ad-hoc signed.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="0.3.0"
swift build -c release
BIN="$(swift build -c release --show-bin-path)"
APP="build/coTs.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/CotsApp" "$APP/Contents/MacOS/coTs"
cp "$BIN/cots" "$APP/Contents/Resources/cots"
cp -R skill/cots "$APP/Contents/Resources/skill"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R Resources/en.lproj Resources/es.lproj "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.neomambi.cots</string>
    <key>CFBundleName</key><string>coTs</string>
    <key>CFBundleDisplayName</key><string>coTs</string>
    <key>CFBundleExecutable</key><string>coTs</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleDevelopmentRegion</key><string>es</string>
    <key>CFBundleLocalizations</key><array><string>es</string><string>en</string></array>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP/Contents/Resources/cots"
codesign --force --sign - "$APP"
echo "$APP"
