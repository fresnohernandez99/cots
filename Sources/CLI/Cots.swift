import ArgumentParser
import CotsCore
import Foundation
import Yams

@main
struct Cots: ParsableCommand {
    /// From the enclosing coTs.app's Info.plist (the CLI lives in Contents/Resources).
    static let version: String = {
        let exe = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let plist = exe.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Info.plist")
        return (NSDictionary(contentsOf: plist)?["CFBundleShortVersionString"] as? String) ?? "dev"
    }()

    static let configuration = CommandConfiguration(
        commandName: "cots",
        abstract: "Notas en Markdown que humanos e IAs comparten. La app de la barra de menú lee la misma carpeta.",
        subcommands: [Add.self, Plan.self, Wait.self, Review.self, Hook.self, MCP.self, Append.self, List.self, Read.self, Search.self, SetCmd.self,
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
