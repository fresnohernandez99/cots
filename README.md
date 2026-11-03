<p align="center">
  <img src="Resources/AppIcon-1024.png" width="128" alt="coTs">
</p>

<h1 align="center">coTs</h1>

<p align="center">
  <b>Notas de código para ti y tus IAs.</b><br>
  Una app nativa de la barra de menú de macOS donde Claude Code, Codex o Gemini guardan informes, logs y planes, y donde tú los lees, editas y apruebas.
</p>

---

## Qué hace

- **"guarda en cots"** guarda la última respuesta de la IA tal cual, en ~0,3 s y **sin gastar tokens**: en Claude Code un hook la intercepta antes de que llegue al modelo.
- **"hagamos un plan en cots"**: la IA escribe un plan, tú lo revisas en la app (lo puedes editar) y pulsas **Aprobar**, **Pedir cambios** o **Rechazar**. La IA, que esperaba sin consumir tokens, continúa sola con tu decisión y tu versión del plan.
- **Topics y colores**: cada nota se etiqueta sola con el proyecto (repo git) donde trabajaba la IA, y cada topic tiene siempre el mismo color. También puedes elegir el color de cada nota.
- **Solo archivos Markdown**: tus notas son `.md` normales en `~/coTs`. Las puedes abrir con cualquier editor, versionar o sincronizar.
- **Siempre a mano**: vive en la barra de menú, arranca al iniciar sesión y muestra cuántas notas tienes sin leer y cuántos planes esperan tu revisión.
- **Español e inglés.**

## Instalar

1. Abre `coTs-<versión>.dmg` y arrastra **coTs** a **Aplicaciones**.
2. Ábrela. La primera vez se instala sola:
   - el arranque al iniciar sesión;
   - el CLI `cots` en `/usr/local/bin` (o `~/.local/bin`);
   - la skill para IAs en `~/.claude/skills/cots` (Claude Code) y `~/.agents/skills/cots` (Codex, Gemini CLI y Antigravity);
   - los hooks de guardado directo en `~/.claude/settings.json`, sin tocar tus otros hooks.
3. Abre una sesión nueva de tu agente para que cargue la skill.

En **Ajustes → Integración con IAs** ves el estado de cada pieza, puedes reinstalarla o quitarla, y aparecen los errores si algo no se pudo instalar.

**Desinstalar:** **Ajustes → Desinstalar coTs…** quita:
- la app (va a la Papelera);
- el CLI, la skill y los hooks;
- el arranque automático;
- las preferencias y las cachés.

Tus notas solo se borran si marcas la casilla, y también van a la Papelera.

## Hablarle a la IA

| Le dices | Qué pasa |
|---|---|
| `guarda en cots` | Guarda su última respuesta en `code-notes`. En Claude Code no pasa por el modelo. |
| `guarda en cots ideas` | Igual, pero en la carpeta `ideas` (se crea si no existe). |
| `guarda un resumen con los pendientes en cots` | La IA escribe el contenido que pediste y lo guarda. |
| `hagamos un plan en cots para …` | La IA crea un plan en `plans` y espera tu decisión. |
| `revisa mis notas de cots de este proyecto` | La IA lista títulos y resúmenes (barato en contexto) y solo abre lo que necesita. |

### El ciclo de un plan

```
IA: cots plan …  ──►  aparece en coTs › Plans (badge naranja)
IA: cots wait <id> (en segundo plano, 0 tokens)
Tú: lees, editas, comentas → Aprobar / Pedir cambios / Rechazar
IA: se despierta con  review: approved|changes|rejected + comentario + plan final
```

Los planes aprobados o rechazados pasan a gris, dentro de la subsección **Planes terminados**.

## La app

- **Icono de la barra de menú:**
  - el clic izquierdo abre el popover: búsqueda, chips de carpetas y topics, lista y detalle de cada nota. El botón ⤢ abre la vista ampliada;
  - el **clic derecho** (o ⌃clic) abre el menú general: Nueva nota, Abrir expandida, Abrir carpeta de notas, Ver archivadas, Mostrar planes terminados, Abrir al iniciar sesión, Ajustes y Salir.
- **Vista ampliada:** barra lateral (Todas · Carpetas · Topics), lista y detalle. Mientras está abierta, coTs aparece en el Dock y en la barra de menús:

| Menú | Atajos |
|---|---|
| Archivo | Nueva nota ⌘N |
| Nota | Leída o no leída ⌘⇧U · Fijar ⌘⇧P · Color · Copiar id ⌘⇧C · Mostrar en Finder ⌘⇧R · Archivar ⌘⇧A · Papelera ⌘⌫ |
| Ver | Todas ⌘0 · Carpetas ⌘1–⌘9 · Ver archivadas ⌘⇧H · Mostrar planes terminados |

