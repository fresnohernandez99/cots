import ArgumentParser
import CotsCore
import Foundation

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
