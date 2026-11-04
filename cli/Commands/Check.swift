import ArgumentParser
import CotsCore
import Foundation

struct Check: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Marca como hechas tareas `- [ ]` de una nota: por línea (--line, exacto) o por texto (cada texto marca las tareas que lo contienen, sin distinguir mayúsculas)."
    )
    @OptionGroup var store: StoreOptions
    @Argument(help: "id de la nota") var id: String
    @Argument(help: "Parte del texto de cada tarea a marcar. Si empieza por '-', ponlo después de --.") var tasks: [String] = []
    @Option(name: .customLong("line"), help: "Línea de la tarea en el body (1 = primera). Repetible.") var lines: [Int] = []
    @Flag(help: "Marcar todas las tareas abiertas.") var all = false

    func run() throws {
        let texts = tasks
        guard all || !texts.isEmpty || !lines.isEmpty else { throw ValidationError("Indica qué tareas marcar: texto, --line N o --all") }
        let matchers = texts.map(TextMatcher.init)
        let (_, checked) = try store.store().checkTasks(id) { line, task in
            all || lines.contains(line) || matchers.contains { $0.matches(task) }
        }
        guard !checked.isEmpty else { throw ValidationError("Ninguna tarea abierta coincide") }
        checked.forEach { print("[x] \($0)") }
    }
}
