import ArgumentParser
import CotsCore
import Foundation

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
