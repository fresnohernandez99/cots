import ArgumentParser
import CotsCore
import Foundation
import Yams

@main
struct Cots: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cots",
        abstract: "Notas en Markdown que humanos e IAs comparten. La app de la barra de menú lee la misma carpeta.",
        subcommands: [Add.self, Plan.self, Wait.self, Review.self, Hook.self, Append.self, List.self, Read.self, Search.self, SetCmd.self,
                      Folders.self, FolderCmd.self, Mkdir.self, Schema_.self, Root.self]
    )
}

// MARK: - Shared

struct StoreOptions: ParsableArguments {
    @Option(name: .customLong("root"), help: "Carpeta raíz (por defecto la de la app).")
    var root: String?

    func store() throws -> NoteStore {
        let store = root.map { NoteStore(root: URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath)) } ?? NoteStore()
        try store.ensureRoot()
        return store
    }
}

/// Reads stdin only when it's a pipe or a redirected file. Agents often run commands
/// with an open-but-silent stdin, and blocking on it would hang them.
func readStdinIfPiped() -> String? {
    var info = stat()
    guard fstat(FileHandle.standardInput.fileDescriptor, &info) == 0 else { return nil }
    let type = info.st_mode & S_IFMT
    guard type == S_IFIFO || type == S_IFREG else { return nil }
    let data = FileHandle.standardInput.readDataToEndOfFile()
    let text = String(decoding: data, as: UTF8.self)
    return text.isEmpty ? nil : text
}

func printJSON(_ value: Any) throws {
    let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    print(String(decoding: data, as: UTF8.self))
}

func summaryJSON(_ note: Note) -> [String: Any] {
    var d: [String: Any] = ["id": note.id, "title": note.title, "folder": note.folder,
                            "status": note.meta.resolvedStatus.rawValue, "created": note.meta.created ?? ""]
    if let s = note.meta.summary { d["summary"] = s }
    if let t = note.meta.tags { d["tags"] = t }
    if let t = note.meta.topic { d["topic"] = t }
    if note.meta.isPinned { d["pinned"] = true }
    return d
}

func summaryLine(_ note: Note) -> String {
    let date = DateFormatter.logHeading.string(from: note.date)
    let flags = [note.meta.resolvedStatus == .unread ? "●" : " ", note.meta.isPinned ? "📌" : ""].joined()
    var line = "\(flags) \(note.id)  \(date)  \(note.meta.topic.map { "[\($0)] " } ?? "")\(note.title)"
    if let s = note.meta.summary, !s.isEmpty { line += " — \(s)" }
    return line
}

/// Parses a JSON or YAML string into a node, for `--ai` / `--actions` style flags.
func structured(_ text: String, flag: String) throws -> Node {
    guard let node = try? Yams.compose(yaml: text) else {
        throw ValidationError("\(flag) no es JSON/YAML válido")
    }
    return node
}

// MARK: - Commands

