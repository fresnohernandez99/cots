#!/bin/bash
# Fills a notes root with varied sample data for visual QA: scripts/fixtures.sh <dir>
set -euo pipefail
export COTS_HOME="$1"
C="${CLI:-$(cd "$(dirname "$0")/.." && pwd)/.build/debug/cots}"
"$C" add code-notes --topic neomambi-api --source claude-code --title "Refactor del módulo de autenticación con JWT y rotación de refresh tokens" \
  --summary "Migré sesiones a JWT; faltan tests de expiración y limpiar SessionStore" --tags auth,backend \
  --action 'open_url|Ver PR|https://github.com' --action 'copy|Prompt para continuar|Continúa' --body $'## Resumen\nMigré **auth** a JWT.\n\n## Pendientes\n- [ ] tests de expiración\n- [x] borrar código viejo\n\n```swift\nlet token = try JWT.sign(claims)\n```' >/dev/null
"$C" add code-notes --topic landing-web --source codex --title "Bug del menú en Safari" --summary "El menú móvil no cierra en Safari 18" --body "Detalle del bug." >/dev/null
"$C" add code-notes --topic Bitacora --source user --title "Ideas sueltas" --style checklist --pin --body $'- [ ] Icono de menú propio\n- [x] Renombrar a coTs\n- [ ] App iOS' >/dev/null
"$C" add code-notes --topic neomambi-api --title "Log de despliegues" --style log --color green --body "Despliegues a producción." >/dev/null
"$C" append code-notes/latest --text "v1.2 desplegada" >/dev/null
"$C" add code-notes --no-topic --title "Nota sin topic" --body "Texto." >/dev/null
for s in pending approved rejected changes pending; do
  id=$(printf '## Objetivo\nHacer algo.\n\n## Pasos\n- [ ] Paso uno\n- [ ] Paso dos\n\n## Riesgos\n- Ninguno\n' | (cd /tmp && "$C" plan --title "Plan $s: migrar base de datos a Postgres 17" --summary "Plan de prueba en estado $s" --source claude-code))
  [ "$s" != pending ] && "$C" review "$id" "$s" --comment "comentario $s" >/dev/null
  "$C" set "$id" --status read >/dev/null || true
done
"$C" list --all
