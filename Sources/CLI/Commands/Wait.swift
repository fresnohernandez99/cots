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
        while true {
            let note = try s.note(id: id)
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
