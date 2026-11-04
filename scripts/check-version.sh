#!/bin/bash
# Fails if any app's version differs from VERSION, or if a release tag doesn't match it:
#   scripts/check-version.sh [v0.7.0-rc.1]
set -euo pipefail
cd "$(dirname "$0")/.."
V="$(cat VERSION)"
fail=0
check() { [ "$2" = "$V" ] || { echo "✗ $1 dice $2, VERSION dice $V"; fail=1; }; }
check cli/Version.swift "$(sed -nE 's/^let cotsVersion = "([^"]+)"/\1/p' cli/Version.swift)"
check apps/windows/package-lock.json "$(sed -nE 's/^  "version": "([^"]+)".*/\1/p' apps/windows/package-lock.json | head -1)"
check apps/windows/package.json "$(sed -nE 's/.*"version": "([^"]+)".*/\1/p' apps/windows/package.json | head -1)"
check apps/windows/src-tauri/tauri.conf.json "$(sed -nE 's/.*"version": "([^"]+)".*/\1/p' apps/windows/src-tauri/tauri.conf.json | head -1)"
check apps/windows/src-tauri/Cargo.toml "$(sed -nE 's/^version = "([^"]+)"/\1/p' apps/windows/src-tauri/Cargo.toml | head -1)"
if [ $# -gt 0 ]; then
  TAG="${1#v}"
  [ "${TAG%%-*}" = "$V" ] || { echo "✗ El tag $1 no corresponde a VERSION $V"; fail=1; }
fi
[ $fail = 0 ] && echo "✓ $V"
exit $fail
