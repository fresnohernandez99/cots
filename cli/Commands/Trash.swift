import ArgumentParser
import CotsCore
import Foundation

struct Trash: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Mueve una nota a la papelera.")
    @OptionGroup var store: StoreOptions
    @Argument(help: "id de la nota") var id: String

    func run() throws {
        let s = try store.store()
        let note = try s.note(id: id)
        try s.trash(note.id)
        print(note.id)
    }
}
