import Foundation
import Yams

/// Hidden notes mirroring each agent session's latest reply, one file per session in
/// `_sessions/` (the underscore keeps it out of folder lists). When a new session starts
/// in the same project, the previous session's note is handed back as "pending".
public enum Sessions {
    public static let folder = "_sessions"
    /// Per project; older session notes beyond this are deleted.
    static let keepPerTopic = 10

    static func url(in store: NoteStore, topic: String, session: String) -> URL {
        store.root.appendingPathComponent(folder, isDirectory: true)
            .appendingPathComponent("\(FileName.safe(topic))--\(FileName.safe(session)).md")
    }

    public static func all(in store: NoteStore) -> [Note] {
        let dir = store.root.appendingPathComponent(folder, isDirectory: true)
        let notes = (try? store.loadNotes(in: dir, skipUnderscored: false)) ?? []
        return notes.sorted { Note.isOlder($1, $0) }
    }

    /// Long enough to hold detail even without code, tables or headings.
    static let detailedLength = 1500

    /// Whether a reply is worth handing to the next session. Status lines and short wrap-ups
    /// ("listo, 40 tests pasan y X ya está en prod") aren't: the user doesn't need to see them
    /// again. Code, tables, headings or a long explanation are.
    public static func isWorthKeeping(_ text: String) -> Bool {
        let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let structured = lines.contains { $0.hasPrefix("```") || $0.hasPrefix("~~~")
            || $0.range(of: #"^#{1,6} "#, options: .regularExpression) != nil }
            || lines.contains { $0.hasPrefix("|") && $0.contains("---") }
        return structured || text.trimmingCharacters(in: .whitespacesAndNewlines).count >= detailedLength
    }

    /// Upserts the session's note with its latest reply and reopens it.
    @discardableResult
    public static func record(_ reply: CachedReply, topic: String, in store: NoteStore) throws -> Note {
        let file = url(in: store, topic: topic, session: reply.session)
        let now = Timestamp.now()
        var node: Node
        if let text = try? String(contentsOf: file, encoding: .utf8) {
            node = try Frontmatter.parse(Frontmatter.split(text).yaml)
        } else {
            node = Frontmatter.emptyMapping
            Frontmatter.set(Node(now), at: ["created"], in: &node)
            Frontmatter.set(Node(topic), at: ["topic"], in: &node)
            Frontmatter.set(Node(reply.agent), at: ["source"], in: &node)
            Frontmatter.set(Node(DisplayStyle.report.rawValue), at: ["display", "style"], in: &node)
            Frontmatter.set(Node(reply.session), at: ["session", "id"], in: &node)
            Frontmatter.set(Node(reply.agent), at: ["session", "agent"], in: &node)
            Frontmatter.set(Node(now), at: ["session", "started"], in: &node)
            if let cwd = reply.cwd { Frontmatter.set(Node(cwd), at: ["session", "cwd"], in: &node) }
        }
        Frontmatter.set(Node(ReplyCache.title(from: reply.text)), at: ["title"], in: &node)
        Frontmatter.set(Node(NoteStatus.read.rawValue), at: ["status"], in: &node)
        Frontmatter.set(Node(now), at: ["session", "last"], in: &node)
        Frontmatter.set(nil, at: ["session", "ended"], in: &node)
        Frontmatter.set(nil, at: ["session", "reason"], in: &node)
        Frontmatter.set(.mapping(Node.Mapping([(Node("status"), Node(ResumeStatus.open.rawValue))])), at: ["resume"], in: &node)
        try store.write(node: node, body: reply.text, to: file)
        dropHandedOver(topic: topic, excluding: reply.session, in: store)
        prune(topic: topic, in: store)
        return try store.loadNote(at: file)
    }

    /// Marks the session as closed normally (SessionEnd). Missing after a crash or shutdown, which is fine.
    public static func end(session: String, reason: String?, in store: NoteStore) {
        for note in all(in: store) where note.meta.session?.id == session {
            _ = try? store.updateFrontmatter(note.id, touch: false) { node in
                Frontmatter.set(Node(Timestamp.now()), at: ["session", "ended"], in: &node)
                if let reason { Frontmatter.set(Node(reason), at: ["session", "reason"], in: &node) }
            }
        }
    }

    /// Called when a session starts in `topic`: returns the latest other session's open
    /// note, marked `requested` so the app notifies once. Older open ones become `superseded`.
    public static func takePending(topic: String, excluding session: String, in store: NoteStore) throws -> Note? {
        dropHandedOver(topic: topic, excluding: session, in: store)
        let open = all(in: store).filter {
            $0.meta.topic == topic && $0.meta.session?.id != session && $0.meta.resume?.resolvedStatus == .open
        }
        guard let latest = open.first else { return nil }
        for older in open.dropFirst() { try setResume(older.id, .superseded, in: store) }
        return try store.updateFrontmatter(latest.id, touch: false) { node in
            Frontmatter.set(Node(ResumeStatus.requested.rawValue), at: ["resume", "status"], in: &node)
            Frontmatter.set(Node(Timestamp.now()), at: ["resume", "requested"], in: &node)
            Frontmatter.set(nil, at: ["resume", "notified"], in: &node)
        }
    }

    /// Session notes the app still has to notify about.
    public static func needingNotification(in store: NoteStore) -> [Note] {
        all(in: store).filter { $0.meta.resume?.resolvedStatus == .requested && $0.meta.resume?.notified == nil }
    }

    public static func markNotified(_ id: String, in store: NoteStore) throws {
        try store.updateFrontmatter(id, touch: false) { Frontmatter.set(Node(Timestamp.now()), at: ["resume", "notified"], in: &$0) }
    }

    @discardableResult
    public static func setResume(_ id: String, _ status: ResumeStatus, in store: NoteStore) throws -> Note {
        try store.updateFrontmatter(id, touch: false) { Frontmatter.set(Node(status.rawValue), at: ["resume", "status"], in: &$0) }
    }

    /// Short context for the new session, so the agent knows without reading the whole note.
    public static func startupContext(for note: Note) -> String {
        let when = note.meta.session?.last.flatMap(Timestamp.parse).map { DateFormatter.logHeading.string(from: $0) } ?? "?"
        let how = note.meta.session?.ended == nil ? "se interrumpió (sin cierre normal)" : "se cerró"
        return """
        coTs: la sesión anterior de este proyecto (\(when)) \(how). Su último mensaje fue: «\(note.title)».
        La nota completa es `\(note.id)` (`cots read \(note.id)`). El usuario recibió un aviso en coTs; \
        si quiere retomarla, léela antes de continuar. No la leas si no hace falta.
        """
    }

    /// A note already handed to a later session (resume no longer `open`) has done its job:
    /// that later session's own note replaces it, or, if it never left one, the next session
    /// to start removes it. The project keeps a single last message instead of a pile.
    private static func dropHandedOver(topic: String, excluding session: String, in store: NoteStore) {
        for note in all(in: store) where note.meta.topic == topic && note.meta.session?.id != session
            && note.meta.resume?.resolvedStatus ?? .open != .open {
            try? FileManager.default.removeItem(at: note.url)
        }
    }

    private static func prune(topic: String, in store: NoteStore) {
        for note in all(in: store).filter({ $0.meta.topic == topic }).dropFirst(keepPerTopic) {
            try? FileManager.default.removeItem(at: note.url)
        }
    }
}
