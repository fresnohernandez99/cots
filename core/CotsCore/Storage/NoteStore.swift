import Foundation
import Yams

public final class NoteStore: @unchecked Sendable {
    public let root: URL
    private let fm = FileManager.default
    private let cache = NoteCache()

    public init(root: URL = CotsConfig.resolveRoot()) {
        self.root = root
    }

    public static let defaultFolder = "code-notes"
    public static let plansFolder = "plans"

    /// Creates the root and the two built-in folders when missing. Existing
    /// `_folder.yml` files are never overwritten.
    public func ensureRoot() throws {
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let builtIn: [(String, FolderConfig)] = [
            (Self.defaultFolder, FolderConfig(
                title: "Code notes",
                description: "Informes y notas de sesiones con IAs.",
                icon: "chevron.left.forwardslash.chevron.right",
                color: "blue",
                defaults: { var d = NoteMeta(); d.display = Display(style: DisplayStyle.report.rawValue); return d }(),
                ai: FolderAI(instructions: "Carpeta por defecto: úsala cuando el usuario diga 'guarda en cots' sin nombrar otra.")
            )),
            (Self.plansFolder, FolderConfig(
                title: "Plans",
                description: "Planes propuestos por IAs, pendientes de revisión.",
                icon: "list.bullet.clipboard",
                color: "purple",
                defaults: { var d = NoteMeta(); d.display = Display(style: DisplayStyle.plan.rawValue); return d }(),
                ai: FolderAI(instructions: "Crea el plan con `cots plan` y espera la decisión con `cots wait <id>`.")
            )),
        ]
        for (name, config) in builtIn where !fm.fileExists(atPath: root.appendingPathComponent(name).path) {
            try createFolder(name, config: config)
        }
    }

    // MARK: Folders

    public func folders() throws -> [Folder] { try scan().folders }

