import Foundation

/// Claude Code hooks in `~/.claude/settings.json`. `Stop` caches each final reply (and
/// mirrors it into the project's hidden session note); `UserPromptSubmit` turns "guarda
/// en cots" into a save that never reaches the model; `SessionStart`/`SessionEnd` hand
/// the previous session's last message back.
public struct ClaudeCodeHooksIntegration: Integration {
    public let env: IntegrationEnvironment
    public init(env: IntegrationEnvironment) { self.env = env }

    public var title: String { "Guardado directo en Claude Code (hooks)" }
    public var location: String? { "~/.claude/settings.json" }

    static let hooks = [("UserPromptSubmit", "claude-prompt"), ("Stop", "claude-stop"),
                        ("SessionStart", "claude-session-start"), ("SessionEnd", "claude-session-end")]

    var settingsURL: URL { env.home.appendingPathComponent(".claude/settings.json") }

    public var isInstalled: Bool { installedEvents.count == Self.hooks.count }
    public var isPartlyInstalled: Bool { !installedEvents.isEmpty }

    private func isOurs(_ entry: [String: Any]) -> Bool {
        guard let command = entry["command"] as? String else { return false }
        return command.contains("/cots\" hook claude-") || command.contains("/cots.exe\" hook claude-")
    }

    var installedEvents: [String] {
        guard let hooks = (try? readJSONObject(settingsURL, name: "~/.claude/settings.json"))??["hooks"] as? [String: Any] else { return [] }
        return Self.hooks.map(\.0).filter { event in
            (hooks[event] as? [[String: Any]] ?? []).contains { group in
                (group["hooks"] as? [[String: Any]] ?? []).contains(where: isOurs)
            }
        }
    }

    public func install() throws {
        guard let cli = env.bundledCLI else { throw IntegrationError("El bundle no incluye el CLI") }
        try edit { sub, groups in
            groups + [["hooks": [["type": "command", "command": "\"\(commandPath(cli))\" hook \(sub)", "timeout": 10]]]]
        }
    }

    public func remove() {
        try? edit { _, groups in groups }
    }

    /// Strips our entries from each event, lets `transform` add new ones, and writes back
    /// only if the file parsed: a malformed settings.json is never overwritten. Other
    /// tools' hooks and settings are kept as they were.
    private func edit(_ transform: (String, [[String: Any]]) -> [[String: Any]]) throws {
        var settings = try readJSONObject(settingsURL, name: "~/.claude/settings.json") ?? [:]
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for (event, sub) in Self.hooks {
            let kept = (hooks[event] as? [[String: Any]] ?? []).compactMap { group -> [String: Any]? in
                var group = group
                let entries = (group["hooks"] as? [[String: Any]] ?? []).filter { !isOurs($0) }
                if entries.isEmpty { return nil }
                group["hooks"] = entries
                return group
            }
            let updated = transform(sub, kept)
            hooks[event] = updated.isEmpty ? nil : updated
        }
        settings["hooks"] = hooks.isEmpty ? nil : hooks
        try writeJSONObject(settings, to: settingsURL)
    }
}
