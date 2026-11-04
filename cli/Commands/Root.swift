import ArgumentParser
import CotsCore
import Foundation

struct Root: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Imprime la carpeta raíz de las notas.")
    @OptionGroup var store: StoreOptions
    func run() throws { print(try store.store().root.path) }
}
