#!/bin/bash
# Fills a notes root with realistic sample data, for visual QA and README screenshots:
#   scripts/fixtures.sh <dir>
set -euo pipefail
export COTS_HOME="$1"
C="${CLI:-$(cd "$(dirname "$0")/.." && pwd)/.build/debug/cots}"

"$C" add code-notes --topic neomambi-api --source claude-code --title "Refactor de autenticación con JWT" \
  --summary "Sesiones migradas a JWT con rotación de refresh tokens; faltan tests de expiración" --tags auth,backend \
  --action 'open_url|Ver PR #42|https://github.com' --action 'copy|Prompt para continuar|Continúa el refactor de auth' \
  --ai '{"branch":"feat/jwt","files":["Sources/Auth/JWT.swift","Sources/Auth/SessionStore.swift"],"next":["Tests de expiración","Borrar SessionStore"]}' \
  --body $'## Resumen\nMigré la **autenticación** de sesiones en servidor a JWT firmados con rotación de refresh tokens.\n\n## Cambios\n- `JWT.swift`: firma y verificación con claves rotables\n- `AuthMiddleware`: valida el token en cada request\n- Endpoints `/login` y `/refresh` actualizados\n\n## Pendientes\n- [ ] Tests de expiración y revocación\n- [x] Migrar clientes móviles\n- [ ] Borrar `SessionStore`\n\n```swift\nlet token = try JWT.sign(claims, key: keys.current)\n```' >/dev/null
"$C" add code-notes --topic landing-web --source codex --title "Bug: el menú móvil no cierra en Safari" \
  --summary "El overlay captura el tap; arreglado con pointer-events y un listener en touchend" --body $'## Causa\nEl overlay del menú quedaba encima del botón en Safari 18.\n\n## Arreglo\n`pointer-events: none` en el overlay cerrado.' >/dev/null
"$C" add code-notes --topic coTs --source user --title "Ideas para coTs" --style checklist --pin \
  --body $'- [x] Guardado directo sin tokens\n- [x] Aprobación de planes\n- [ ] App de iOS\n- [ ] Notificaciones al volver a un proyecto' >/dev/null
"$C" add code-notes --topic neomambi-api --source claude-code --title "Despliegues a producción" --style log --color green \
  --summary "Registro de versiones desplegadas" --body "Despliegues de la API." >/dev/null
"$C" append code-notes/latest --text "v1.4.0: JWT y rate limiting" >/dev/null
"$C" set code-notes/latest --status read >/dev/null

plan() { # topic status title summary
  local id
  id=$(printf '## Objetivo\n%s\n\n## Pasos\n- [ ] Crear la base nueva y replicar datos\n- [ ] Cambiar la conexión detrás de un flag\n- [ ] Validar en staging y migrar\n\n## Riesgos\n- Ventana de escritura durante el corte\n' "$4" \
    | "$C" plan --topic "$1" --title "$3" --summary "$4" --source claude-code)
  [ "$2" != pending ] && "$C" review "$id" "$2" --comment "Hazlo en dos fases" >/dev/null
  "$C" set "$id" --status read >/dev/null
}
plan neomambi-api rejected "Plan: reescribir la API en Rust" "Reescritura completa del servicio"
plan landing-web approved "Plan: caché de imágenes en el CDN" "Servir imágenes optimizadas desde el CDN"
plan landing-web changes "Plan: rediseñar el onboarding" "Tres pasos en lugar de cinco, con progreso visible"
plan neomambi-api pending "Plan: migrar la base de datos a Postgres 17" "Actualizar a Postgres 17 sin downtime usando replicación lógica"
"$C" list --all
