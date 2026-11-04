import ArgumentParser
import CotsCore
import CotsIntegrations
import Foundation

struct Setup: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Instala para los agentes la skill, los hooks de Claude Code y el MCP de Claude Desktop, apuntando a este `cots`.",
        discussion: "Lo usa la app de Windows al arrancar; en macOS lo hace la app desde Ajustes."
    )
    @Flag(help: "Quitarlo todo.") var remove = false
    @Flag(help: "Solo mostrar qué está instalado.") var status = false
    @Flag(help: "Instalar también lo que solo se instala la primera vez (Claude Desktop si está).") var firstLaunch = false
    @Flag var json = false

    func run() throws {
        let env = IntegrationEnvironment.cli(executable: URL(fileURLWithPath: CommandLine.arguments[0]))
        let integrations = Integrations.all(env)
        var errors: [String] = []
        if remove {
            integrations.forEach { $0.remove() }
        } else if !status {
            errors = Integrations.setUp(integrations, firstLaunch: firstLaunch)
        }
        if json {
            try printJSON([
                "integrations": integrations.map { ["title": $0.title, "installed": $0.isInstalled, "location": $0.location ?? ""] as [String: Any] },
                "errors": errors,
            ])
        } else {
            for i in integrations { print("\(i.isInstalled ? "✓" : "·") \(i.title)\(i.location.map { "  \($0)" } ?? "")") }
            errors.forEach { print("✗ \($0)") }
        }
        if !errors.isEmpty { throw ExitCode(1) }
    }
}
