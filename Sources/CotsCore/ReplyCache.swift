import Foundation

/// The last reply of each agent session, captured by the agent's own end-of-turn
/// hook (Claude Code's `Stop` passes `last_assistant_message`). Saving "the last
/// reply" then costs zero model tokens: nothing has to be regenerated.
public struct CachedReply: Codable, Equatable, Sendable {
    public var agent: String
    public var session: String
    public var cwd: String?
    public var text: String
    public var at: String

    public init(agent: String, session: String, cwd: String?, text: String, at: String = Timestamp.now()) {
        self.agent = agent
        self.session = session
        self.cwd = cwd
        self.text = text
        self.at = at
    }
}

public enum ReplyCache {
    public static var directory: URL {
        CotsConfig.home.appendingPathComponent("Library/Caches/\(CotsConfig.bundleID)/replies", isDirectory: true)
    }

    public static func store(_ reply: CachedReply) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = reply.session.replacingOccurrences(of: "/", with: "_")
        let file = directory.appendingPathComponent("\(reply.agent)-\(name).json")
        try JSONEncoder().encode(reply).write(to: file, options: .atomic)
        let caches = directory.deletingLastPathComponent()
        Ownership.matchHome(caches, directory, file)
    }

    public static func reply(session: String, agent: String) -> CachedReply? {
        let url = directory.appendingPathComponent("\(agent)-\(session.replacingOccurrences(of: "/", with: "_")).json")
        return (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(CachedReply.self, from: $0) }
    }

    /// Most recent reply, preferring sessions running in `cwd` (the CLI doesn't
    /// know which session invoked it, but the working directory narrows it down).
    public static func latest(cwd: String? = nil) -> CachedReply? {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return nil
        }
        let replies = urls
            .compactMap { url -> (Date, CachedReply)? in
                guard let data = try? Data(contentsOf: url), let r = try? JSONDecoder().decode(CachedReply.self, from: data) else { return nil }
                let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return (date, r)
            }
            .sorted { $0.0 > $1.0 }
            .map(\.1)
        if let cwd, let match = replies.first(where: { $0.cwd == cwd }) { return match }
        return replies.first
    }

    /// Title from the first heading or line, without markdown, at most ~70 chars on a word boundary.
    public static func title(from text: String) -> String {
        let line = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? ""
        var clean = line.trimmingCharacters(in: CharacterSet(charactersIn: "#>-*` "))
        clean = clean.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
        guard clean.count > 70 else { return clean.isEmpty ? "Nota" : clean }
        let cut = clean.prefix(70)
        return (cut.lastIndex(of: " ").map { String(cut[..<$0]) } ?? String(cut)) + "…"
    }
}

/// Parses "guarda en cots [carpeta]" style prompts. Deliberately strict: anything
/// longer ("guarda un resumen con pendientes en cots") goes to the agent instead.
public struct SaveCommand: Equatable, Sendable {
    /// Folder named in the prompt, nil for the default one.
    public var folder: String?

    public static func parse(_ prompt: String) -> SaveCommand? {
        let normalized = prompt
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es"))
            .lowercased()
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".!¡")))
        let pattern = #"^(guarda|guardalo|guardala|guardar|save)( (esto|eso|this|it|el ultimo mensaje|la ultima respuesta|el ultimo informe|lo ultimo|last reply))? (en|in|to) cots( [a-z0-9_-]+)?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)) else {
            return nil
        }
        let range = match.range(at: 5)
        guard range.location != NSNotFound, let r = Range(range, in: normalized) else { return SaveCommand(folder: nil) }
        return SaveCommand(folder: normalized[r].trimmingCharacters(in: .whitespaces))
    }
}
