import ArgumentParser
import CotsCore
import Foundation

struct Export: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Todo en un JSON: carpetas y notas con su frontmatter y body. Lo usa la app de Windows para pintar.",
        shouldDisplay: false
    )
    @OptionGroup var store: StoreOptions

    func run() throws {
        let s = try store.store()
        let (folders, notes) = try s.scan()
        let encoder = JSONEncoder()
        func object<T: Encodable>(_ value: T) throws -> Any { try JSONSerialization.jsonObject(with: encoder.encode(value)) }
        try printJSON([
            "root": s.root.path,
            "folders": try folders.map { f -> [String: Any] in
                ["name": f.name, "title": f.title, "notes": f.noteCount, "unread": f.unreadCount, "config": try object(f.config)]
            },
            "notes": try notes.map { n -> [String: Any] in
                var d: [String: Any] = ["id": n.id, "folder": n.folder, "path": n.url.path, "title": n.title,
                                        "date": n.date.timeIntervalSince1970, "body": n.body, "meta": try object(n.meta),
                                        "style": n.style.rawValue, "tasks": n.openTasks.count]
                if let error = n.parseError { d["error"] = error }
                return d
            },
        ])
    }
}
