import ArgumentParser
import CotsCore
import Foundation

struct Schema_: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "schema", abstract: "Imprime la referencia completa del formato de nota.")
    func run() { print(Schema.reference) }
}
