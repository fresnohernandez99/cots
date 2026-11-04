#!/bin/bash
# Builds build/coTs-<version>-macos-<arch>.dmg: the app next to an Applications shortcut, to drag and drop.
set -euo pipefail
cd "$(dirname "$0")/../../.."

apps/macos/scripts/build-app.sh
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" build/coTs.app/Contents/Info.plist)
# RELEASE names the file for a release candidate (0.6.0-rc.1); the app keeps VERSION.
RELEASE="${RELEASE:-$VERSION}"
STAGE="build/dmg"
DMG="build/coTs-$RELEASE-macos-$(uname -m).dmg"

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R build/coTs.app "$STAGE/"
ln -s /Applications "$STAGE/Aplicaciones"

hdiutil create -volname "coTs $RELEASE" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
rm -rf "$STAGE"
echo "$DMG"