struct Add: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Crea una nota. El body va por stdin o --body. Si stdin empieza con '---', se toma como nota completa con frontmatter.",
        discussion: """
        Ejemplos:
          echo "## Resumen ..." | cots add notes_for_code --title "Refactor auth" --summary "Migré a JWT" --source claude-code
          cots add ideas --title "Idea" --body "texto" --style checklist
          cots add notes_for_code --ai '{"cwd":"/repo","next":["tests"]}' --action 'open_url|Ver PR|https://...' < informe.md
        """
    )

    @OptionGroup var store: StoreOptions
    @Argument(help: "Carpeta destino (se crea si no existe).") var folder: String
    @Option var title: String?
    @Option(parsing: .unconditional) var summary: String?
    @Option(help: "Separadas por comas.") var tags: String?
    @Option(help: "Proyecto. Por defecto se detecta del repo git / carpeta actual.") var topic: String?
    @Flag(help: "No asignar topic automáticamente.") var noTopic = false
    @Option(help: "user, claude-code, cursor...") var source: String?
    @Option(help: "unread | read | archived") var status: String?
    @Option(help: "document | report | checklist | log | code") var style: String?
    @Option(help: "SF Symbol") var icon: String?
    @Option var color: String?
    @Flag var pin = false
    @Option(parsing: .unconditional, help: "Objeto JSON/YAML con el contexto para IAs (bloque `ai`).") var ai: String?
    @Option(parsing: .unconditional, help: "Lista JSON/YAML de acciones.") var actions: String?
    @Option(name: .customLong("action"), help: "Acción rápida 'tipo|etiqueta|valor' (repetible). valor = url, path, command o text según el tipo.")
    var quickActions: [String] = []
    @Option(parsing: .unconditional, help: "Body en línea (alternativa a stdin).") var body: String?
    @Option(name: .customLong("file"), help: "Leer la nota/body de un archivo.") var file: String?
    @Flag(help: "Usar como body tu última respuesta (capturada por el hook; no la reescribas).") var fromLastReply = false
    @Flag var json = false

    func run() throws {
        let input: String
        if fromLastReply {
            guard let reply = ReplyCache.latest(cwd: FileManager.default.currentDirectoryPath) else {
                throw ValidationError("No hay respuesta capturada; instala los hooks desde Ajustes de coTs o pasa el body por stdin")
            }
            input = reply.text
        } else {
            input = try file.map { try String(contentsOfFile: ($0 as NSString).expandingTildeInPath, encoding: .utf8) }
                ?? body ?? readStdinIfPiped() ?? ""
        }
        let (yaml, parsedBody) = Frontmatter.split(input)
        var node = try Frontmatter.parse(yaml)

        func set(_ value: String?, _ path: String...) {
            if let value { Frontmatter.set(Node(value), at: path, in: &node) }
        }
        set(title, "title")
        set(summary, "summary")
        if !noTopic, node["topic"] == nil { set(topic ?? Topic.detect(cwd: FileManager.default.currentDirectoryPath), "topic") }
        set(source, "source")
        set(status, "status")
        set(style, "display", "style")
        set(icon, "display", "icon")
        set(color, "display", "color")
        if pin { Frontmatter.set(Node("true"), at: ["display", "pinned"], in: &node) }
        if let tags {
            let list = tags.split(separator: ",").map { Node($0.trimmingCharacters(in: .whitespaces)) }
            Frontmatter.set(.sequence(Node.Sequence(list)), at: ["tags"], in: &node)
        }
        if let ai {
            var merged = try structured(ai, flag: "--ai")
            if let existing = node["ai"] { Frontmatter.merge(defaults: existing, into: &merged) }
            Frontmatter.set(merged, at: ["ai"], in: &node)
        }
        var actionNodes = node["actions"]?.sequence.map(Array.init) ?? []
        if let actions {
            guard let list = try structured(actions, flag: "--actions").sequence else {
                throw ValidationError("--actions debe ser una lista")
            }
            actionNodes += list
        }
        for spec in quickActions {
            actionNodes.append(try Frontmatter.node(from: parseQuickAction(spec)))
        }
        if !actionNodes.isEmpty { Frontmatter.set(.sequence(Node.Sequence(actionNodes)), at: ["actions"], in: &node) }

        let note = try store.store().create(folder: folder, frontmatter: node, body: parsedBody)
        if json { try printJSON(summaryJSON(note).merging(["path": note.url.path]) { $1 }) } else { print(note.id) }
    }

    func parseQuickAction(_ spec: String) throws -> NoteAction {
        let parts = spec.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, let type = ActionType(rawValue: parts[0]) else {
            throw ValidationError("--action '\(spec)': usa 'tipo|etiqueta|valor' con tipo en \(ActionType.allCases.map(\.rawValue).joined(separator: ", "))")
        }
        var action = NoteAction(type: type.rawValue, label: parts[1].isEmpty ? nil : parts[1])
        switch type {
        case .copy: action.text = parts[2]
        case .openURL: action.url = parts[2]
        case .openFile, .reveal: action.path = parts[2]
        case .run: action.command = parts[2]
        }
        return action
    }
}

struct Append: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Añade una entrada con fecha a una nota (ideal para estilo log). Texto por stdin o --text.")
    @OptionGroup var store: StoreOptions
    @Argument(help: "id de la nota (carpeta/nombre o carpeta/latest)") var id: String
    @Option(parsing: .unconditional) var text: String?

    func run() throws {
        guard let content = text ?? readStdinIfPiped(), !content.isEmpty else { throw ValidationError("Falta el texto") }
        print(try store.store().append(id, text: content).id)
    }
}

