import ArgumentParser
import CotsCore
import Foundation

struct Append: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Añade una entrada con fecha a una nota (ideal para estilo log). Texto por stdin o --text.")
    @OptionGroup var store: StoreOptions
    @Argument(help: "id de la nota (carpeta/nombre o carpeta/latest)") var id: String
    @Option(parsing: .unconditional) var text: String?

    func run() throws {
        guard let content = text ?? readStdinIfPiped(), !content.isEmpty else { throw ValidationError("Falta el texto") }
        print(try store.store().append(id, text: content).id)
    }
}
