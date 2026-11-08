coTs: notas en Markdown para ti y tus IAs, ahora en **macOS y Windows**.

### Novedades
- **coTs para Windows.** Un icono en la bandeja del sistema abre las notas: carpetas, búsqueda, revisión de planes, tareas y avisos de notas nuevas. Comparte la carpeta de notas y el CLI `cots` con la app de Mac.
- **Pendientes del proyecto actual.** Pregunta a tu agente «¿qué tengo pendiente en cots?» y responde solo con las tareas y planes del proyecto en el que estás. Nuevos `cots pending` y `cots check`.
- **Mucho más rápida.** Con 1.500 notas, `cots list` y `cots search` pasan de 8,9 s a 0,12 s.
- **Un plan, no dos.** Cuando pides cambios, la IA corrige el mismo plan (`cots plan --replace <id>`) y vuelve a quedar por revisar, en vez de crear otro.
- **Solo se guardan los mensajes de sesión con detalle.** Los cierres breves («listo, 40 tests pasan») ya no aparecen como sesión pendiente; siguen disponibles para «guarda en cots».
- **Un solo mensaje de sesión por proyecto.** El último mensaje de la sesión anterior se sustituye por el de la nueva; si la nueva no deja ninguno, se borra al abrir la siguiente.
- **Borrar una nota abierta la cierra primero.** Antes, al borrar la nota de sesión abierta desde la notificación, la ventana se quedaba en «Sin notas» hasta reiniciar la app.
- **La lista se actualiza sola** al abrir el popover (macOS) o la ventana de la bandeja (Windows), con las notas y planes que llegaron mientras estaba cerrada.
- Contraste legible en «Pedir cambios», «Cambios pedidos», «Por revisar» y los nombres de proyecto.

### Revisión de calidad (RC 2)
- **No se pierden notas ni ediciones** cuando varios agentes escriben a la vez: antes, tres notas creadas en el mismo minuto podían quedar en una.
- **Seguridad:** un id de nota ya no puede salir de la carpeta de notas. Las acciones y los enlaces de una nota no abren programas ni scripts, solo páginas web y documentos.
- **Windows:** el instalador incluye el runtime de Swift (en la RC 1 faltaba), respeta el tipo del PATH del registro, usa la Papelera de reciclaje, está en español e inglés y conserva las integraciones al actualizar.
- **macOS:** un solo DMG universal para Intel y Apple Silicon.

### Instalar
- **macOS:** descarga el `-macos-universal.dmg`, arrastra **coTs** a Aplicaciones y ábrela. Firmada ad-hoc, no notarizada: si macOS la bloquea, clic derecho → **Abrir**.
- **Windows:** ejecuta el instalador `-setup.exe`. Se instala para tu usuario, sin permisos de administrador. Sin firma de código: si SmartScreen avisa, **Más información → Ejecutar de todas formas**.
- La primera vez, la app instala el CLI, la skill (Claude Code, Codex, Gemini), los hooks de Claude Code y el MCP de Claude Desktop.

La skill sola, para marketplaces de skills, está en `cots-skill-*.zip`. Las sumas SHA-256 están en `SHA256SUMS.txt`.
