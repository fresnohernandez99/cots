# Publicar una versión

Todas las apps comparten una versión: la del archivo `VERSION`.

| Qué | Dónde |
|---|---|
| Versión de todas las apps | `VERSION`, `apps/windows/package.json`, `apps/windows/src-tauri/{Cargo.toml,tauri.conf.json}` (sincronizadas por `scripts/set-version.sh`) |
| Notas de la release | `docs/release-notes.md` |
| Paquete de la skill para Agensi | `scripts/package-skill.sh` → `build/cots-skill-<versión>.zip` |

## Release candidate

1. `scripts/set-version.sh 0.7.0` si cambia la versión, y actualiza `docs/release-notes.md`.
2. Commit, y luego el tag de la candidata: `git tag v0.7.0-rc.1 && git push origin master v0.7.0-rc.1`.
3. GitHub Actions (`.github/workflows/release.yml`) compila y deja un **borrador** de pre-release, «coTs 0.7.0 RC 1», con:
   - `coTs-0.7.0-rc.1-macos-<arch>.dmg`
   - `coTs-0.7.0-rc.1-windows-x64-setup.exe`
   - `cots-skill-0.7.0.zip`
   - `SHA256SUMS.txt`
4. Prueba los instaladores y publica el borrador. Si algo falla: arréglalo y saca `v0.7.0-rc.2`.

La versión final es el mismo proceso con el tag `v0.7.0`. Las apps llevan `0.7.0` en las candidatas y en la final; el sufijo `-rc.N` solo está en el tag y en los nombres de archivo, porque el instalador MSI de Windows no acepta sufijos.

## Localmente

- macOS: `RELEASE=0.7.0-rc.1 apps/macos/scripts/make-dmg.sh` → `build/coTs-0.7.0-rc.1-macos-<arch>.dmg`.
- Windows (en Windows): `apps\windows\scripts\prepare-cli.ps1`, luego en `apps\windows`: `npm ci; npx tauri build`.

## Skill en Agensi

1. `scripts/package-skill.sh` (o descarga el `.zip` de la release).
2. En agensi.io/dashboard/submit (o en Creator Studio → Skills → editar, para una actualización), sube el ZIP y rellena la ficha con `docs/agensi.md`.
