import ArgumentParser
import CotsCore
import Foundation
import Yams

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
    @Flag(help: "El body es solo texto: un '---' inicial no se toma como frontmatter (para texto escrito por una persona).") var rawBody = false
    @Flag var json = false

    func run() throws {
        let input: String
        if fromLastReply {
            guard let reply = ReplyCache.standard.latest(cwd: FileManager.default.currentDirectoryPath) else {
                throw ValidationError("No hay respuesta capturada; instala los hooks desde Ajustes de coTs o pasa el body por stdin")
            }
            input = reply.text
        } else {
            input = try file.map { try String(contentsOfFile: ($0 as NSString).expandingTildeInPath, encoding: .utf8) }
                ?? body ?? readStdinIfPiped() ?? ""
        }
        let (yaml, parsedBody) = rawBody ? (nil, input) : Frontmatter.split(input)
        var draft = NoteDraft(folder: folder, body: parsedBody)
        draft.base = try Frontmatter.parse(yaml)
        draft.title = title
        draft.summary = summary
        if !noTopic, draft.base["topic"] == nil { draft.topic = topic ?? Topic.detect(cwd: FileManager.default.currentDirectoryPath) }
        draft.source = source
        draft.status = status
        draft.style = style
        draft.icon = icon
        draft.color = color
        draft.pinned = pin
        draft.tags = tags.map { $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
        draft.ai = try ai.map { try structured($0, flag: "--ai") }
        if let actions {
            guard let list = try structured(actions, flag: "--actions").sequence else {
                throw ValidationError("--actions debe ser una lista")
            }
            draft.actions += list
        }
        for spec in quickActions { try draft.addAction(parseQuickAction(spec)) }

        let note = try store.store().create(draft)
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
