---
name: cots
description: Guarda notas y planes en coTs, la app de notas de la barra de menú del usuario, mediante el CLI `cots`. Úsala cuando el usuario diga "guarda en cots [carpeta]", "guarda esto/el informe en cots", "hagamos un plan en cots", "plan en cots", o pida leer, buscar o continuar notas o planes de coTs. También en inglés: "save in/to cots [folder]", "let's make a plan in cots".
---

# coTs

coTs guarda notas Markdown en carpetas (`code-notes` por defecto, `plans` para los planes). Siempre usa el CLI `cots` y nunca edites los archivos a mano. El topic (el proyecto) se detecta solo a partir del directorio actual.

## "guarda en cots [carpeta]"

En Claude Code, con los hooks de coTs instalados, esta frase exacta se guarda sola y nunca te llega. Si te llega, haz esto:

- **Claude Code:** `cots add <carpeta|code-notes> --from-last-reply --source claude-code`. Toma tu última respuesta ya capturada, así que no la reescribas. Añade `--title`/`--summary` solo si aportan.
- **Otros agentes (Codex, Gemini…):** pasa el texto por stdin:

```bash
cots add code-notes --title "Título corto" --summary "Una línea con el resultado" --source <agente> <<'EOF'
...markdown...
EOF
```

Si piden "un resumen", "con pendientes", etc., escribe tú ese contenido. Opciones útiles:
- `--style report|checklist|log|document|code`.
- `--color blue|purple|green|...`.
- `--ai '{"next":[...],"files":[...],"context":"..."}'` guarda contexto oculto para otra IA.
- `--action 'copy|Etiqueta|texto'` añade un botón (`open_url`, `open_file`, `reveal` y `run` también existen).

Responde solo con el id que imprime el comando.

## "hagamos un plan en cots": plan con aprobación del usuario

1. Escribe el plan: pasos concretos, archivos afectados y riesgos.

```bash
cots plan --title "Plan: <objetivo>" --summary "<una línea>" --source <agente> <<'EOF'
## Objetivo
## Pasos
- [ ] ...
## Riesgos
EOF
```

2. Dile al usuario que lo revise en coTs, y espera:
   - **Claude Code:** `cots wait <id>` con `run_in_background: true`. Te despertará al decidir. No consultes el estado en bucle.
   - **Otros agentes:** `cots wait <id> --timeout 1800` en primer plano.
3. La salida empieza con `review: approved|changes|rejected`, luego `comment:` si lo hay, y después el plan **tal como quedó**, porque el usuario puede haberlo editado: sigue esa versión.
   - **approved:** ejecuta el plan.
   - **changes:** revísalo según el comentario, actualízalo con `cots plan` (uno nuevo) y vuelve a esperar.
   - **rejected:** detente y pregunta.

## Sesiones anteriores

Si al empezar recibes un aviso de coTs sobre la sesión anterior del proyecto, menciónalo en una línea. Léelo con `cots read <id>` solo si el usuario quiere retomarla.

## Leer gastando poco contexto

- `cots list [carpeta] [--topic X] [--unread]` muestra id, fecha, topic, título y summary, sin el body.
- `cots read <id>` lee el body (`<carpeta>/latest` es la nota más reciente). `--ai` añade el contexto oculto.
- `cots search "texto"` busca en las notas.
- `cots append <id>` añade una entrada con fecha (stdin).
- `cots schema` muestra el formato completo.
