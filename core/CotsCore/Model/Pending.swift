import Foundation
import Yams

extension Note {
    /// Unchecked Markdown tasks (`- [ ] …`, also `*` and `+` bullets), in order, without
    /// the checkbox. Fenced code blocks are skipped: a task inside one is an example.
    public var openTasks: [String] {
        Self.taskLines(in: body).map(\.task)
    }

    /// The body with the open tasks that `shouldCheck` accepts ticked (`- [x]`), and
    /// those tasks. Everything else, spacing included, is left as it was.
    public func checkingTasks(where shouldCheck: (String) -> Bool) -> (body: String, checked: [String]) {
        Self.checkingTasks(in: body) { _, task in shouldCheck(task) }
    }

    /// Same, deciding by the task's 1-based line in the body as well as its text.
    public static func checkingTasks(in body: String, where shouldCheck: (Int, String) -> Bool) -> (body: String, checked: [String]) {
        var lines = body.components(separatedBy: "\n")
        var checked: [String] = []
        for (index, task, box) in taskLines(in: body) where shouldCheck(index + 1, task) {
            let line = lines[index]
            let i = line.index(line.startIndex, offsetBy: box)
            lines[index] = line.replacingCharacters(in: i..<line.index(after: i), with: "x")
            checked.append(task)
        }
        return (lines.joined(separator: "\n"), checked)
    }

    /// Open tasks with their line number and the offset of the space inside `[ ]`.
    private static func taskLines(in body: String) -> [(line: Int, task: String, box: Int)] {
        var result: [(Int, String, Int)] = []
        var inFence = false
        for (index, line) in body.components(separatedBy: "\n").enumerated() {
            let indent = line.prefix { $0 == " " || $0 == "\t" }.count
            let trimmed = line.dropFirst(indent)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") { inFence.toggle(); continue }
            guard !inFence, let bullet = trimmed.first, "-*+".contains(bullet), trimmed.dropFirst().hasPrefix(" [ ] ") else { continue }
            let task = trimmed.dropFirst(6).trimmingCharacters(in: .whitespaces)
            if !task.isEmpty { result.append((index, task, indent + 3)) }
        }
        return result
    }

    /// A plan still waiting on the user, or sent back for changes the agent hasn't made.
    public var awaitsReview: Bool {
        style == .plan && [.pending, .changes].contains(meta.review?.resolvedStatus ?? .pending)
    }

    /// Sent back for changes and an agent has picked up the request: it's working on the plan.
    public var isBeingRevised: Bool {
        style == .plan && meta.review?.resolvedStatus == .changes && meta.review?.seen != nil
    }

    /// Notes are filed under the project they were written from; names compare without case.
    public func belongs(toTopic topic: String) -> Bool {
        meta.topic?.caseInsensitiveCompare(topic) == .orderedSame
    }
}

/// What's left to do: notes with open tasks and plans awaiting the user. Shared by
/// `cots pending` and the MCP `list_pending` tool so both answer the same way.
public struct PendingReport {
    public let project: String?
    public let items: [(note: Note, tasks: [String])]

    /// `project` nil means every project.
    public init(store: NoteStore, project: String?) throws {
        self.project = project
        var notes = try store.notes(includeArchived: false)
        if let project { notes = notes.filter { $0.belongs(toTopic: project) } }
        items = notes.compactMap { note in
            let tasks = note.openTasks
            return tasks.isEmpty && !note.awaitsReview ? nil : (note, tasks)
        }
    }

    public var text: String {
        var out = project.map { "Pendientes de \($0)" } ?? "Pendientes de todos los proyectos"
        if items.isEmpty { return out + "\nNada pendiente." }
        for (note, tasks) in items {
            out += "\n\n\(note.id)  \(project == nil ? note.meta.topic.map { "[\($0)] " } ?? "" : "")\(note.title)"
            if note.awaitsReview { out += note.meta.review?.resolvedStatus == .changes ? " (cambios pedidos)" : " (plan por revisar)" }
            for task in tasks { out += "\n  - [ ] \(task)" }
        }
        return out
    }
}

extension NoteStore {
    /// Flips the checkbox of the task on `line` (1-based, in the body) between `[ ]` and
    /// `[x]`, in the file as it is now. A line that isn't a task is left alone.
    @discardableResult
    public func toggleTask(_ id: String, line: Int) throws -> Note {
        try mutate(id) { node, body in
            var lines = body.components(separatedBy: "\n")
            guard lines.indices.contains(line - 1) else { return }
            let text = lines[line - 1]
            let indent = text.prefix { $0 == " " || $0 == "\t" }.count
            let rest = text.dropFirst(indent)
            guard let bullet = rest.first, "-*+".contains(bullet) else { return }
            let box = rest.dropFirst()
            let mark: String
            if box.hasPrefix(" [ ]") { mark = "x" } else if box.hasPrefix(" [x]") || box.hasPrefix(" [X]") { mark = " " } else { return }
            let i = text.index(text.startIndex, offsetBy: indent + 3)
            lines[line - 1] = text.replacingCharacters(in: i..<text.index(after: i), with: mark)
            body = lines.joined(separator: "\n")
            Frontmatter.set(Node(Timestamp.now()), at: ["updated"], in: &node)
        }
    }
}
