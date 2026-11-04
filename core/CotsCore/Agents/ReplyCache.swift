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
        prune()
    }

    /// One file per session would otherwise pile up forever: keep the newest `keep`,
    /// and nothing older than `maxAge`.
    static let keep = 200
    static let maxAge: TimeInterval = 30 * 24 * 3600

    func prune() {
        let files = newestFirst()
        let cutoff = Date().addingTimeInterval(-Self.maxAge)
        for (index, (date, url)) in files.enumerated() where index >= Self.keep || date < cutoff {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func newestFirst() -> [(Date, URL)] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return urls.filter { $0.pathExtension == "json" }
            .map { (((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast), $0) }
            .sorted { $0.0 > $1.0 }
    }

    public func reply(session: String, agent: String) -> CachedReply? {
        (try? Data(contentsOf: file(session: session, agent: agent))).flatMap { try? JSONDecoder().decode(CachedReply.self, from: $0) }
    }

    private func file(session: String, agent: String) -> URL {
        directory.appendingPathComponent("\(FileName.safe(agent))-\(FileName.safe(session)).json")
    }

    /// Most recent reply, preferring sessions running in `cwd` (the CLI doesn't
    /// know which session invoked it, but the working directory narrows it down).
    public func latest(cwd: String? = nil) -> CachedReply? {
        // Newest first, decoding only until a match: the cache can hold hundreds of replies.
        var newest: CachedReply?
        for (_, url) in newestFirst() {
            guard let data = try? Data(contentsOf: url), let reply = try? JSONDecoder().decode(CachedReply.self, from: data) else { continue }
            if newest == nil { newest = reply }
            if cwd == nil || reply.cwd == cwd { return reply }
        }
        return newest
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
