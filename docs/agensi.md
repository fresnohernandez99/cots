# Ficha de la skill en Agensi

Para el formulario de agensi.io/dashboard/submit. El ZIP es `build/cots-skill-<versión>.zip` (`scripts/package-skill.sh`). Agensi lee `name`, `description`, `version`, `summary`, `tags`, `keywords`, `use_cases` y `docs_url` del frontmatter, así que esos campos ya vienen rellenos.

**Precio:** gratis. **Categorías** (hasta 3; la primera decide la página): Productivity, Workflow Automation, Technical Documentation.

**Name** (≤ 60): `coTs: notes & plan approval for your agents`

**Summary** (≤ 300):
> Markdown notes and plans you share with your coding agents. Save the agent's last reply without spending tokens, approve plans before they touch code, and ask what's pending in the project you're in. Works with Claude Code, Codex and Gemini CLI.

**Description** (Markdown):
> coTs is a notes app for people who work with AI agents: a menu bar app on macOS and a tray app on Windows, over a folder of plain Markdown files. This skill teaches your agent to use its `cots` CLI.
>
> - **"guarda en cots" / "save in cots"** saves the agent's last reply as a note, word for word. With the Claude Code hooks it never reaches the model, so it costs no tokens.
> - **"let's make a plan in cots"**: the agent writes the plan and waits while you approve it, ask for changes or reject it from the app. It then follows the plan as you left it, edits included.
> - **"what's pending in cots?"** lists the open tasks and plans waiting for review of the project the agent is running in (the git repo), without asking you which one.
> - Reading is cheap on context: listings never include note bodies.
>
> **Where it stops:** it needs the coTs app (free, open source) installed, which puts `cots` on the PATH. It doesn't sync notes between machines; put the notes folder in iCloud, Dropbox or git for that. The instructions are in Spanish and the triggers work in Spanish and English.

**See it in action:**
> **You:** what's pending in cots?
> **Agent:** runs `cots pending`
> ```
> Pendientes de shop-api
>
> plans/261103-1953-4  Plan: migrate the database to Postgres 17 (plan por revisar)
>   - [ ] Create the new database and replicate data
>   - [ ] Switch the connection behind a flag
>   - [ ] Validate in staging and migrate
>
> code-notes/261103-1953  JWT auth refactor
>   - [ ] Expiration and revocation tests
>   - [ ] Delete SessionStore
> ```
> **Agent:** In shop-api there's a plan waiting for your review (Postgres 17 migration, 3 steps) and two open tasks in the JWT refactor: expiration/revocation tests and deleting SessionStore.

**Compatibility note:** Requires the coTs app for macOS 14+ or Windows 10/11 (github.com/fresnohernandez99/cots/releases). Works with Claude Code, Codex CLI and Gemini CLI; hooks for zero-token saving are Claude Code only.

**Tags / use cases:** notes, planning, todo, plan approval, claude-code, codex, gemini-cli, mcp, markdown.

**Permissions to confirm:** runs the local `cots` command only. No network access, no environment variables, no files outside the notes folder.

**Docs link:** https://github.com/fresnohernandez99/cots#readme

**Logo:** `assets/AppIcon-1024.png`, reduced to 512 × 512.

**Screenshots:** `docs/screenshots/popover.png`, `popover-plan.png`, `popover-plans-expanded.png`, and the Windows app.

## FAQ
- **Does it send my notes anywhere?** No. They are Markdown files in a folder on your machine (`~/coTs` by default).
- **Do I need Claude Code?** No. Any agent that can run shell commands and load SKILL.md skills works. Zero-token saving needs the Claude Code hooks, which the app installs.
