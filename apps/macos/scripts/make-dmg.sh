#!/bin/bash
# Builds build/coTs-<version>-macos-universal.dmg (or -<arch> with ARCHS=…): the app next to an Applications shortcut, to drag and drop.
set -euo pipefail
cd "$(dirname "$0")/../../.."

apps/macos/scripts/build-app.sh
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" build/coTs.app/Contents/Info.plist)
# RELEASE names the file for a release candidate (0.6.0-rc.1); the app keeps VERSION.
RELEASE="${RELEASE:-$VERSION}"
STAGE="build/dmg"
ARCH="$(lipo -archs build/coTs.app/Contents/MacOS/coTs | tr ' ' '\n' | wc -l | tr -d ' ')"
[ "$ARCH" -gt 1 ] && ARCH=universal || ARCH="$(lipo -archs build/coTs.app/Contents/MacOS/coTs)"
DMG="build/coTs-$RELEASE-macos-$ARCH.dmg"

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R build/coTs.app "$STAGE/"
ln -s /Applications "$STAGE/Aplicaciones"

hdiutil create -volname "coTs $RELEASE" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
rm -rf "$STAGE"
echo "$DMG"