struct List: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Lista notas: id, fecha, título y summary. No incluye el body (barato en contexto).")
    @OptionGroup var store: StoreOptions
    @Argument var folder: String?
    @Option var limit = 20
    @Flag var unread = false
    @Flag(help: "Incluir archivadas.") var all = false
    @Flag var json = false

    func run() throws {
        var notes = try store.store().notes(in: folder, includeArchived: all)
        if unread { notes = notes.filter { $0.meta.resolvedStatus == .unread } }
        notes = Array(notes.prefix(limit))
        if json { try printJSON(notes.map(summaryJSON)) } else { notes.map(summaryLine).forEach { print($0) } }
    }
}

struct Read: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Muestra una nota. Por defecto sin el bloque `ai`; usa --ai para incluirlo.")
    @OptionGroup var store: StoreOptions
    @Argument(help: "id de la nota (carpeta/nombre o carpeta/latest)") var id: String
    @Flag(help: "Incluir el contexto para IAs.") var ai = false
    @Flag(help: "Archivo tal cual, con todo el frontmatter.") var raw = false
    @Flag var json = false

    func run() throws {
        let note = try store.store().note(id: id)
        if raw { print(try String(contentsOf: note.url, encoding: .utf8)); return }
        if json {
            var d = summaryJSON(note)
            d["body"] = note.body
            d["path"] = note.url.path
            if ai, let ctx = note.meta.ai,
               let obj = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(ctx)) { d["ai"] = obj }
            try printJSON(d)
            return
        }
        print("# \(note.title)")
        var info = [note.id, DateFormatter.logHeading.string(from: note.date), note.meta.resolvedStatus.rawValue]
        if let tags = note.meta.tags, !tags.isEmpty { info.append(tags.map { "#\($0)" }.joined(separator: " ")) }
        if let source = note.meta.source { info.append("por \(source)") }
        print(info.joined(separator: " · "))
        if let s = note.meta.summary { print("> \(s)") }
        print("")
        print(note.body.trimmingCharacters(in: .newlines))
        if ai, let ctx = note.meta.ai {
            print("\n---\nai:")
            print(try Frontmatter.yaml(ctx).split(separator: "\n").map { "  \($0)" }.joined(separator: "\n"))
        }
    }
}

struct Search: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Busca en título, summary, tags y body.")
    @OptionGroup var store: StoreOptions
    @Argument var query: String
    @Option var folder: String?
    @Option var limit = 20
    @Flag var json = false

    func run() throws {
        let notes = Array(try store.store().search(query, in: folder).prefix(limit))
        if json { try printJSON(notes.map(summaryJSON)) } else { notes.map(summaryLine).forEach { print($0) } }
    }
}

struct SetCmd: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "set", abstract: "Cambia estado o fijado de una nota.")
    @OptionGroup var store: StoreOptions
    @Argument var id: String
    @Option(help: "unread | read | archived") var status: String?
    @Flag(inversion: .prefixedNo, help: "Fijar arriba.") var pin: Bool?

    func run() throws {
        let s = try store.store()
        if let status {
            guard let value = NoteStatus(rawValue: status) else { throw ValidationError("status: unread | read | archived") }
            try s.setStatus(id, value)
        }
        if let pin { try s.setPinned(id, pin) }
        print(try s.note(id: id).id)
    }
}

struct Folders: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Lista carpetas con su descripción.")
    @OptionGroup var store: StoreOptions
    @Flag var json = false

    func run() throws {
        let folders = try store.store().folders()
        if json {
            try printJSON(folders.map { f -> [String: Any] in
                var d: [String: Any] = ["name": f.name, "notes": f.noteCount, "unread": f.unreadCount]
                if let t = f.config.title { d["title"] = t }
                if let desc = f.config.description { d["description"] = desc }
                return d
            })
        } else {
            for f in folders {
                print("\(f.name)  (\(f.noteCount) notas, \(f.unreadCount) sin leer)\(f.config.description.map { " — \($0)" } ?? "")")
            }
        }
    }
}

