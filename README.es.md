<p align="center">
  <img src="assets/AppIcon-1024.png" width="128" alt="coTs">
</p>

<h1 align="center">coTs</h1>

<p align="center"><a href="README.md">English</a> · <b>Español</b></p>

<p align="center">
  <b>Notas de código para ti y tus IAs.</b><br>
  Una app de la barra de menú en macOS y de la bandeja del sistema en Windows donde Claude Code, Codex o Gemini guardan informes, logs y planes, y donde tú los lees, editas y apruebas.
</p>

<p align="center">
  <img src="docs/screenshots/popover.png" width="300" alt="Lista de notas en el popover">
  &nbsp;
  <img src="docs/screenshots/popover-plan.png" width="300" alt="Revisión de un plan">
  &nbsp;
  <img src="docs/screenshots/popover-dark.png" width="300" alt="Modo oscuro">
</p>

---

## Qué hace

- **"guarda en cots"** guarda la última respuesta de la IA tal cual, en ~0,3 s y **sin gastar tokens**: en Claude Code un hook la intercepta antes de que llegue al modelo.
- **"hagamos un plan en cots"**: la IA escribe un plan, tú lo revisas en la app (lo puedes editar) y pulsas **Aprobar**, **Pedir cambios** o **Rechazar**. La IA, que esperaba sin consumir tokens, continúa sola con tu decisión y tu versión del plan.
- **Nunca pierdes el hilo**: cada sesión de IA va guardando su último mensaje en una nota oculta del proyecto. Si la sesión se cierra o se apaga el Mac, al abrir una sesión nueva en ese proyecto coTs te avisa con una notificación, y la IA recibe un resumen de una línea de dónde se quedó.
- **"¿qué tengo pendiente en cots?"** responde con las tareas abiertas y los planes por revisar del proyecto donde abriste el agente, sin preguntarte cuál. Fuera de un proyecto, los muestra todos.
- **Topics y colores**: cada nota se etiqueta sola con el proyecto (repo git) donde trabajaba la IA, y cada topic tiene siempre el mismo color. También puedes elegir el color de cada nota.
- **Solo archivos Markdown**: tus notas son `.md` normales en `~/coTs`. Las puedes abrir con cualquier editor, versionar o sincronizar.
- **Siempre a mano**: vive en la barra de menú (macOS) o en la bandeja del sistema (Windows), arranca al iniciar sesión y muestra cuántas notas tienes sin leer y cuántos planes esperan tu revisión.
- **Español e inglés.**

## Apps

| | macOS | Windows |
|---|---|---|
| App | Barra de menú, SwiftUI (`apps/macos`) | Bandeja del sistema, Tauri (`apps/windows`) |
| Notas, CLI, skill, hooks, MCP | Compartidos | Compartidos |
| Descarga | `coTs-<versión>-macos-universal.dmg` | `coTs-<versión>-windows-x64-setup.exe` |

