#!/bin/bash
# Builds build/coTs-<version>.dmg: the app next to an Applications shortcut, to drag and drop.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-app.sh
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" build/coTs.app/Contents/Info.plist)
STAGE="build/dmg"
DMG="build/coTs-$VERSION.dmg"

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R build/coTs.app "$STAGE/"
ln -s /Applications "$STAGE/Aplicaciones"

hdiutil create -volname "coTs $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
rm -rf "$STAGE"
echo "$DMG"
