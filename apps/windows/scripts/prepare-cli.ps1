# Builds the Swift `cots` CLI for Windows and puts it, with the agent skill, where
# Tauri bundles them. Needs the Swift toolchain for Windows (swift.org) and Rust.
#   powershell -File apps\windows\scripts\prepare-cli.ps1 [-Config release]
param([string]$Config = "release")
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..\..\..")

# Static Swift runtime: cots.exe runs on machines without Swift installed.
swift build -c $Config --product cots --static-swift-stdlib
if ($LASTEXITCODE -ne 0) { throw "swift build falló" }
$bin = Join-Path (swift build -c $Config --show-bin-path) "cots.exe"
$triple = (rustc -vV | Select-String "^host: ").ToString().Substring(6).Trim()
$tauri = "apps\windows\src-tauri"

New-Item -ItemType Directory -Force "$tauri\binaries", "$tauri\resources" | Out-Null
Copy-Item $bin "$tauri\binaries\cots-$triple.exe" -Force
if (Test-Path "$tauri\resources\skill") { Remove-Item -Recurse -Force "$tauri\resources\skill" }
Copy-Item -Recurse "skills\cots" "$tauri\resources\skill"
Write-Output "$tauri\binaries\cots-$triple.exe"
