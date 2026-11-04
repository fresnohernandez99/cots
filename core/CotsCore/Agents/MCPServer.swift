import Foundation
import Yams

/// Model Context Protocol server (JSON-RPC 2.0) exposing coTs as tools, for agents
/// that have no terminal or hooks: Claude Desktop, ChatGPT desktop. Transport-agnostic:
/// `handle` takes one decoded message and returns the response, nil for notifications.
public final class MCPServer {
    public static let supportedVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]

    private let store: NoteStore
    private let version: String
    /// The client's name from `initialize` (e.g. "claude-ai"), recorded as the note source.
    private var clientName = "mcp"

    public init(store: NoteStore = NoteStore(), version: String = "1.0") {
        self.store = store
        self.version = version
    }

    public func handle(_ message: [String: Any]) -> [String: Any]? {
        let id = message["id"]
        guard let method = message["method"] as? String else {
            return id.map { error($0, -32600, "Invalid request") }
        }
        let params = message["params"] as? [String: Any] ?? [:]
        guard let id else { return nil } // notifications (initialized, cancelled…) need no reply

        switch method {
        case "initialize":
            if let info = params["clientInfo"] as? [String: Any], let name = info["name"] as? String { clientName = name }
            let requested = params["protocolVersion"] as? String ?? Self.supportedVersions[0]
            return result(id, [
                "protocolVersion": Self.supportedVersions.contains(requested) ? requested : Self.supportedVersions[0],
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "cots", "title": "coTs", "version": version],
                "instructions": Self.instructions,
            ])
        case "ping":
            return result(id, [:])
        case "tools/list":
            return result(id, ["tools": Self.tools])
        case "tools/call":
            let name = params["name"] as? String ?? ""
            let args = params["arguments"] as? [String: Any] ?? [:]
            do {
                return result(id, ["content": [["type": "text", "text": try call(name, args)]]])
            } catch {
                // Tool failures are results the model can read and react to, not protocol errors.
                return result(id, ["content": [["type": "text", "text": "Error: \(error.localizedDescription)"]], "isError": true])
            }
        default:
            return error(id, -32601, "Method not found: \(method)")
        }
    }

    /// Reads newline-delimited JSON-RPC from stdin and writes responses to stdout until EOF.
    public func runStdio() {
        try? store.ensureRoot()
        while let line = readLine(strippingNewline: true) {
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            let response: [String: Any]?
            if let data = line.data(using: .utf8), let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                response = handle(message)
            } else {
                response = error(NSNull(), -32700, "Parse error")
            }
            guard let response, let data = try? JSONSerialization.data(withJSONObject: response, options: [.withoutEscapingSlashes]) else { continue }
            FileHandle.standardOutput.write(data + Data("\n".utf8))
        }
    }

    // MARK: Tools

    private func call(_ name: String, _ a: [String: Any]) throws -> String {
        switch name {
        case "list_folders":
            return try store.folders().map { f in
                var line = "- \(f.name) (\(f.noteCount) notas)"
                if let d = f.config.description { line += ": \(d)" }
                if let i = f.config.ai?.instructions { line += "\n  Instrucciones: \(i)" }
                return line
            }.joined(separator: "\n")

        case "list_notes", "search_notes":
            var notes: [Note]
            if name == "search_notes" {
                notes = try store.search(try string(a, "query"), in: a["folder"] as? String)
            } else {
                notes = try store.notes(in: a["folder"] as? String, includeArchived: a["include_archived"] as? Bool ?? false)
                if a["unread_only"] as? Bool == true { notes = notes.filter { $0.meta.resolvedStatus == .unread } }
            }
            if let topic = a["topic"] as? String { notes = notes.filter { $0.meta.topic?.lowercased() == topic.lowercased() } }
            let lines = notes.prefix(a["limit"] as? Int ?? 20).map { n in
                let date = DateFormatter.logHeading.string(from: n.date)
                var line = "- \(n.id) · \(date)\(n.meta.topic.map { " · [\($0)]" } ?? "") · \(n.title)"
                if let review = n.reviewStatusForTools { line += " · plan: \(review)" }
                if let s = n.meta.summary { line += " — \(s)" }
                return line
            }
            return lines.isEmpty ? "Sin notas." : lines.joined(separator: "\n")

        case "list_pending":
            return try PendingReport(store: store, project: a["topic"] as? String).text

        case "read_note":
            let note = try store.note(id: try string(a, "id"))
            var out = "# \(note.title)\nid: \(note.id)\(note.meta.topic.map { " · topic: \($0)" } ?? "")\n"
            if let s = note.meta.summary { out += "> \(s)\n" }
            out += "\n" + note.body.trimmingCharacters(in: .newlines)
            if a["include_ai_context"] as? Bool == true, let ctx = note.meta.ai {
                out += "\n\n---\nai:\n" + (try Frontmatter.yaml(ctx))
            }
            return out

        case "save_note":
            var draft = NoteDraft(folder: a["folder"] as? String ?? NoteStore.defaultFolder, body: try string(a, "body"))
            draft.title = try string(a, "title")
            draft.summary = nonEmpty(a["summary"])
            draft.topic = nonEmpty(a["topic"])
            draft.style = nonEmpty(a["style"])
            draft.color = nonEmpty(a["color"])
            if let tags = a["tags"] as? [String], !tags.isEmpty { draft.tags = tags }
            draft.source = clientName
            return "Guardada en coTs: \(try store.create(draft).id)"

        case "append_to_note":
            return "Añadido a \(try store.append(try string(a, "id"), text: try string(a, "text")).id)"

        case "create_plan":
            var draft = NoteDraft.plan(title: try string(a, "title"), body: try string(a, "body"))
            draft.summary = a["summary"] as? String
            draft.topic = a["topic"] as? String
            draft.source = clientName
            let note = try store.create(draft)
            return """
            Plan creado: \(note.id).
            Pide al usuario que lo revise en coTs (Aprobar / Pedir cambios / Rechazar) y que te avise. \
            Después llama a get_plan_review con este id.
            """

        case "get_plan_review":
            let id = try string(a, "id")
            // Bounded so a client's request timeout never fires first.
            let deadline = Date().addingTimeInterval(min(max(a["wait_seconds"] as? Double ?? 0, 0), 50))
            while true {
                let note = try store.note(id: id)
                let status = note.meta.review?.resolvedStatus ?? .pending
                if status != .pending || Date() >= deadline {
                    var out = "review: \(status.rawValue)\n"
                    if let c = note.meta.review?.comment, !c.isEmpty { out += "comment: \(c)\n" }
                    if status == .pending { return out + "El usuario aún no ha decidido." }
                    return out + "\n# \(note.title)\n\n" + note.body.trimmingCharacters(in: .newlines)
                }
                Thread.sleep(forTimeInterval: 1)
            }

        default:
            throw CotsError.invalidArgument("herramienta desconocida: \(name)")
        }
    }

    private func string(_ args: [String: Any], _ key: String) throws -> String {
        guard let v = args[key] as? String, !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CotsError.invalidArgument("falta el argumento '\(key)'")
        }
        return v
    }

    private func nonEmpty(_ value: Any?) -> String? {
        (value as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    private func result(_ id: Any, _ result: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }

    private func error(_ id: Any, _ code: Int, _ message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
    }

    // MARK: Descriptions

    static let instructions = """
    coTs es la app de notas de la barra de menú del usuario. Úsala cuando pida guardar algo "en cots", \
    hacer un plan "en cots", o revisar sus notas. Guarda con save_note (carpeta por defecto code-notes; \
    title corto, summary de una línea, el body en Markdown). Para planes: create_plan, pide al usuario que \
    lo revise en coTs y, cuando avise, get_plan_review; sigue la versión del plan que devuelve, porque \
    puede haberlo editado. Para leer, empieza por list_notes (sin bodies) y abre solo lo necesario con read_note.
    """

    static var tools: [[String: Any]] { [
        tool("list_folders", "Lista las carpetas de coTs con su descripción e instrucciones para IAs.", [:]),
        tool("list_notes", "Lista notas (id, fecha, topic, título, summary), sin el contenido. Barato en contexto.", [
            "folder": prop("string", "Carpeta, p. ej. code-notes o plans. Todas si se omite."),
            "topic": prop("string", "Proyecto."),
            "unread_only": prop("boolean", "Solo no leídas."),
            "include_archived": prop("boolean", "Incluir archivadas."),
            "limit": prop("integer", "Máximo de notas (20 por defecto)."),
        ], readOnly: true),
        tool("list_pending", "Lo que queda por hacer: tareas `- [ ]` sin marcar y planes por revisar. Si sabes en qué proyecto trabaja el usuario, pásalo en topic y responde solo con ese.", [
            "topic": prop("string", "Proyecto. Todos si se omite."),
        ], readOnly: true),
        tool("search_notes", "Busca texto en título, summary, tags y contenido.", [
            "query": prop("string", "Texto a buscar."),
            "folder": prop("string", "Limitar a una carpeta."),
            "topic": prop("string", "Limitar a un proyecto."),
            "limit": prop("integer", "Máximo de resultados."),
        ], required: ["query"], readOnly: true),
        tool("read_note", "Lee una nota completa. `<carpeta>/latest` es la más reciente.", [
            "id": prop("string", "Id de la nota (carpeta/nombre)."),
            "include_ai_context": prop("boolean", "Incluir el contexto oculto para IAs."),
        ], required: ["id"], readOnly: true),
        tool("save_note", "Guarda una nota en coTs. Úsala cuando el usuario diga 'guarda en cots'.", [
            "title": prop("string", "Título corto."),
            "body": prop("string", "Contenido en Markdown."),
            "summary": prop("string", "Una línea con el resultado."),
            "folder": prop("string", "Carpeta (code-notes por defecto)."),
            "topic": prop("string", "Proyecto al que pertenece."),
            "tags": ["type": "array", "items": ["type": "string"], "description": "Etiquetas."],
            "style": ["type": "string", "enum": ["document", "report", "checklist", "log", "code"], "description": "Cómo se muestra."],
            "color": ["type": "string", "enum": ["blue", "purple", "pink", "red", "orange", "yellow", "green", "teal", "indigo", "mint", "brown", "gray"]],
        ], required: ["title", "body"]),
        tool("append_to_note", "Añade una entrada con fecha al final de una nota (ideal para logs).", [
            "id": prop("string", "Id de la nota."),
            "text": prop("string", "Texto Markdown."),
        ], required: ["id", "text"]),
        tool("create_plan", "Crea un plan para que el usuario lo apruebe, pida cambios o lo rechace en coTs.", [
            "title": prop("string", "Título, p. ej. 'Plan: migrar a Postgres 17'."),
            "body": prop("string", "Plan en Markdown: objetivo, pasos (- [ ]), riesgos."),
            "summary": prop("string", "Una línea."),
            "topic": prop("string", "Proyecto."),
        ], required: ["title", "body"]),
        tool("get_plan_review", "Devuelve la decisión del usuario sobre un plan (approved / changes / rejected / pending), su comentario y el plan tal como quedó.", [
            "id": prop("string", "Id del plan."),
            "wait_seconds": prop("number", "Esperar hasta N segundos (máx. 50) a que decida."),
        ], required: ["id"], readOnly: true),
    ] }

    private static func tool(_ name: String, _ description: String, _ properties: [String: Any],
                             required: [String] = [], readOnly: Bool = false) -> [String: Any] {
        var schema: [String: Any] = ["type": "object", "properties": properties]
        if !required.isEmpty { schema["required"] = required }
        return ["name": name, "description": description, "inputSchema": schema,
                "annotations": ["readOnlyHint": readOnly]]
    }

    private static func prop(_ type: String, _ description: String) -> [String: Any] {
        ["type": type, "description": description]
    }
}

private extension Note {
    var reviewStatusForTools: String? {
        meta.display?.resolvedStyle == .plan ? (meta.review?.resolvedStatus ?? .pending).rawValue : nil
    }
}
