import Foundation

// The frontmatter schema. Every field is optional and enum-like values are kept
// as strings so that a note hand-edited (or written by an AI) with an unknown
// value still loads; the typed accessors fall back to sensible defaults.

public enum NoteStatus: String, CaseIterable, Sendable {
    case unread, read, archived
}

public enum DisplayStyle: String, CaseIterable, Sendable {
    /// Rendered markdown.
    case document
    /// Rendered markdown with the summary as a highlighted lead.
    case report
    /// `- [ ]` items become toggles that write back to the file.
    case checklist
    /// `## <timestamp>` sections rendered as a timeline, newest first.
    case log
    /// Monospaced, unrendered.
    case code
    /// A plan proposed by an agent, waiting for the user to approve, request changes or reject.
    case plan
}

public enum ReviewStatus: String, CaseIterable, Sendable {
    case pending, approved, changes, rejected
}

/// The user's verdict on a `plan` note. `cots wait` blocks until `status` leaves `pending`.
public struct Review: Codable, Equatable, Sendable {
    public var status: String?
    public var comment: String?
    public var at: String?
    /// When an agent read a `changes` verdict (`cots wait`, `get_plan_review`): from then
    /// until it replaces the plan, the app shows the agent as working on it.
    public var seen: String?

    public init(status: String? = nil, comment: String? = nil, at: String? = nil, seen: String? = nil) {
        self.status = status
        self.comment = comment
        self.at = at
        self.seen = seen
    }

    public var resolvedStatus: ReviewStatus { ReviewStatus(rawValue: status ?? "") ?? .pending }
}

public enum ActionType: String, CaseIterable, Sendable {
    /// Copy `text` (or the note body) to the clipboard.
    case copy
    /// Open `url` in the default browser/handler.
    case openURL = "open_url"
    /// Open `path` with its default app.
    case openFile = "open_file"
    /// Reveal `path` in Finder.
    case reveal
    /// Run `command` in a shell. Always asks for confirmation first.
    case run
}

public struct Display: Codable, Equatable, Sendable {
    public var style: String?
    /// SF Symbol name.
    public var icon: String?
    /// blue, green, orange, red, purple, pink, yellow, gray, or #RRGGBB.
    public var color: String?
    public var pinned: Bool?

    public init(style: String? = nil, icon: String? = nil, color: String? = nil, pinned: Bool? = nil) {
        self.style = style
        self.icon = icon
        self.color = color
        self.pinned = pinned
    }

    public var resolvedStyle: DisplayStyle { DisplayStyle(rawValue: style ?? "") ?? .document }
}

public struct NoteAction: Codable, Equatable, Sendable {
    public var type: String
    public var label: String?
    public var url: String?
    public var path: String?
    public var command: String?
    public var text: String?

    public init(type: String, label: String? = nil, url: String? = nil, path: String? = nil,
                command: String? = nil, text: String? = nil) {
        self.type = type
        self.label = label
        self.url = url
        self.path = path
        self.command = command
        self.text = text
    }

    public var resolvedType: ActionType? { ActionType(rawValue: type) }

    public var displayLabel: String {
        if let label, !label.isEmpty { return label }
        switch resolvedType {
        case .copy: return "Copiar"
        case .openURL: return "Abrir enlace"
        case .openFile: return "Abrir archivo"
        case .reveal: return "Mostrar en Finder"
        case .run: return "Ejecutar"
        case nil: return type
        }
    }
}

/// Machine context for AIs. Never rendered in the note body and only returned by
/// the CLI when explicitly requested (`cots read --ai`), so it doesn't cost
/// context unless an agent actually needs it.
public struct AIContext: Codable, Equatable, Sendable {
    public var agent: String?
    public var model: String?
    public var session: String?
    public var cwd: String?
    public var project: String?
    public var branch: String?
    /// Files the session touched or that matter for this note.
    public var files: [String]?
    /// Commits, PRs, issues, URLs.
    public var refs: [String]?
    /// Concrete next steps for whoever (or whatever) picks this up.
    public var next: [String]?
    /// Free-form context meant for a future agent, not for the human reader.
    public var context: String?

    public init() {}
}

/// The agent session a hidden session note mirrors.
public struct SessionInfo: Codable, Equatable, Sendable {
    public var id: String?
    public var agent: String?
    public var cwd: String?
    public var started: String?
    public var last: String?
    public var ended: String?
    public var reason: String?

    public init(id: String? = nil, agent: String? = nil, cwd: String? = nil) {
        self.id = id
        self.agent = agent
        self.cwd = cwd
    }
}

public enum ResumeStatus: String, Sendable {
    /// Has a last message nobody has been reminded of yet.
    case open
    /// A new session in the project asked for it; the app notifies once.
    case requested
    case dismissed
    /// An older session overtaken by a newer one in the same project.
    case superseded
}

public struct ResumeInfo: Codable, Equatable, Sendable {
    public var status: String?
    public var requested: String?
    public var notified: String?

    public init(status: String? = nil) { self.status = status }

    public var resolvedStatus: ResumeStatus { ResumeStatus(rawValue: status ?? "") ?? .open }
}

public struct NoteMeta: Codable, Equatable, Sendable {
    public var title: String?
    /// One line. Shown under the title and returned by `cots list`, so agents
    /// can triage notes without reading their bodies.
    public var summary: String?
    public var created: String?
    public var updated: String?
    public var status: String?
    public var tags: [String]?
    /// Project the note belongs to. Agents set it from the repo they run in, so notes
    /// group and color by project automatically.
    public var topic: String?
    /// Who wrote it: "user", "claude-code", "cursor", ...
    public var source: String?
    public var display: Display?
    public var actions: [NoteAction]?
    public var ai: AIContext?
    public var review: Review?
    /// Only on hidden session notes (`_sessions/`).
    public var session: SessionInfo?
    public var resume: ResumeInfo?

    public init(title: String? = nil) {
        self.title = title
    }

    public var resolvedStatus: NoteStatus { NoteStatus(rawValue: status ?? "") ?? .read }
    public var isPinned: Bool { display?.pinned ?? false }
    public var createdDate: Date? { created.flatMap(Timestamp.parse) }
    public var updatedDate: Date? { updated.flatMap(Timestamp.parse) }

    /// Canonical key order used when writing frontmatter. Unknown keys go after these.
    public static let keyOrder = ["title", "summary", "created", "updated", "status", "review", "topic", "tags", "source",
                                  "display", "actions", "session", "resume", "ai"]
}
