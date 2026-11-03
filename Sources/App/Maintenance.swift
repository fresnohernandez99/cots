import AppKit
import CotsCore
import Foundation
import ServiceManagement

/// The CLI, the agent skill and the agent hooks ship inside the bundle. Dragging the
/// app from the DMG doesn't run any installer, so the app sets them up itself.
enum Integrations {
    private static let fm = FileManager.default
    private static var home: URL { CotsConfig.home }
    private static let firstLaunchKey = "didInstallIntegrations"

    /// Failures from the last automatic setup, shown in Settings instead of being swallowed.
    @MainActor static var lastErrors: [String] = []

    static var bundledCLI: URL? { Bundle.main.url(forResource: "cots", withExtension: nil) }
    static var bundledSkill: URL? { Bundle.main.url(forResource: "skill", withExtension: nil) }

    // MARK: CLI

    /// Preferred first; `/usr/local/bin` is on every shell's PATH. `COTS_BIN_DIR` confines
    /// the link to one folder, so an isolated test install can't touch the real one.
    static var cliLinks: [URL] {
        if let dir = ProcessInfo.processInfo.environment["COTS_BIN_DIR"], !dir.isEmpty {
            return [URL(fileURLWithPath: dir).appendingPathComponent("cots")]
        }
        return [URL(fileURLWithPath: "/usr/local/bin/cots"), home.appendingPathComponent(".local/bin/cots")]
    }

    static var installedCLI: URL? { cliLinks.first(where: isOurLink) }

    /// Only links that point into a coTs.app are ours to replace or remove.
    static func isOurLink(_ url: URL) -> Bool {
        guard let dest = try? fm.destinationOfSymbolicLink(atPath: url.path) else { return false }
        return dest.hasSuffix("coTs.app/Contents/Resources/cots")
    }

    @discardableResult
    static func installCLI() throws -> URL {
        guard let source = bundledCLI else { throw MaintenanceError("El bundle no incluye el CLI") }
        for link in cliLinks {
            let dir = link.deletingLastPathComponent()
            if dir.path.hasPrefix(home.path) { try? fm.createDirectory(at: dir, withIntermediateDirectories: true) }
            guard fm.isWritableFile(atPath: dir.path) else { continue }
            if isOurLink(link) {
                try fm.removeItem(at: link)
            } else if (try? fm.attributesOfItem(atPath: link.path)) != nil {
                continue // Someone else's `cots`; don't clobber it.
            }
            try fm.createSymbolicLink(at: link, withDestinationURL: source)
            return link
        }
        throw MaintenanceError("No hay permiso de escritura en /usr/local/bin ni en ~/.local/bin")
    }

    static func removeCLI() {
        for link in cliLinks where isOurLink(link) { try? fm.removeItem(at: link) }
    }

    // MARK: Skill

    /// SKILL.md is the open Agent Skills format; agents only differ in where they look.
    /// `~/.agents/skills` is read by Codex and by Gemini CLI / Antigravity (as an alias).
    static var skillURLs: [URL] {
        [".claude/skills/cots", ".agents/skills/cots"].map { home.appendingPathComponent($0, isDirectory: true) }
    }

    static func skillInstalled(at url: URL) -> Bool {
        fm.fileExists(atPath: url.appendingPathComponent("SKILL.md").path)
    }

    static var skillInstalled: Bool { skillURLs.contains(where: skillInstalled(at:)) }

    /// Installs into every location independently; one unwritable folder doesn't block the others.
    static func installSkill() throws {
        guard let source = bundledSkill else { throw MaintenanceError("El bundle no incluye la skill") }
        var failures: [String] = []
        for url in skillURLs {
            do {
                try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
                try fm.copyItem(at: source, to: url)
            } catch {
                failures.append("\(url.deletingLastPathComponent().path): \(error.localizedDescription)")
            }
        }
        if !failures.isEmpty { throw MaintenanceError(failures.joined(separator: "\n")) }
    }

    static func removeSkill() {
        for url in skillURLs { try? fm.removeItem(at: url) }
    }

    // MARK: Claude Code hooks

    static var claudeSettingsURL: URL { home.appendingPathComponent(".claude/settings.json") }

    /// `Stop` caches each final reply (and mirrors it into the project's hidden session
    /// note); `UserPromptSubmit` turns "guarda en cots" into a save that never reaches the
    /// model; `SessionStart`/`SessionEnd` hand the previous session's last message back.
    private static let claudeHooks = [("UserPromptSubmit", "claude-prompt"), ("Stop", "claude-stop"),
                                      ("SessionStart", "claude-session-start"), ("SessionEnd", "claude-session-end")]

