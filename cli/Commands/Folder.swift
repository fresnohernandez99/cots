import ArgumentParser
import CotsCore
import Foundation

struct FolderCmd: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "folder", abstract: "Muestra la configuración de una carpeta, incluidas las instrucciones para IAs.")
    @OptionGroup var store: StoreOptions
    @Argument var name: String

    func run() throws {
        let s = try store.store()
        guard try s.folders().contains(where: { $0.name == name }) else {
            print("La carpeta '\(name)' no existe todavía; `cots add \(name) ...` la crea sin instrucciones.")
            return
        }
        let config = s.folderConfig(name)
        print("# \(config.title ?? name)")
        if let d = config.description { print(d) }
        if let i = config.ai?.instructions { print("\n## Instrucciones para IAs\n\(i)") }
        if let t = config.ai?.template { print("\n## Plantilla del body\n\(t)") }
        if let defaults = config.defaults { print("\n## Defaults\n\(try Frontmatter.yaml(defaults))") }
    }
}