struct FolderCmd: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "folder", abstract: "Muestra la configuración de una carpeta, incluidas las instrucciones para IAs.")
    @OptionGroup var store: StoreOptions
    @Argument var name: String

    func run() throws {
        let s = try store.store()
        guard try s.folders().contains(where: { $0.name == name }) else {
            print("La carpeta '\(name)' no existe todavía; `cots add \(name) ...` la crea sin instrucciones.")
            return
        }
        let config = s.folderConfig(name)
        print("# \(config.title ?? name)")
        if let d = config.description { print(d) }
        if let i = config.ai?.instructions { print("\n## Instrucciones para IAs\n\(i)") }
        if let t = config.ai?.template { print("\n## Plantilla del body\n\(t)") }
        if let defaults = config.defaults { print("\n## Defaults\n\(try Frontmatter.yaml(defaults))") }
    }
}

struct Mkdir: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Crea o actualiza una carpeta y su _folder.yml.")
    @OptionGroup var store: StoreOptions
    @Argument var name: String
    @Option var title: String?
    @Option var description: String?
    @Option var icon: String?
    @Option var color: String?
    @Option(help: "Estilo por defecto de las notas nuevas.") var style: String?
    @Option(help: "Instrucciones para las IAs que escriban aquí.") var instructions: String?
    @Option(parsing: .unconditional, help: "Plantilla markdown del body.") var template: String?

    func run() throws {
        let s = try store.store()
        var config = s.folderConfig(name)
        config.title = title ?? config.title
        config.description = description ?? config.description
        config.icon = icon ?? config.icon
        config.color = color ?? config.color
        if let style {
            var defaults = config.defaults ?? NoteMeta()
            defaults.display = Display(style: style)
            config.defaults = defaults
        }
        if instructions != nil || template != nil {
            var ai = config.ai ?? FolderAI()
            ai.instructions = instructions ?? ai.instructions
            ai.template = template ?? ai.template
            config.ai = ai
        }
        print(try s.createFolder(name, config: config).name)
    }
}

struct Schema_: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "schema", abstract: "Imprime la referencia completa del formato de nota.")
    func run() { print(Schema.reference) }
}

struct Root: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Imprime la carpeta raíz de las notas.")
    @OptionGroup var store: StoreOptions
    func run() throws { print(try store.store().root.path) }
}

// MARK: - Plans

struct Plan: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Crea un plan para que el usuario lo apruebe, pida cambios o lo rechace en la app. Body por stdin.",
        discussion: "Después ejecuta `cots wait <id>` (en segundo plano si tu agente lo permite) y actúa según la decisión."
    )
    @OptionGroup var store: StoreOptions
    @Option var title: String
    @Option(parsing: .unconditional) var summary: String?
    @Option(help: "user, claude-code, codex, gemini...") var source: String?
    @Option(parsing: .unconditional, help: "Objeto JSON/YAML con el contexto para IAs.") var ai: String?
    @Option(help: "Carpeta (por defecto plans).") var folder = NoteStore.plansFolder
    @Option(help: "Proyecto. Por defecto se detecta del repo git / carpeta actual.") var topic: String?
    @Option(parsing: .unconditional) var body: String?

    func run() throws {
        let text = body ?? readStdinIfPiped() ?? ""
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ValidationError("El plan está vacío") }
        var node = Frontmatter.emptyMapping
        Frontmatter.set(Node(title), at: ["title"], in: &node)
        if let summary { Frontmatter.set(Node(summary), at: ["summary"], in: &node) }
        if let source { Frontmatter.set(Node(source), at: ["source"], in: &node) }
        if let topic = topic ?? Topic.detect(cwd: FileManager.default.currentDirectoryPath) {
            Frontmatter.set(Node(topic), at: ["topic"], in: &node)
        }
        Frontmatter.set(Node(ReviewStatus.pending.rawValue), at: ["review", "status"], in: &node)
        Frontmatter.set(Node(DisplayStyle.plan.rawValue), at: ["display", "style"], in: &node)
        if let ai { Frontmatter.set(try structured(ai, flag: "--ai"), at: ["ai"], in: &node) }
        print(try store.store().create(folder: folder, frontmatter: node, body: text).id)
    }
}

