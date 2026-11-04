import Foundation

public struct Note: Identifiable, Equatable, Sendable {
    /// `<folder>/<file name without .md>`, the handle agents use with the CLI.
    public var id: String
    public var folder: String
    public var url: URL
    public var meta: NoteMeta
    public var body: String
    public var modified: Date
    /// Set when the frontmatter couldn't be decoded; the note still shows, untyped.
    public var parseError: String?
    /// `created`, else the modification date. Parsed once here: sorting compares it
    /// thousands of times, and parsing a timestamp is slow.
    public let date: Date

    init(id: String, folder: String, url: URL, meta: NoteMeta, body: String, modified: Date, parseError: String?) {
        self.id = id
        self.folder = folder
        self.url = url
        self.meta = meta
        self.body = body
        self.modified = modified
        self.parseError = parseError
        date = meta.createdDate ?? modified
    }

    public var title: String {
        if let t = meta.title, !t.isEmpty { return t }
        return url.deletingPathExtension().lastPathComponent
    }

    public var style: DisplayStyle { meta.display?.resolvedStyle ?? .document }

    /// Case-insensitive match on title, summary, tags and body.
    public func matches(_ query: String) -> Bool {
        matches(TextMatcher(query))
    }

    public func matches(_ matcher: TextMatcher) -> Bool {
        matcher.matches(title) || matcher.matches(meta.summary ?? "")
            || (meta.tags ?? []).contains(where: matcher.matches) || matcher.matches(body)
    }

    /// Creation date, then modification date as a tie-break (several notes can share a second).
    public static func isOlder(_ a: Note, _ b: Note) -> Bool {
        if a.date != b.date { return a.date < b.date }
        if a.modified != b.modified { return a.modified < b.modified }
        return a.id < b.id
    }
}

/// Contents of `<folder>/_folder.yml`.
public struct FolderConfig: Codable, Equatable, Sendable {
    public var title: String?
    public var description: String?
    public var icon: String?
    public var color: String?
    /// Frontmatter merged into every new note created in this folder (the note wins on conflicts).
    public var defaults: NoteMeta?
    public var ai: FolderAI?

    public init(title: String? = nil, description: String? = nil, icon: String? = nil, color: String? = nil,
                defaults: NoteMeta? = nil, ai: FolderAI? = nil) {
        self.title = title
        self.description = description
        self.icon = icon
        self.color = color
        self.defaults = defaults
        self.ai = ai
    }

    public static let fileName = "_folder.yml"
}

public struct FolderAI: Codable, Equatable, Sendable {
    /// How an agent should write notes in this folder.
    public var instructions: String?
    /// Markdown skeleton for the body.
    public var template: String?

    public init(instructions: String? = nil, template: String? = nil) {
        self.instructions = instructions
        self.template = template
    }
}

public struct Folder: Identifiable, Equatable, Sendable {
    public var name: String
    public var url: URL
    public var config: FolderConfig
    public var noteCount: Int
    public var unreadCount: Int

    public var id: String { name }
    public var title: String { config.title ?? name }
}

/// Case-insensitive substring search. ASCII queries (the usual case) go to `strcasestr`,
/// many times faster than lowercasing every note or asking Foundation; non-ASCII bytes
/// in the text are compared as is, which is right for an ASCII query.
public struct TextMatcher: Sendable {
    private let query: String
    private let ascii: Bool

    public init(_ query: String) {
        ascii = query.utf8.allSatisfy { $0 < 128 }
        self.query = ascii ? query : query.lowercased()
    }

    public func matches(_ text: String) -> Bool {
        guard !query.isEmpty else { return true }
        guard ascii else { return text.lowercased().contains(query) }
        return text.withCString { hay in query.withCString { strcasestr(hay, $0) != nil } }
    }
}
