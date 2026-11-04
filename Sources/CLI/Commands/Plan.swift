import ArgumentParser
import CotsCore
import Foundation

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
        var draft = NoteDraft.plan(title: title, body: text)
        draft.folder = folder
        draft.summary = summary
        draft.source = source
        draft.topic = topic ?? Topic.detect(cwd: FileManager.default.currentDirectoryPath)
        draft.ai = try ai.map { try structured($0, flag: "--ai") }
        print(try store.store().create(draft).id)
    }
}
