import ArgumentParser
import CotsCore
import Foundation

struct Mkdir: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Crea o actualiza una carpeta y su _folder.yml.")
    @OptionGroup var store: StoreOptions
    @Argument var name: String
    @Option var title: String?
    @Option var description: String?
    @Option var icon: String?
    @Option var color: String?
    @Option(help: "Estilo por defecto de las notas nuevas.") var style: String?
    @Option(help: "Instrucciones para las IAs que escriban aquí.") var instructions: String?
    @Option(parsing: .unconditional, help: "Plantilla markdown del body.") var template: String?

    func run() throws {
        let s = try store.store()
        var config = s.folderConfig(name)
        config.title = title ?? config.title
        config.description = description ?? config.description
        config.icon = icon ?? config.icon
        config.color = color ?? config.color
        if let style {
            var defaults = config.defaults ?? NoteMeta()
            defaults.display = Display(style: style)
            config.defaults = defaults
        }
        if instructions != nil || template != nil {
            var ai = config.ai ?? FolderAI()
            ai.instructions = instructions ?? ai.instructions
            ai.template = template ?? ai.template
            config.ai = ai
        }
        print(try s.createFolder(name, config: config).name)
    }
}
