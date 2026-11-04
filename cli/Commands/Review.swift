import ArgumentParser
import CotsCore
import Foundation

struct Review: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Registra una decisión sobre un plan (lo mismo que los botones de la app).")
    @OptionGroup var store: StoreOptions
    @Argument var id: String
    @Argument(help: "approved | changes | rejected | pending") var status: String
    @Option(parsing: .unconditional) var comment: String?

    func run() throws {
        guard let value = ReviewStatus(rawValue: status) else { throw ValidationError("status: approved | changes | rejected | pending") }
        print(try store.store().setReview(id, value, comment: comment).id)
    }
}
