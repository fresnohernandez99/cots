# Builds the Swift `cots` CLI for Windows and puts it, with the agent skill, where
# Tauri bundles them. Needs the Swift toolchain for Windows (swift.org) and Rust.
#   powershell -File apps\windows\scripts\prepare-cli.ps1 [-Config release]
param([string]$Config = "release")
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..\..\..")

swift build -c $Config --product cots
if ($LASTEXITCODE -ne 0) { throw "swift build falló" }
$bin = Join-Path (swift build -c $Config --show-bin-path) "cots.exe"
$triple = (rustc -vV | Select-String "^host: ").ToString().Substring(6).Trim()
$tauri = "apps\windows\src-tauri"

New-Item -ItemType Directory -Force "$tauri\binaries", "$tauri\resources" | Out-Null
Copy-Item $bin "$tauri\binaries\cots-$triple.exe" -Force
if (Test-Path "$tauri\resources\skill") { Remove-Item -Recurse -Force "$tauri\resources\skill" }
Copy-Item -Recurse "skills\cots" "$tauri\resources\skill"

# cots.exe links the Swift runtime dynamically (Windows has no static Foundation), so its
# DLLs ship next to it; the installer puts resources\runtime\* in the install folder.
$runtime = "$tauri\resources\runtime"
if (Test-Path $runtime) { Remove-Item -Recurse -Force $runtime }
New-Item -ItemType Directory -Force $runtime | Out-Null
$swiftBin = $env:Path.Split(";") | Where-Object { $_ -and (Test-Path (Join-Path $_ "swiftCore.dll")) } | Select-Object -First 1
if (-not $swiftBin) { throw "No encuentro el runtime de Swift (swiftCore.dll) en el PATH" }
Copy-Item "$swiftBin\*.dll" $runtime -Force
# The Visual C++ runtime, app-local, for PCs that don't have it installed.
foreach ($dll in "vcruntime140.dll", "vcruntime140_1.dll", "msvcp140.dll") {
  $src = Join-Path "$env:SystemRoot\System32" $dll
  if (Test-Path $src) { Copy-Item $src $runtime -Force }
}

# Prove it runs without Swift installed: only the runtime folder and Windows on the PATH.
$saved = $env:Path
$env:Path = "$((Resolve-Path $runtime).Path);$env:SystemRoot\System32;$env:SystemRoot"
Copy-Item "$tauri\binaries\cots-$triple.exe" "$runtime\cots-smoke.exe" -Force
& "$runtime\cots-smoke.exe" --version
$code = $LASTEXITCODE
Remove-Item "$runtime\cots-smoke.exe"
$env:Path = $saved
if ($code -ne 0) { throw "cots.exe no arranca solo con el runtime empaquetado (código $code)" }

Write-Output "$tauri\binaries\cots-$triple.exe"
