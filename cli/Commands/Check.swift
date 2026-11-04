import ArgumentParser
import CotsCore
import Foundation

struct Check: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Marca como hechas tareas `- [ ]` de una nota. Cada texto marca las tareas que lo contienen (sin distinguir mayúsculas)."
    )
    @OptionGroup var store: StoreOptions
    @Argument(help: "id de la nota") var id: String
    @Argument(help: "Parte del texto de cada tarea a marcar.") var tasks: [String] = []
    @Flag(help: "Marcar todas las tareas abiertas.") var all = false

    func run() throws {
        guard all || !tasks.isEmpty else { throw ValidationError("Indica qué tareas marcar, o --all") }
        let s = try store.store()
        let matchers = tasks.map(TextMatcher.init)
        let (body, checked) = try s.note(id: id).checkingTasks { task in all || matchers.contains { $0.matches(task) } }
        guard !checked.isEmpty else { throw ValidationError("Ninguna tarea abierta coincide") }
        try s.updateBody(id, body: body)
        checked.forEach { print("[x] \($0)") }
    }
}
