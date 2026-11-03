#!/bin/bash
# Dev shortcut: build and copy to /Applications. On first launch the app installs
# the CLI and the skill itself (same path as dragging it from the DMG).
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-app.sh
APPS="/Applications"; [ -w "$APPS" ] || APPS="$HOME/Applications"
mkdir -p "$APPS"
pkill -x coTs 2>/dev/null || true
rm -rf "$APPS/coTs.app"
cp -R build/coTs.app "$APPS/"
open "$APPS/coTs.app"
echo "$APPS/coTs.app"
