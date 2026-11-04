#!/bin/bash
# Builds build/cots-skill-<version>.zip: the agent skill as Agensi (and any SKILL.md
# marketplace) expects it, cots/SKILL.md, with the listing fields Agensi reads from the
# frontmatter. The skill in skills/cots stays minimal, as agents install it.
set -euo pipefail
cd "$(dirname "$0")/.."
V="$(cat VERSION)"
OUT="build/skill"
rm -rf "$OUT" && mkdir -p "$OUT/cots"

awk -v version="$V" '
  NR == 1 && $0 == "---" { print; infront = 1; next }
  infront && $0 == "---" {
    print "version: " version
    print "summary: \"Notas y planes en Markdown que compartes con tus agentes: guarda respuestas sin gastar tokens, aprueba planes antes de que toquen código y consulta los pendientes del proyecto actual.\""
    print "tags: [notes, planning, todo, claude-code, codex, gemini-cli, mcp, markdown, productivity]"
    print "keywords: [cots, notas, planes, pendientes, todo, save reply, plan approval]"
    print "use_cases:"
    print "  - Guardar la última respuesta del agente con \"guarda en cots\" sin gastar tokens"
    print "  - Que el agente escriba un plan y espere tu aprobación antes de tocar código"
    print "  - Preguntar qué queda pendiente en el proyecto en el que estás"
    print "docs_url: https://github.com/fresnohernandez99/cots#readme"
    print; infront = 0; next
  }
  { print }
' skills/cots/SKILL.md > "$OUT/cots/SKILL.md"

ZIP="build/cots-skill-$V.zip"
rm -f "$ZIP"
(cd "$OUT" && zip -qrX "../../$ZIP" cots)
echo "$ZIP"
