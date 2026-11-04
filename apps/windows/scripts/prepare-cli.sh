#!/bin/bash
# Builds the Swift `cots` CLI for this machine and puts it, with the agent skill, where
# Tauri bundles them (src-tauri/binaries, src-tauri/resources). Run before `npm run dev`
# or `npm run build` on macOS or Linux; on Windows use prepare-cli.ps1.
set -euo pipefail
cd "$(dirname "$0")/../../.."

CONFIG="${1:-debug}"
swift build -c "$CONFIG" --product cots
BIN="$(swift build -c "$CONFIG" --show-bin-path)/cots"
TRIPLE="$(rustc -vV | sed -n 's/^host: //p')"
TAURI=apps/windows/src-tauri

# resources/runtime holds the Swift DLLs on Windows; elsewhere it's empty but must exist.
mkdir -p "$TAURI/binaries" "$TAURI/resources/runtime"
cp "$BIN" "$TAURI/binaries/cots-$TRIPLE"
rm -rf "$TAURI/resources/skill"
cp -R skills/cots "$TAURI/resources/skill"
echo "$TAURI/binaries/cots-$TRIPLE"
