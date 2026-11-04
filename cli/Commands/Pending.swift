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
        let report = try PendingReport(store: store.store(), project: project)
        guard json else { print(report.text); return }
        try printJSON(report.items.map { note, tasks -> [String: Any] in
            var d = summaryJSON(note)
            d["tasks"] = tasks
            if note.awaitsReview { d["review"] = (note.meta.review?.resolvedStatus ?? .pending).rawValue }
            return d
        })
    }
}
