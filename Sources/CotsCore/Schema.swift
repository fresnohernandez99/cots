/// The format reference printed by `cots schema`. Kept in code so the CLI,
/// the app and the agent skill never drift apart.
public enum Schema {
    public static let reference = """
    coTs — formato de nota
    ==========================

    Una nota es un archivo Markdown dentro de una carpeta: <root>/<carpeta>/<fecha>-<slug>.md
    El frontmatter YAML tiene tres capas; todas las claves son opcionales salvo `title`.

    ---
    # 1. Identidad (visible en la app y en `cots list`)
    title: Refactor del módulo auth          # obligatorio
    summary: Migré sesiones a JWT; faltan tests   # 1 línea; las IAs la leen sin abrir el body
    created: 2026-11-02T14:30:00-05:00       # lo pone el CLI si falta
    updated: 2026-11-02T15:10:00-05:00       # lo pone el CLI/app al editar
    status: unread                           # unread | read | archived
    tags: [auth, backend]
    source: claude-code                      # quién la escribió: user, claude-code, cursor...

    # 2. Presentación y acciones (cómo la muestra la app)
    display:
      style: report        # document | report | checklist | log | code
      icon: hammer         # nombre de SF Symbol
      color: blue          # blue green orange red purple pink yellow gray o #RRGGBB
      pinned: false
    actions:               # botones en la cabecera de la nota
      - type: copy         # copia `text` (o el body si no hay text)
        label: Copiar prompt para continuar
        text: "Continúa el refactor de auth: ..."
      - type: open_url
        label: Ver PR
        url: https://github.com/org/repo/pull/42
      - type: open_file    # abre con la app por defecto
        path: ~/code/repo/Sources/Auth.swift
      - type: reveal       # muestra en Finder
        path: ~/code/repo
      - type: run          # la app SIEMPRE pide confirmación mostrando el comando
        label: Correr tests
        command: cd ~/code/repo && swift test

    # 3. Contexto para IAs (NUNCA se muestra en el cuerpo; solo `cots read --ai`)
    ai:
      agent: claude-code
      model: claude-opus-5-5
      session: <id de sesión>
      cwd: /Users/me/code/repo
      project: repo
      branch: feat/jwt
      files: [Sources/Auth.swift, Tests/AuthTests.swift]
      refs: [abc1234, https://github.com/org/repo/pull/42]
      next: [Añadir tests de expiración, Borrar SessionStore viejo]
      context: |
        Notas libres para la próxima IA: decisiones, trampas, por qué se hizo así.
    ---

    Cuerpo en Markdown. Lo que lee el humano.

    Estilos
    -------
    document   Markdown renderizado.
    report     Igual, con `summary` destacado arriba. Ideal para informes de sesión.
    checklist  Las líneas `- [ ] tarea` se vuelven casillas que se pueden marcar en la app.
    log        Entradas `## AAAA-MM-DD HH:MM` (las crea `cots append`); se muestran como timeline.
    code       Monoespaciado, sin renderizar.

    Carpetas
    --------
    Cada carpeta puede tener `_folder.yml`:
      title: Notas para código
      description: Informes de fin de sesión
      icon: hammer
      color: blue
      defaults:              # se mezcla en cada nota nueva (la nota gana)
        display: { style: report }
        tags: [code]
      ai:
        instructions: Qué debe incluir una IA al escribir aquí.
        template: |
          ## Resumen
          ## Cambios
          ## Pendientes
    Lee las instrucciones con `cots folder <nombre>` antes de escribir.

    Claves desconocidas se conservan siempre: puedes añadir las tuyas.
    """
}
