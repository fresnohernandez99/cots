import Foundation

/// The agent skill, copied where each agent looks for skills. SKILL.md is the open Agent
/// Skills format; `~/.agents/skills` is read by Codex and by Gemini CLI / Antigravity.
public struct SkillIntegration: Integration {
    public let env: IntegrationEnvironment
    public init(env: IntegrationEnvironment) { self.env = env }

    public var title: String { "Skill (Claude Code, Codex, Gemini)" }
    public var location: String? { "~/.claude/skills · ~/.agents/skills" }

    var destinations: [URL] {
        [".claude/skills/cots", ".agents/skills/cots"].map { env.home.appendingPathComponent($0, isDirectory: true) }
    }

    public var isInstalled: Bool {
        destinations.contains { FileManager.default.fileExists(atPath: $0.appendingPathComponent("SKILL.md").path) }
    }

    /// Installs into every location independently; one unwritable folder doesn't block the others.
    public func install() throws {
        guard let source = env.bundledSkill else { throw IntegrationError("El bundle no incluye la skill") }
        let fm = FileManager.default
        var failures: [String] = []
        for url in destinations {
            do {
                try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
                try fm.copyItem(at: source, to: url)
            } catch {
                failures.append("\(url.deletingLastPathComponent().path): \(error.localizedDescription)")
            }
        }
        if !failures.isEmpty { throw IntegrationError(failures.joined(separator: "\n")) }
    }

    public func remove() {
        for url in destinations { try? FileManager.default.removeItem(at: url) }
    }
}