    private static func isOurHook(_ entry: [String: Any]) -> Bool {
        (entry["command"] as? String)?.contains("/cots\" hook claude-") == true
    }

    static var hooksInstalled: Bool { installedHookEvents.count == claudeHooks.count }

    /// Any of ours present: an older version installed fewer hooks and gets upgraded on launch.
    static var anyHookInstalled: Bool { !installedHookEvents.isEmpty }

    private static var installedHookEvents: [String] {
        guard let hooks = (try? readClaudeSettings())??["hooks"] as? [String: Any] else { return [] }
        return claudeHooks.map(\.0).filter { event in
            (hooks[event] as? [[String: Any]] ?? []).contains { group in
                (group["hooks"] as? [[String: Any]] ?? []).contains(where: isOurHook)
            }
        }
    }

    static func installHooks() throws {
        guard let cli = bundledCLI else { throw MaintenanceError("El bundle no incluye el CLI") }
        try editClaudeHooks { _, sub, groups in
            groups + [["hooks": [["type": "command", "command": "\"\(cli.path)\" hook \(sub)", "timeout": 10]]]]
        }
    }

    static func removeHooks() {
        try? editClaudeHooks { _, _, groups in groups }
    }

    /// Strips our entries from each event, lets `transform` add new ones, and writes
    /// back only if the file parsed: a malformed settings.json is never overwritten.
    private static func editClaudeHooks(_ transform: (String, String, [[String: Any]]) -> [[String: Any]]) throws {
        var settings = try readClaudeSettings() ?? [:]
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for (event, sub) in claudeHooks {
            let kept = (hooks[event] as? [[String: Any]] ?? []).compactMap { group -> [String: Any]? in
                var group = group
                let entries = (group["hooks"] as? [[String: Any]] ?? []).filter { !isOurHook($0) }
                if entries.isEmpty { return nil }
                group["hooks"] = entries
                return group
            }
            let updated = transform(event, sub, kept)
            hooks[event] = updated.isEmpty ? nil : updated
        }
        settings["hooks"] = hooks.isEmpty ? nil : hooks
        try fm.createDirectory(at: claudeSettingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: claudeSettingsURL, options: .atomic)
    }

    private static func readClaudeSettings() throws -> [String: Any]? {
        guard fm.fileExists(atPath: claudeSettingsURL.path) else { return nil }
        let data = try Data(contentsOf: claudeSettingsURL)
        if data.isEmpty { return [:] }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MaintenanceError("~/.claude/settings.json no es un objeto JSON; no lo toco")
        }
        return object
    }

    // MARK: MCP clients (Claude Desktop, ChatGPT)

    static var claudeDesktopConfigURL: URL {
        home.appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json")
    }

    /// Claude Desktop creates its support folder on first run; without it there's nothing to configure.
    static var claudeDesktopPresent: Bool {
        fm.fileExists(atPath: claudeDesktopConfigURL.deletingLastPathComponent().path)
    }

    static var mcpInstalledInClaudeDesktop: Bool {
        guard let data = try? Data(contentsOf: claudeDesktopConfigURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let servers = json["mcpServers"] as? [String: Any] else { return false }
        return servers["cots"] != nil
    }

    /// The `mcpServers.cots` entry every MCP client needs: run the bundled CLI with `mcp`.
    static var mcpServerEntry: [String: Any]? {
        bundledCLI.map { ["command": $0.path, "args": ["mcp"]] }
    }

    static func installMCPInClaudeDesktop() throws {
        guard let entry = mcpServerEntry else { throw MaintenanceError("El bundle no incluye el CLI") }
        try editClaudeDesktopConfig { $0["cots"] = entry }
    }

    static func removeMCPFromClaudeDesktop() {
        try? editClaudeDesktopConfig { $0["cots"] = nil }
    }

    /// Same rule as Claude Code's settings: only rewrite a file that parsed.
    private static func editClaudeDesktopConfig(_ edit: (inout [String: Any]) -> Void) throws {
        var config: [String: Any] = [:]
        if fm.fileExists(atPath: claudeDesktopConfigURL.path) {
            let data = try Data(contentsOf: claudeDesktopConfigURL)
            if !data.isEmpty {
                guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw MaintenanceError("claude_desktop_config.json no es un objeto JSON; no lo toco")
                }
                config = object
            }
        }
        var servers = config["mcpServers"] as? [String: Any] ?? [:]
        edit(&servers)
        config["mcpServers"] = servers.isEmpty ? nil : servers
        try fm.createDirectory(at: claudeDesktopConfigURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: claudeDesktopConfigURL, options: .atomic)
    }

    /// What to paste into ChatGPT (Settings → Plugins → add MCP server) or any other MCP client.
    static var mcpManualConfig: String {
        let path = bundledCLI?.path ?? "/Applications/coTs.app/Contents/Resources/cots"
        return """
        {
          "mcpServers": {
            "cots": { "command": "\(path)", "args": ["mcp"] }
          }
        }
        """
    }

    // MARK: Launch

    /// First launch installs everything; later launches keep what's installed in sync
    /// with this copy of the app (new skill text, CLI and hook paths if the app moved).
    @MainActor
    static func setUpOnLaunch() {
        guard Bundle.main.isInstalledCopy else { return }
        let first = !UserDefaults.standard.bool(forKey: firstLaunchKey)
        var errors: [String] = []
        func attempt(_ name: String, _ work: () throws -> Void) {
            do { try work() } catch { errors.append("\(name): \(error.localizedDescription)") }
        }
        if first || installedCLI != nil { attempt("CLI") { try installCLI() } }
        if first || skillInstalled { attempt("Skill") { try installSkill() } }
        if first || anyHookInstalled { attempt("Hooks") { try installHooks() } }
        if (first && claudeDesktopPresent) || mcpInstalledInClaudeDesktop {
            attempt("Claude Desktop") { try installMCPInClaudeDesktop() }
        }
        UserDefaults.standard.set(true, forKey: firstLaunchKey)
        lastErrors = errors
    }
}

