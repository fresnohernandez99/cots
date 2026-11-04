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