    /// Folders with their counts and every note, newest first, from one pass over the disk.
    public func scan() throws -> (folders: [Folder], notes: [Note]) {
        guard fm.fileExists(atPath: root.path) else { return ([], []) }
        let urls = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey],
                                              options: [.skipsHiddenFiles])
        var folders: [Folder] = []
        var notes: [Note] = []
        for url in urls where !url.lastPathComponent.hasPrefix("_")
            && (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            let inFolder = try loadNotes(in: url)
            folders.append(Folder(name: url.lastPathComponent, url: url, config: folderConfig(url.lastPathComponent),
                                  noteCount: inFolder.count,
                                  unreadCount: inFolder.count { $0.meta.resolvedStatus == .unread }))
            notes += inFolder
        }
        folders.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return (folders, Self.sorted(notes))
    }

    public func folderConfig(_ name: String) -> FolderConfig {
        let url = root.appendingPathComponent(name).appendingPathComponent(FolderConfig.fileName)
        guard let yaml = try? String(contentsOf: url, encoding: .utf8),
              let config = try? YAMLDecoder().decode(FolderConfig.self, from: yaml) else { return FolderConfig() }
        return config
    }

    @discardableResult
    public func createFolder(_ name: String, config: FolderConfig = FolderConfig()) throws -> Folder {
        try Self.validateFolderName(name)
        let url = root.appendingPathComponent(name, isDirectory: true)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        let configURL = url.appendingPathComponent(FolderConfig.fileName)
        if config != FolderConfig() || !fm.fileExists(atPath: configURL.path) {
            try Frontmatter.yaml(config).write(to: configURL, atomically: true, encoding: .utf8)
        }
        Ownership.matchHome(root, url, configURL)
        return Folder(name: name, url: url, config: config, noteCount: 0, unreadCount: 0)
    }

    public static func validateFolderName(_ name: String) throws {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        guard !name.isEmpty, !name.hasPrefix("_"), !name.hasPrefix("."), name.count <= 80,
              name.unicodeScalars.allSatisfy(allowed.contains) else {
            throw CotsError.invalidFolderName(name)
        }
    }

    // MARK: Reading

    public func notes(in folder: String? = nil, includeArchived: Bool = true) throws -> [Note] {
        var result: [Note]
        if let folder {
            let url = root.appendingPathComponent(folder, isDirectory: true)
            guard fm.fileExists(atPath: url.path) else { throw CotsError.folderNotFound(folder) }
            result = Self.sorted(try loadNotes(in: url))
        } else {
            result = try scan().notes
        }
        if !includeArchived { result.removeAll { $0.meta.resolvedStatus == .archived } }
        return result
    }

    /// Pinned first, then newest first.
    public static func sorted(_ notes: [Note]) -> [Note] {
        notes.sorted { a, b in
            if a.meta.isPinned != b.meta.isPinned { return a.meta.isPinned }
            return Note.isOlder(b, a)
        }
    }

    /// Every note in a directory, parsing only files that changed since the last call.
    /// Files that fail to read are skipped; broken frontmatter still loads (see `parseError`).
    func loadNotes(in directory: URL, skipUnderscored: Bool = true) throws -> [Note] {
        let urls = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            .filter { $0.pathExtension == "md" && !(skipUnderscored && $0.lastPathComponent.hasPrefix("_")) }
        cache.retain(only: Set(urls.map(\.path)), under: directory.path + "/")
        // Files are independent, so a cold load parses them on every core.
        var loaded = [Note?](repeating: nil, count: urls.count)
        loaded.withUnsafeMutableBufferPointer { buffer in
            nonisolated(unsafe) let slots = buffer
            DispatchQueue.concurrentPerform(iterations: urls.count) { i in slots[i] = try? loadNote(at: urls[i]) }
        }
        return loaded.compactMap { $0 }
    }

    /// Accepts `folder/name`, `folder/name.md`, `folder/latest`, or a bare `name` searched across folders.
    public func note(id rawID: String) throws -> Note {
        let id = rawID.hasSuffix(".md") ? String(rawID.dropLast(3)) : rawID
        let parts = id.split(separator: "/", maxSplits: 1).map(String.init)
        if parts.count == 2 {
            if parts[1] == "latest" {
                guard let latest = try notes(in: parts[0]).max(by: Note.isOlder) else {
                    throw CotsError.noteNotFound(rawID)
                }
                return latest
            }
            let url = root.appendingPathComponent(parts[0]).appendingPathComponent(parts[1] + ".md")
            guard fm.fileExists(atPath: url.path) else { throw CotsError.noteNotFound(rawID) }
            return try loadNote(at: url)
        }
        guard let match = try notes().first(where: { $0.url.deletingPathExtension().lastPathComponent == id }) else {
            throw CotsError.noteNotFound(rawID)
        }
        return match
    }

    public func loadNote(at url: URL) throws -> Note {
        let stamp = NoteCache.Stamp(path: url.path)
        if let stamp, let cached = cache.note(at: url.path, stamp: stamp) { return cached }
        let text = try String(contentsOf: url, encoding: .utf8)
        let (yaml, body) = Frontmatter.split(text)
        let folder = url.deletingLastPathComponent().lastPathComponent
        let modified = stamp?.modified ?? Date()
        var meta = NoteMeta()
        var parseError: String?
        do {
            meta = try Frontmatter.decodeMeta(Frontmatter.parse(yaml))
        } catch {
            parseError = String(describing: error)
        }
        let note = Note(id: "\(folder)/\(url.deletingPathExtension().lastPathComponent)", folder: folder, url: url,
                        meta: meta, body: body, modified: modified, parseError: parseError)
        if let stamp { cache.store(note, at: url.path, stamp: stamp) }
        return note
    }

    public func search(_ query: String, in folder: String? = nil) throws -> [Note] {
        let matcher = TextMatcher(query)
        return try notes(in: folder).filter { $0.matches(matcher) }
    }

    // MARK: Writing

    /// Creates a note. `frontmatter` may carry any keys; the folder's defaults fill
    /// what's missing, and `created`/`status` are set if absent.
    @discardableResult
    public func create(folder: String, frontmatter input: Node = Frontmatter.emptyMapping, body: String) throws -> Note {
        try Self.validateFolderName(folder)
        let folderURL = root.appendingPathComponent(folder, isDirectory: true)
        if !fm.fileExists(atPath: folderURL.path) { try createFolder(folder) }

        var node = input
        if let defaults = folderConfig(folder).defaults {
            Frontmatter.merge(defaults: try Frontmatter.node(from: defaults), into: &node)
        }
        if node["created"] == nil { Frontmatter.set(Node(Timestamp.now()), at: ["created"], in: &node) }
        if node["status"] == nil { Frontmatter.set(Node(NoteStatus.unread.rawValue), at: ["status"], in: &node) }

        let meta = try Frontmatter.decodeMeta(node)
        guard let title = meta.title?.trimmingCharacters(in: .whitespaces), !title.isEmpty else {
            throw CotsError.invalidFrontmatter("falta 'title'")
        }

        let url = uniqueURL(in: folderURL, title: title, date: meta.createdDate ?? Date())
        try Frontmatter.join(node: node, body: body).write(to: url, atomically: true, encoding: .utf8)
        Ownership.matchHome(url)
        return try loadNote(at: url)
    }

    /// Edits a note's frontmatter in place, keeping keys this app doesn't model.
    @discardableResult
    public func updateFrontmatter(_ id: String, touch: Bool = true, _ edit: (inout Node) throws -> Void) throws -> Note {
        let note = try note(id: id)
        let text = try String(contentsOf: note.url, encoding: .utf8)
        let (yaml, body) = Frontmatter.split(text)
        var node = try Frontmatter.parse(yaml)
        try edit(&node)
        if touch { Frontmatter.set(Node(Timestamp.now()), at: ["updated"], in: &node) }
        _ = try Frontmatter.decodeMeta(node)
        try Frontmatter.join(node: node, body: body).write(to: note.url, atomically: true, encoding: .utf8)
        Ownership.matchHome(note.url)
        return try loadNote(at: note.url)
    }

    @discardableResult
    public func updateBody(_ id: String, body: String) throws -> Note {
        let note = try note(id: id)
        let text = try String(contentsOf: note.url, encoding: .utf8)
        var node = try Frontmatter.parse(Frontmatter.split(text).yaml)
        Frontmatter.set(Node(Timestamp.now()), at: ["updated"], in: &node)
        try Frontmatter.join(node: node, body: body).write(to: note.url, atomically: true, encoding: .utf8)
        Ownership.matchHome(note.url)
        return try loadNote(at: note.url)
    }

    @discardableResult
    public func setStatus(_ id: String, _ status: NoteStatus) throws -> Note {
        try updateFrontmatter(id, touch: false) { Frontmatter.set(Node(status.rawValue), at: ["status"], in: &$0) }
    }

    /// Records the user's verdict on a plan and marks it read.
    @discardableResult
    public func setReview(_ id: String, _ status: ReviewStatus, comment: String?) throws -> Note {
        try updateFrontmatter(id) { node in
            Frontmatter.set(Node(status.rawValue), at: ["review", "status"], in: &node)
            Frontmatter.set(comment.flatMap { $0.isEmpty ? nil : Node($0) }, at: ["review", "comment"], in: &node)
            Frontmatter.set(Node(Timestamp.now()), at: ["review", "at"], in: &node)
        }
    }

    /// nil removes the explicit color, falling back to the topic's / folder's.
    @discardableResult
    public func setColor(_ id: String, _ color: String?) throws -> Note {
        try updateFrontmatter(id, touch: false) { Frontmatter.set(color.map { Node($0) }, at: ["display", "color"], in: &$0) }
    }

    @discardableResult
    public func setPinned(_ id: String, _ pinned: Bool) throws -> Note {
        try updateFrontmatter(id, touch: false) { Frontmatter.set(Node(pinned ? "true" : "false"), at: ["display", "pinned"], in: &$0) }
    }

    /// Appends a timestamped `## ` entry, the format the `log` style renders as a timeline.
    @discardableResult
    public func append(_ id: String, text: String, markUnread: Bool = true) throws -> Note {
        let note = try note(id: id)
        let stamp = DateFormatter.logHeading.string(from: Date())
        var body = note.body.trimmingCharacters(in: .newlines)
        body += (body.isEmpty ? "" : "\n\n") + "## \(stamp)\n\n" + text.trimmingCharacters(in: .newlines) + "\n"
        _ = try updateBody(id, body: body)
        if markUnread { return try setStatus(id, .unread) }
        return try self.note(id: id)
    }

    /// Writes a note at a fixed location (session notes), creating its folder.
    func write(node: Node, body: String, to url: URL) throws {
        let dir = url.deletingLastPathComponent()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try Frontmatter.join(node: node, body: body).write(to: url, atomically: true, encoding: .utf8)
        Ownership.matchHome(root, dir, url)
    }

    public func trash(_ id: String) throws {
        let url = try note(id: id).url
        #if canImport(Darwin)
        try fm.trashItem(at: url, resultingItemURL: nil)
        #else
        // Foundation has no Recycle Bin elsewhere: keep it under `.trash`, hidden from
        // every listing, so a deleted note can still be recovered by hand.
        let bin = root.appendingPathComponent(".trash", isDirectory: true)
            .appendingPathComponent(url.deletingLastPathComponent().lastPathComponent, isDirectory: true)
        try fm.createDirectory(at: bin, withIntermediateDirectories: true)
        var dest = bin.appendingPathComponent(url.lastPathComponent)
        if fm.fileExists(atPath: dest.path) { dest = bin.appendingPathComponent("\(UUID().uuidString)-\(url.lastPathComponent)") }
        try fm.moveItem(at: url, to: dest)
        #endif
    }

    /// Short names (`261102-1927.md`); the title lives in the frontmatter.
    private func uniqueURL(in folder: URL, title: String, date: Date) -> URL {
        let base = DateFormatter.fileStamp.string(from: date)
        var url = folder.appendingPathComponent(base + ".md")
        var n = 2
        while fm.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(base)-\(n).md")
            n += 1
        }
        return url
    }
}

extension DateFormatter {
    static let fileStamp: DateFormatter = posix("yyMMdd-HHmm")
    public static let logHeading: DateFormatter = posix("yyyy-MM-dd HH:mm")

    private static func posix(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = format
        return f
    }
}