struct Wait: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Espera a que el usuario revise un plan en la app y muestra su decisión, comentario y el plan (posiblemente editado).",
        discussion: "Salida: primera línea `review: approved|changes|rejected`. Código de salida 2 si vence --timeout."
    )
    @OptionGroup var store: StoreOptions
    @Argument var id: String
    @Option(help: "Segundos máximos de espera (0 = sin límite).") var timeout = 0

    func run() throws {
        let s = try store.store()
        let start = Date()
        while true {
            let note = try s.note(id: id)
            let review = note.meta.review?.resolvedStatus ?? .pending
            if review != .pending {
                print("review: \(review.rawValue)")
                if let comment = note.meta.review?.comment, !comment.isEmpty { print("comment: \(comment)") }
                print("id: \(note.id)\n\n# \(note.title)\n")
                print(note.body.trimmingCharacters(in: .newlines))
                return
            }
            if timeout > 0, Date().timeIntervalSince(start) > Double(timeout) {
                print("review: pending (timeout)")
                throw ExitCode(2)
            }
            Thread.sleep(forTimeInterval: 1)
        }
    }
}

struct Review: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Registra una decisión sobre un plan (lo mismo que los botones de la app).")
    @OptionGroup var store: StoreOptions
    @Argument var id: String
    @Argument(help: "approved | changes | rejected | pending") var status: String
    @Option(parsing: .unconditional) var comment: String?

    func run() throws {
        guard let value = ReviewStatus(rawValue: status) else { throw ValidationError("status: approved | changes | rejected | pending") }
        print(try store.store().setReview(id, value, comment: comment).id)
    }
}

// MARK: - Agent hooks

struct Hook: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Puntos de entrada para hooks de agentes (los instala la app).",
        subcommands: [ClaudeStop.self, ClaudePrompt.self]
    )

    static func input() -> [String: Any] {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    /// Claude Code `Stop`: cache the final reply so saving it later costs nothing.
    struct ClaudeStop: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "claude-stop")
        func run() {
            let input = Hook.input()
            guard let session = input["session_id"] as? String,
                  let text = input["last_assistant_message"] as? String, !text.isEmpty else { return }
            do { try ReplyCache.store(CachedReply(agent: "claude-code", session: session, cwd: input["cwd"] as? String, text: text)) } catch { FileHandle.standardError.write(Data("cots: \(error)\n".utf8)) }
        }
    }

    /// Claude Code `UserPromptSubmit`: "guarda en cots [carpeta]" is handled here and
    /// never reaches the model. Anything else passes through untouched.
    struct ClaudePrompt: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "claude-prompt")
        func run() throws {
            let input = Hook.input()
            guard let prompt = input["prompt"] as? String, let command = SaveCommand.parse(prompt),
                  let session = input["session_id"] as? String,
                  let reply = ReplyCache.reply(session: session, agent: "claude-code") else { return }
            let cwd = input["cwd"] as? String
            let folder = command.folder ?? NoteStore.defaultFolder
            var node = Frontmatter.emptyMapping
            Frontmatter.set(Node(ReplyCache.title(from: reply.text)), at: ["title"], in: &node)
            Frontmatter.set(Node("claude-code"), at: ["source"], in: &node)
            if let topic = cwd.flatMap(Topic.detect) { Frontmatter.set(Node(topic), at: ["topic"], in: &node) }
            var ai = AIContext()
            ai.agent = "claude-code"
            ai.session = session
            ai.cwd = cwd
            ai.branch = cwd.flatMap(gitBranch)
            Frontmatter.set(try Frontmatter.node(from: ai), at: ["ai"], in: &node)

            let message: String
            do {
                let store = NoteStore()
                try store.ensureRoot()
                message = "✓ coTs → \(try store.create(folder: folder, frontmatter: node, body: reply.text).id)"
            } catch {
                message = "✗ coTs: \(error.localizedDescription)"
            }
            try printJSON(["decision": "block", "reason": message,
                           "hookSpecificOutput": ["hookEventName": "UserPromptSubmit", "suppressOriginalPrompt": true]])
        }

        func gitBranch(_ cwd: String) -> String? {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            p.arguments = ["-C", cwd, "rev-parse", "--abbrev-ref", "HEAD"]
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = FileHandle.nullDevice
            guard (try? p.run()) != nil else { return nil }
            p.waitUntilExit()
            let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return p.terminationStatus == 0 && !out.isEmpty ? out : nil
        }
    }
}
