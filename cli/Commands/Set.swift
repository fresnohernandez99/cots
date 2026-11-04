import ArgumentParser
import CotsCore
import Foundation

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
