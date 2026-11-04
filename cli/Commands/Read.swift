import ArgumentParser
import CotsCore
import Foundation

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
