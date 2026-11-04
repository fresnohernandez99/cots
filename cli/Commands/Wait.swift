import ArgumentParser
import CotsCore
import Foundation

struct Wait: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Espera a que el usuario revise un plan en la app y muestra su decisión, comentario y el plan (posiblemente editado).",
        discussion: "Salida: primera línea `review: approved|changes|rejected`. Código de salida 2 si vence --timeout."
    )
    @OptionGroup var store: StoreOptions
    @Argument var id: String
    @Option(help: "Segundos máximos de espera (0 = sin límite).") var timeout = 0

    func run() throws {
        let s = try store.store()
        let start = Date()
        // Resolved once: `plans/latest` must not drift to a newer plan while waiting, and a
        // bare id would otherwise scan every note each second.
        let fixedID = try s.note(id: id).id
        var missingSince: Date?
        while true {
            let note: Note
            do {
                note = try s.note(id: fixedID)
                missingSince = nil
            } catch CotsError.noteNotFound(let missing) {
                // A sync client briefly moves files while it renames or downloads them.
                let since = missingSince ?? Date()
                missingSince = since
                guard Date().timeIntervalSince(since) < 30 else { throw CotsError.noteNotFound(missing) }
                Thread.sleep(forTimeInterval: 1)
                continue
            }
            let review = note.meta.review?.resolvedStatus ?? .pending
            if review != .pending {
                print("review: \(review.rawValue)")
                if let comment = note.meta.review?.comment, !comment.isEmpty { print("comment: \(comment)") }
                print("id: \(note.id)\n\n# \(note.title)\n")
                print(note.body.trimmingCharacters(in: .newlines))
                return
            }
            if timeout > 0, Date().timeIntervalSince(start) > Double(timeout) {
                print("review: pending (timeout)")
                throw ExitCode(2)
            }
            Thread.sleep(forTimeInterval: 1)
        }
    }
}
