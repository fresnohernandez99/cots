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

public struct ReplyCache: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// Next to the app's other caches, under the user's home.
    public static var standard: ReplyCache {
        ReplyCache(directory: CotsConfig.cacheDirectory.appendingPathComponent("replies", isDirectory: true))
    }

    public func store(_ reply: CachedReply) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(reply).write(to: file(session: reply.session, agent: reply.agent), options: .atomic)
        Ownership.matchHome(directory.deletingLastPathComponent(), directory, file(session: reply.session, agent: reply.agent))
    }

    public func reply(session: String, agent: String) -> CachedReply? {
        (try? Data(contentsOf: file(session: session, agent: agent))).flatMap { try? JSONDecoder().decode(CachedReply.self, from: $0) }
    }

    private func file(session: String, agent: String) -> URL {
        directory.appendingPathComponent("\(agent)-\(session.replacingOccurrences(of: "/", with: "_")).json")
    }

    /// Most recent reply, preferring sessions running in `cwd` (the CLI doesn't
    /// know which session invoked it, but the working directory narrows it down).
    public func latest(cwd: String? = nil) -> CachedReply? {
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
