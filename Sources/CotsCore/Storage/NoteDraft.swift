import Foundation
import Yams

/// A note about to be created. The CLI, the MCP server, the agent hooks and the app
/// all describe new notes and plans with one of these, so the frontmatter they write
/// can't drift apart.
public struct NoteDraft {
    public var folder: String
    public var body: String
    /// Frontmatter to start from (a note piped in with its own `---` block); the
    /// fields below override it.
    public var base: Node = Frontmatter.emptyMapping

    public var title: String?
    public var summary: String?
    public var topic: String?
    public var source: String?
    /// Kept as text like every enum-like field: an unknown value still loads, as `read`.
    public var status: String?
    public var tags: [String]?
    public var style: String?
    public var icon: String?
    public var color: String?
    public var pinned = false
    /// Set on plans: they start `pending` until the user decides.
    public var review: ReviewStatus?
    /// Appended after any actions already in `base`.
    public var actions: [Node] = []
    /// Merged over the `ai` block in `base`: these keys win, the others are kept.
    public var ai: Node?

    public init(folder: String = NoteStore.defaultFolder, body: String) {
        self.folder = folder
        self.body = body
    }

    /// A plan waiting for the user's review in the `plans` folder.
    public static func plan(title: String, body: String) -> NoteDraft {
        var draft = NoteDraft(folder: NoteStore.plansFolder, body: body)
        draft.title = title
        draft.style = DisplayStyle.plan.rawValue
        draft.review = .pending
        return draft
    }

    public mutating func addAction(_ action: NoteAction) throws {
        actions.append(try Frontmatter.node(from: action))
    }

    public mutating func setAI(_ context: AIContext) throws {
        ai = try Frontmatter.node(from: context)
    }

    /// The frontmatter to write, before the folder's defaults and `created`/`status` fill the gaps.
    public func frontmatter() -> Node {
        var node = base
        func set(_ value: String?, _ path: String...) {
            if let value { Frontmatter.set(Node(value), at: path, in: &node) }
        }
        set(title, "title")
        set(summary, "summary")
        set(topic, "topic")
        set(source, "source")
        set(status, "status")
        set(style, "display", "style")
        set(icon, "display", "icon")
        set(color, "display", "color")
        if pinned { set("true", "display", "pinned") }
        if let tags {
            Frontmatter.set(.sequence(Node.Sequence(tags.map { Node($0) })), at: ["tags"], in: &node)
        }
        set(review?.rawValue, "review", "status")
        if let ai {
            var merged = ai
            if let existing = node["ai"] { Frontmatter.merge(defaults: existing, into: &merged) }
            Frontmatter.set(merged, at: ["ai"], in: &node)
        }
        if !actions.isEmpty {
            let existing = node["actions"]?.sequence.map(Array.init) ?? []
            Frontmatter.set(.sequence(Node.Sequence(existing + actions)), at: ["actions"], in: &node)
        }
        return node
    }
}

extension NoteStore {
    @discardableResult
    public func create(_ draft: NoteDraft) throws -> Note {
        try create(folder: draft.folder, frontmatter: draft.frontmatter(), body: draft.body)
    }
}
