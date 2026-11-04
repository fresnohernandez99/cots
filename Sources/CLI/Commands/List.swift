import ArgumentParser
import CotsCore
import Foundation

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