- **En cada nota:** editar, fijar, color 🎨, contexto IA ✨ (oculto por defecto), botones de acción propios y el menú … con el resto. Todo también con clic derecho en la lista.
- **Estilos:**
  - `document`;
  - `report`, con el resumen destacado;
  - `checklist`, con casillas clicables;
  - `log`, una línea de tiempo;
  - `code`;
  - `plan`.

## Formato de una nota

Cada nota es `~/coTs/<carpeta>/<AAMMDD-HHMM>.md`. El frontmatter tiene tres capas, cada una para un lector distinto:

```yaml
---
# 1. Identidad: la ves en la app; la IA la lee con `cots list` sin abrir el body
title: Refactor del módulo auth
summary: Migré sesiones a JWT; faltan tests
status: unread            # unread | read | archived
topic: neomambi-api       # proyecto, detectado del repo
tags: [auth]
source: claude-code

# 2. Presentación y acciones: cómo se ve y qué botones tiene
display: { style: report, color: blue, pinned: false }
actions:
  - { type: open_url, label: Ver PR, url: https://… }
  - { type: copy, label: Prompt para continuar, text: "…" }
  - { type: run, label: Tests, command: swift test }   # siempre pide confirmación

# 3. Contexto para IAs: oculto en la app; solo `cots read --ai`
ai:
  cwd: /Users/me/code/repo
  branch: feat/jwt
  files: [Sources/Auth.swift]
  next: [Añadir tests de expiración]
  context: Decisiones y trampas para la próxima IA.

review: { status: pending, comment: "…" }   # solo en planes
---
## Resumen
El body es para ti.
```

Las claves desconocidas se conservan siempre. Cada carpeta puede tener un `_folder.yml` con título, icono, color, valores por defecto e instrucciones o plantilla para las IAs. `cots schema` imprime la referencia completa.

## CLI

```bash
cots add <carpeta> --title … [--summary …] [--style …] [--color …] [--ai JSON] [--action 'tipo|etiqueta|valor'] < body.md
cots add code-notes --from-last-reply        # usa la última respuesta capturada por el hook
cots plan --title … < plan.md                 # crea un plan pendiente
cots wait <id> [--timeout s]                  # bloquea hasta que decidas
cots review <id> approved|changes|rejected [--comment …]
cots list [carpeta] [--topic X] [--unread] [--json]
cots read <id> [--ai] [--raw]                 # <carpeta>/latest = la más reciente
cots search "texto" · cots append <id> · cots set <id> --status … --pin
cots folders · cots folder <nombre> · cots mkdir <nombre> …
```

## Almacenamiento

Por defecto las notas están en `~/coTs`. En **Ajustes** puedes elegir otra carpeta, o **iCloud Drive** para verlas desde el iPhone con la app Archivos. La app y el CLI comparten la configuración en `~/.config/cots/config.json`, y la variable `COTS_HOME` la sobrescribe.

## Desarrollo

Requiere macOS 14+ y Swift 6. Dependencias: [Yams](https://github.com/jpsim/Yams) y [swift-argument-parser](https://github.com/apple/swift-argument-parser).

```bash
swift build && swift test
scripts/make-dmg.sh                 # build/coTs.app firmada ad-hoc + build/coTs-<versión>.dmg
scripts/install.sh                  # atajo: compila y copia a /Applications
swift scripts/make-icon.swift .     # regenera el icono (luego iconutil, ver el script)

# QA visual sin pantalla: datos de ejemplo + capturas de las vistas reales
scripts/fixtures.sh /tmp/cots-fx/notes
COTS_HOME=/tmp/cots-fx/notes .build/debug/CotsApp --snapshot /tmp/cots-fx/shots
```

| Ruta | Contenido |
|---|---|
| `Sources/CotsCore` | Formato, parser YAML, almacenamiento, topics, caché de respuestas. Se reutilizará en la app de iOS. |
| `Sources/CLI` | `cots` y los puntos de entrada de los hooks (`cots hook claude-stop` / `claude-prompt`). |
| `Sources/App` | App SwiftUI: popover, ventana, ajustes, comandos de menú, integraciones y desinstalador. |
| `skill/cots/SKILL.md` | Skill en formato abierto Agent Skills. |
| `Resources` | Icono y traducciones (`es` es el idioma base, `en`). |

Para distribuir a otros Macs sin el aviso de "desarrollador no identificado" hay que firmar con Developer ID y notarizar.

## Pendiente

- App de iOS reutilizando `CotsCore`.
- Notificaciones del sistema cuando una IA deja una nota.
- Servidor MCP para agentes sin terminal (ChatGPT y Claude Desktop).
