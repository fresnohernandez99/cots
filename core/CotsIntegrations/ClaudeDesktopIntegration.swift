import Foundation

/// The `cots` MCP server in Claude Desktop's config. Other MCP clients (ChatGPT…) have
/// no config file we can edit; `manualConfig` is what to paste into them.
public struct ClaudeDesktopIntegration: Integration {
    public let env: IntegrationEnvironment
    public init(env: IntegrationEnvironment) { self.env = env }

    public var title: String { "Claude Desktop (MCP)" }
    public var location: String? { "claude_desktop_config.json" }

    var configURL: URL { env.home.appendingPathComponent("\(Self.supportFolder)/Claude/claude_desktop_config.json") }

    #if os(macOS)
    static let supportFolder = "Library/Application Support"
    #elseif os(Windows)
    static let supportFolder = "AppData/Roaming" // %APPDATA%
    #else
    static let supportFolder = ".config"
    #endif

    /// Claude Desktop creates its support folder on first run; without it there's nothing to configure.
    public var installsOnFirstLaunch: Bool {
        FileManager.default.fileExists(atPath: configURL.deletingLastPathComponent().path)
    }

    public var isInstalled: Bool {
        ((try? readJSONObject(configURL, name: "claude_desktop_config.json"))??["mcpServers"] as? [String: Any])?["cots"] != nil
    }

    public func install() throws {
        guard let cli = env.bundledCLI else { throw IntegrationError("El bundle no incluye el CLI") }
        try edit { $0["cots"] = ["command": commandPath(cli), "args": ["mcp"]] }
    }

    public func remove() {
        try? edit { $0["cots"] = nil }
    }

    /// Same rule as Claude Code's settings: only rewrite a file that parsed.
    private func edit(_ change: (inout [String: Any]) -> Void) throws {
        var config = try readJSONObject(configURL, name: "claude_desktop_config.json") ?? [:]
        var servers = config["mcpServers"] as? [String: Any] ?? [:]
        change(&servers)
        config["mcpServers"] = servers.isEmpty ? nil : servers
        try writeJSONObject(config, to: configURL)
    }

    /// What to paste into ChatGPT (Settings → Plugins → add MCP server) or any other MCP client.
    public var manualConfig: String {
        let path = env.bundledCLI.map(commandPath) ?? "/Applications/coTs.app/Contents/Resources/cots"
        return """
        {
          "mcpServers": {
            "cots": { "command": "\(path)", "args": ["mcp"] }
          }
        }
        """
    }
}
