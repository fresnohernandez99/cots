#!/bin/bash
# Sets the version of every app at once: scripts/set-version.sh 0.7.0
# Plain x.y.z only; release candidates are a tag (v0.7.0-rc.1), not a version, because
# the Windows installer (MSI) rejects pre-release suffixes.
set -euo pipefail
cd "$(dirname "$0")/.."
V="${1:?uso: scripts/set-version.sh x.y.z}"
[[ "$V" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "La versión debe ser x.y.z"; exit 1; }

echo "$V" > VERSION
sed -i.bak -E "s/^version = \"[^\"]+\"/version = \"$V\"/" apps/windows/src-tauri/Cargo.toml
sed -i.bak -E "s/\"version\": \"[^\"]+\"/\"version\": \"$V\"/" apps/windows/src-tauri/tauri.conf.json apps/windows/package.json
rm -f apps/windows/src-tauri/Cargo.toml.bak apps/windows/src-tauri/tauri.conf.json.bak apps/windows/package.json.bak
(cd apps/windows/src-tauri && cargo update -p cots-app --offline >/dev/null 2>&1 || true)
scripts/check-version.sh
