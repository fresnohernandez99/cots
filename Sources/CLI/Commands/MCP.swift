import ArgumentParser
import CotsCore
import Foundation

struct MCP: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcp",
        abstract: "Servidor MCP por stdio, para Claude Desktop, ChatGPT y otros clientes MCP.",
        discussion: "Configura el cliente con command = ruta de `cots` y args = [\"mcp\"]."
    )
    @OptionGroup var store: StoreOptions

    func run() throws {
        let root = try store.store()
        MCPServer(store: root, version: Cots.version).runStdio()
    }
}