Las dos leen la misma carpeta de notas con el mismo CLI `cots`, así que una carpeta sincronizada entre un Mac y un PC funciona en ambos. Las descargas están en la [página de releases](https://github.com/fresnohernandez99/cots/releases): las release candidates son pre-releases llamadas «coTs x.y.z RC n».

<p align="center"><img src="docs/screenshots/windows.png" width="300" alt="coTs en Windows"></p>

## Instalar

### Windows

Ejecuta `coTs-<versión>-windows-x64-setup.exe`. Se instala para tu usuario (sin permisos de administrador), añade `cots` a tu PATH y, al abrirla por primera vez, instala la skill, los hooks de Claude Code y el MCP de Claude Desktop, igual que la app de Mac. Haz clic en el icono de la bandeja para ver tus notas; con clic derecho tienes **Nueva nota**, **Abrir carpeta de notas**, **Abrir al iniciar sesión** y **Ajustes**. Desinstalarla desde la configuración de Windows quita también todo eso, nunca tus notas. El instalador aún no está firmado: si SmartScreen avisa, elige **Más información → Ejecutar de todas formas**.

### macOS

1. Abre `coTs-<versión>-macos-universal.dmg` y arrastra **coTs** a **Aplicaciones**.
2. Ábrela. La primera vez se instala sola:
   - el arranque al iniciar sesión;
   - el CLI `cots` en `/usr/local/bin` (o `~/.local/bin`);
   - la skill para IAs en `~/.claude/skills/cots` (Claude Code) y `~/.agents/skills/cots` (Codex, Gemini CLI y Antigravity);
   - los hooks de Claude Code en `~/.claude/settings.json` (guardado directo y sesiones), sin tocar tus otros hooks;
   - el servidor MCP en Claude Desktop, si lo tienes instalado;
   - el permiso de notificaciones, que macOS te pedirá.
3. Abre una sesión nueva de tu agente para que cargue la skill.

<p align="center"><img src="docs/screenshots/settings.png" width="460" alt="Ajustes"></p>

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
| `guarda en cots ideas` | Igual, pero en la carpeta `ideas` (se crea si no existe). También vale en inglés: `save in cots ideas`. |
| `guarda un resumen con los pendientes en cots` | La IA escribe el contenido que pediste y lo guarda. |
| `hagamos un plan en cots para …` | La IA crea un plan en `plans` y espera tu decisión. |
| `revisa mis notas de cots de este proyecto` | La IA lista títulos y resúmenes (barato en contexto) y solo abre lo que necesita. |

### El ciclo de un plan

<p align="center">
  <img src="docs/screenshots/popover-plan.png" width="300" alt="Plan pendiente con Aprobar, Pedir cambios y Rechazar">
  &nbsp;
  <img src="docs/screenshots/popover-plans-expanded.png" width="300" alt="Planes terminados en gris">
</p>

```
IA: cots plan …  ──►  aparece en coTs › Plans (badge naranja)
IA: cots wait <id> (en segundo plano, 0 tokens)
Tú: lees, editas, comentas → Aprobar / Pedir cambios / Rechazar
IA: se despierta con  review: approved|changes|rejected + comentario + plan final
```

Los planes aprobados o rechazados pasan a gris, dentro de la subsección **Planes terminados**.

### Retomar donde lo dejaste

<p align="center"><img src="docs/screenshots/popover-session.png" width="300" alt="Nota de una sesión interrumpida"></p>

1. Mientras trabajas, el hook `Stop` guarda la última respuesta de cada sesión en `~/coTs/_sessions/<proyecto>--<sesión>.md`. Es una nota oculta: no sale en las listas.
2. `SessionEnd` anota si la sesión se cerró normalmente. Si se cuelga o apagas el Mac, ese aviso no llega, y no pasa nada.
3. Al abrir una sesión nueva en el mismo proyecto, `SessionStart`:
   - avisa a coTs, que muestra una **notificación de macOS** y un aviso naranja en el popover;
   - le pasa a la IA unas líneas con el último mensaje y el id de la nota (~100 tokens).
4. En la nota eliges qué hacer:
   - **Retomar** copia un prompt para continuar;
   - **Guardar como nota** la conserva en `code-notes`;
   - **Descartar** quita el aviso.

   Todas las sesiones siguen en **Vista ampliada → Sistema → Sesiones**.

### Claude Desktop y ChatGPT (MCP)

Las apps sin terminal ni hooks usan coTs a través de su servidor MCP, `cots mcp` (stdio). Ofrece estas herramientas:
- `list_folders`, `list_notes`, `search_notes`, `read_note`;
- `save_note`, `append_to_note`;
- `create_plan`, `get_plan_review`.

- **Claude Desktop:** coTs se registra sola en `claude_desktop_config.json` al abrirse por primera vez, o desde **Ajustes → Integración con IAs**. Reinicia Claude Desktop después.
- **ChatGPT de escritorio y otros clientes MCP:** **Ajustes → Integración con IAs → Copiar configuración** te da el comando (`…/coTs.app/Contents/Resources/cots`) y su argumento (`mcp`). Añádelos como servidor MCP local (en ChatGPT: Ajustes → Plugins).

Sin hooks, ahí "guarda en cots" sí gasta tokens, porque el modelo tiene que enviar el texto. En los planes, la IA crea el plan, tú lo revisas en coTs, le dices "listo" y lee tu decisión con `get_plan_review`.

## La app

<table>
  <tr>
    <td align="center"><img src="docs/screenshots/popover-report.png" width="260"><br><sub>Detalle de una nota: resumen, acciones y checklist</sub></td>
    <td align="center"><img src="docs/screenshots/sidebar.png" width="160"><br><sub>Barra lateral de la vista ampliada</sub></td>
    <td align="center"><img src="docs/screenshots/new-note.png" width="260"><br><sub>Nueva nota: carpeta, topic, estilo y color</sub></td>
  </tr>
</table>

- **Icono de la barra de menú:**
  - el clic izquierdo abre el popover: búsqueda, chips de carpetas y topics, lista y detalle de cada nota. El botón ⤢ abre la vista ampliada;
  - el **clic derecho** (o ⌃clic) abre el menú general: Nueva nota, Abrir expandida, Abrir carpeta de notas, Ver archivadas, Mostrar planes terminados, Abrir al iniciar sesión, Ajustes y Salir.
- **Vista ampliada:** barra lateral (Todas · Carpetas · Topics · Sistema), lista y detalle. Mientras está abierta, coTs aparece en el Dock y en la barra de menús:

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
topic: shop-api       # proyecto, detectado del repo
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
cots list [carpeta] [--here | --topic X] [--unread] [--json]
cots pending [--topic X | --all-projects]     # tareas abiertas y planes por revisar; por defecto, del proyecto actual
cots check <id> "parte de una tarea" [--all]  # marca tareas como hechas
cots setup [--status] [--remove]              # skill, hooks y MCP apuntando a este cots
cots read <id> [--ai] [--raw]                 # <carpeta>/latest = la más reciente
cots search "texto" [--here] · cots append <id> · cots trash <id> · cots set <id> --status … --pin
cots folders · cots folder <nombre> · cots mkdir <nombre> …
cots mcp                                      # servidor MCP por stdio
```

## Almacenamiento

Por defecto las notas están en `~/coTs`. En **Ajustes** puedes elegir otra carpeta, o **iCloud Drive** para verlas desde el iPhone con la app Archivos. La app y el CLI comparten la configuración en `~/.config/cots/config.json`, y la variable `COTS_HOME` la sobrescribe.

## Desarrollo

El núcleo y el CLI son Swift 6 y compilan en macOS, Windows y Linux. Dependencias: [Yams](https://github.com/jpsim/Yams) y [swift-argument-parser](https://github.com/apple/swift-argument-parser). La app de Windows necesita además Rust y Node.

```bash
swift build && swift test

# App de macOS (macOS 14+)
apps/macos/scripts/make-dmg.sh      # build/coTs.app firmada ad-hoc + build/coTs-<versión>-macos-universal.dmg
apps/macos/scripts/install.sh       # atajo: compila y copia a /Applications
swift apps/macos/scripts/make-icon.swift .   # regenera el icono (luego iconutil, ver el script)

# App de Windows (también arranca en macOS para desarrollar)
apps/windows/scripts/prepare-cli.sh # o prepare-cli.ps1 en Windows: compila cots junto a la app
cd apps/windows && npm install && npm run dev

# QA visual sin pantalla: datos de ejemplo + capturas de las vistas reales
# (las del README salen de aquí, copiadas a docs/screenshots)
scripts/fixtures.sh /tmp/cots-fx/notes
COTS_HOME=/tmp/cots-fx/notes .build/debug/CotsApp --snapshot /tmp/cots-fx/shots -AppleLanguages "(es)" -AppleLocale es_ES
```

| Ruta | Contenido |
|---|---|
| `core/CotsCore` | Compartido por todas las apps. `Model` (tipos de nota, tareas pendientes), `Format` (frontmatter YAML), `Storage` (repositorio, caché de notas, `NoteDraft`) y `Agents` (sesiones, caché de respuestas, hooks de Claude Code, servidor MCP). |
| `core/CotsIntegrations` | Lo que se instala para las IAs (enlace del CLI, skill, hooks de Claude Code, MCP de Claude Desktop), cada uno con instalar, quitar y estado. |
| `core/Tests` | Tests de ambos. |
| `cli` | `cots`, un archivo por comando en `Commands/`. Lo lleva cada app. |
| `apps/macos` | App SwiftUI de la barra de menú: `Sources` (`Model`, `Popover`, `Window`, `Settings`, `Components`), `Resources` (icono, traducciones `es`/`en`) y `scripts` (build, DMG, instalar). |
| `apps/windows` | App Tauri de la bandeja: `src` (la ventana, HTML/JS) y `src-tauri` (Rust: bandeja, llamadas al CLI, Markdown, vigilancia de la carpeta, instalador). |
| `skills/cots/SKILL.md` | Skill en formato abierto Agent Skills; `scripts/package-skill.sh` arma el ZIP para Agensi. |
| `assets` | Fuente del icono, compartida por las dos apps. |
| `scripts` | Versión (`set-version.sh`, `check-version.sh`), paquete de la skill y datos de ejemplo. |
| `docs` | Capturas, [cómo publicar](docs/RELEASING.md), notas de la release y la ficha de Agensi. |

Para distribuir a otros Macs sin el aviso de "desarrollador no identificado" hay que firmar con Developer ID y notarizar.

## Pendiente

- App de iOS reutilizando `CotsCore`.
- Notificaciones del sistema en macOS cuando una IA deja una nota (Windows ya las tiene).
- Firma de código del instalador de Windows.
