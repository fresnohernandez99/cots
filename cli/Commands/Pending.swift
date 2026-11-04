import ArgumentParser
import CotsCore
import Foundation

struct Pending: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Lo que queda por hacer en el proyecto actual: tareas `- [ ]` sin marcar y planes por revisar.",
        discussion: "Por defecto solo el proyecto del directorio actual; fuera de un proyecto, todos. --all-projects los muestra todos siempre."
    )
    @OptionGroup var store: StoreOptions
    @Option(help: "Proyecto concreto en lugar del actual.") var topic: String?
    @Flag(help: "Todos los proyectos aunque estés dentro de uno.") var allProjects = false
    @Flag var json = false

    func run() throws {
        let project = allProjects ? nil : topic ?? Topic.detect(cwd: FileManager.default.currentDirectoryPath)
        var notes = try store.store().notes(includeArchived: false)
        if let project { notes = notes.filter { $0.belongs(toTopic: project) } }
        let items = notes.compactMap { note -> (Note, [String])? in
            let tasks = note.openTasks
            return tasks.isEmpty && !note.awaitsReview ? nil : (note, tasks)
        }

        if json {
            try printJSON(items.map { note, tasks -> [String: Any] in
                var d = summaryJSON(note)
                d["tasks"] = tasks
                if note.awaitsReview { d["review"] = (note.meta.review?.resolvedStatus ?? .pending).rawValue }
                return d
            })
            return
        }
        print(project.map { "Pendientes de \($0)" } ?? "Pendientes de todos los proyectos")
        if items.isEmpty { print("Nada pendiente."); return }
        for (note, tasks) in items {
            var heading = "\n\(note.id)  \(project == nil ? note.meta.topic.map { "[\($0)] " } ?? "" : "")\(note.title)"
            if note.awaitsReview { heading += note.meta.review?.resolvedStatus == .changes ? " (cambios pedidos)" : " (plan por revisar)" }
            print(heading)
            tasks.forEach { print("  - [ ] \($0)") }
        }
    }
}