/// Removes everything the app put on the system. Notes are only removed on request,
/// and go to the Trash rather than being deleted.
enum Uninstaller {
    private static let fm = FileManager.default

    static var bundleID: String { Bundle.main.bundleIdentifier ?? CotsConfig.bundleID }

    /// Files macOS or the app create outside the bundle, for the current and the legacy identifier.
    static var residues: [URL] {
        [bundleID, CotsConfig.legacyBundleID].flatMap(residues(for:))
            + [CotsConfig.home.appendingPathComponent(".config/cots")]
    }

    static func residues(for id: String) -> [URL] {
        let lib = CotsConfig.home.appendingPathComponent("Library")
        return [
            lib.appendingPathComponent("Preferences/\(id).plist"),
            lib.appendingPathComponent("Caches/\(id)"),
            lib.appendingPathComponent("HTTPStorages/\(id)"),
            lib.appendingPathComponent("HTTPStorages/\(id).binarycookies"),
            lib.appendingPathComponent("Saved Application State/\(id).savedState"),
            lib.appendingPathComponent("Application Support/\(id)"),
            lib.appendingPathComponent("WebKit/\(id)"),
        ]
    }

    /// Removes what versions before 0.4.1 left under the old identifier.
    static func cleanUpLegacy() {
        let legacy = CotsConfig.legacyBundleID
        guard UserDefaults.standard.persistentDomain(forName: legacy) != nil
                || residues(for: legacy).contains(where: { fm.fileExists(atPath: $0.path) }) else { return }
        UserDefaults.standard.removePersistentDomain(forName: legacy)
        for url in residues(for: legacy) { try? fm.removeItem(at: url) }
    }

    /// Never returns: the app quits, and a detached shell removes the residues the
    /// system may still rewrite while we're running (preferences, saved state).
    static func run(deleteNotes: Bool, notesRoot: URL) -> Never {
        try? SMAppService.mainApp.unregister()
        Integrations.removeCLI()
        Integrations.removeSkill()
        Integrations.removeHooks()
        Integrations.removeMCPFromClaudeDesktop()
        if deleteNotes { try? fm.trashItem(at: notesRoot, resultingItemURL: nil) }
        UserDefaults.standard.removePersistentDomain(forName: bundleID)
        UserDefaults.standard.synchronize()

        let paths = residues.map { "'" + $0.path.replacingOccurrences(of: "'", with: "'\\''") + "'" }.joined(separator: " ")
        let cleanup = Process()
        cleanup.executableURL = URL(fileURLWithPath: "/bin/sh")
        cleanup.arguments = ["-c", "while kill -0 \(getpid()) 2>/dev/null; do sleep 0.2; done; rm -rf \(paths); defaults delete \(bundleID) 2>/dev/null; true"]
        try? cleanup.run()
        cleanUpLegacy()

        if Bundle.main.isInstalledCopy {
            try? fm.trashItem(at: Bundle.main.bundleURL, resultingItemURL: nil)
        }
        exit(0)
    }
}

struct MaintenanceError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

extension Bundle {
    /// Running from /Applications or ~/Applications, as opposed to a dev build.
    var isInstalledCopy: Bool {
        let path = bundlePath
        let userApps = CotsConfig.home.appendingPathComponent("Applications").path
        return path.hasSuffix(".app") && (path.hasPrefix("/Applications/") || path.hasPrefix(userApps + "/"))
    }
}
