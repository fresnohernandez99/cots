import AppKit
import CotsCore
import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    private(set) var store: NoteStore
    private(set) var folders: [Folder] = []
    private(set) var notes: [Note] = []
    /// Hidden `_sessions/` notes: each agent session's latest reply, per project.
    private(set) var sessionNotes: [Note] = []
    /// The expanded window's "Sesiones" view.
    var showSessions = false
    var selectedFolder: String?
    var selectedTopic: String?
    /// Note shown in the expanded window; the popover sets it before opening the window.
    var windowSelection: String?
    var search = ""
    var showArchived = false
    var showFinishedPlans = false
    /// Set by the menu bar command; the expanded window shows the new-note sheet.
    var showingNewNote = false
    var lastError: String?

    private var watcher: FileWatcher?

    init() {
        store = NoteStore()
        bootstrap()
    }

    var unreadCount: Int { notes.filter { $0.meta.resolvedStatus == .unread }.count }

    /// Projects that have notes, most used first.
    var topics: [String] {
        let counts = Dictionary(grouping: notes.compactMap(\.meta.topic), by: { $0 }).mapValues(\.count)
        return counts.keys.sorted { counts[$0]! != counts[$1]! ? counts[$0]! > counts[$1]! : $0 < $1 }
    }

    var pendingPlans: Int {
        notes.filter { $0.style == .plan && $0.meta.review?.resolvedStatus ?? .pending == .pending
            && $0.meta.resolvedStatus != .archived }.count
    }

    var visibleNotes: [Note] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        if showSessions {
            return sessionNotes.filter { q.isEmpty || $0.title.lowercased().contains(q) || $0.body.lowercased().contains(q) }
        }
        return notes.filter { note in
            (selectedFolder == nil || note.folder == selectedFolder)
                && (selectedTopic == nil || note.meta.topic == selectedTopic)
                && (showArchived ? note.meta.resolvedStatus == .archived : note.meta.resolvedStatus != .archived)
                && (q.isEmpty || [note.title, note.meta.summary ?? "", note.meta.topic ?? "", note.body, (note.meta.tags ?? []).joined(separator: " ")]
                    .contains { $0.lowercased().contains(q) })
        }
    }

    func note(_ id: String) -> Note? { notes.first { $0.id == id } ?? sessionNotes.first { $0.id == id } }

    /// Sessions handed back to a new session and not yet dismissed.
    var pendingSessions: [Note] { sessionNotes.filter { $0.meta.resume?.resolvedStatus == .requested } }

    func unread(in folder: String) -> Int {
        notes.filter { $0.folder == folder && $0.meta.resolvedStatus == .unread }.count
    }

    func reload() {
        do {
            // Only publish real changes: reassigning identical arrays makes the
            // lists re-diff (and jump) on every file event, including our own writes.
            let newFolders = try store.folders()
            let newNotes = try store.notes()
            if newFolders != folders { folders = newFolders }
            if newNotes != notes { notes = newNotes }
            let newSessions = Sessions.all(in: store)
            if newSessions != sessionNotes { sessionNotes = newSessions }
            notifyPendingSessions()
            if let selected = selectedFolder, !folders.contains(where: { $0.name == selected }) { selectedFolder = nil }
            if let topic = selectedTopic, !notes.contains(where: { $0.meta.topic == topic }) { selectedTopic = nil }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func changeRoot(to url: URL) {
        do {
            try CotsConfig.saveRoot(url)
            store = NoteStore(root: url)
            selectedFolder = nil
            bootstrap()
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func bootstrap() {
        do { try store.ensureRoot() } catch { lastError = error.localizedDescription }
        reload()
        watcher = FileWatcher(url: store.root) { [weak self] in
            Task { @MainActor in self?.reload() }
        }
    }

    // MARK: Mutations

    private func perform(_ work: () throws -> Void) {
        do {
            try work()
        } catch {
            lastError = error.localizedDescription
        }
        reload()
    }

    func markRead(_ note: Note) {
        guard note.meta.resolvedStatus == .unread else { return }
        perform { try store.setStatus(note.id, .read) }
    }

    func setStatus(_ note: Note, _ status: NoteStatus) { perform { try store.setStatus(note.id, status) } }
    /// Each handed-back session is notified once; the mark lives in the note so it
    /// survives relaunches.
    private func notifyPendingSessions() {
        for note in Sessions.needingNotification(in: store) {
            Notifier.shared.post(note)
            try? Sessions.markNotified(note.id, in: store)
        }
    }

    func dismissSession(_ note: Note) { perform { try Sessions.setResume(note.id, .dismissed, in: store) } }

    /// Keeps the session's last message as a regular note, then dismisses the reminder.
    @discardableResult
    func promoteSession(_ note: Note) -> Note? {
        var meta = NoteMeta(title: note.title)
        meta.topic = note.meta.topic
        meta.source = note.meta.source
        meta.status = NoteStatus.read.rawValue
        var created: Note?
        perform {
            created = try store.create(folder: NoteStore.defaultFolder, frontmatter: Frontmatter.node(from: meta), body: note.body)
            try Sessions.setResume(note.id, .dismissed, in: store)
        }
        return created
    }

    func setReview(_ note: Note, _ status: ReviewStatus, comment: String) {
        perform { try store.setReview(note.id, status, comment: comment) }
    }

    /// nil = automatic (topic, then folder color).
    func setColor(_ note: Note, _ color: String?) {
        perform { try store.setColor(note.id, color) }
    }

    var selectedNote: Note? { windowSelection.flatMap(note) }

    func togglePin(_ note: Note) { perform { try store.setPinned(note.id, !note.meta.isPinned) } }
    func saveBody(_ note: Note, _ body: String) { perform { try store.updateBody(note.id, body: body) } }
    func trash(_ note: Note) { perform { try store.trash(note.id) } }

    func toggleTask(_ note: Note, line: Int) {
        var lines = note.body.components(separatedBy: "\n")
        guard lines.indices.contains(line) else { return }
        let l = lines[line]
        if let r = l.range(of: "[ ]") {
            lines[line] = l.replacingCharacters(in: r, with: "[x]")
        } else if let r = l.range(of: "[x]") ?? l.range(of: "[X]") {
            lines[line] = l.replacingCharacters(in: r, with: "[ ]")
        }
        saveBody(note, lines.joined(separator: "\n"))
    }

    @discardableResult
    func create(folder: String, title: String, style: DisplayStyle, topic: String, color: String?, body: String) -> Note? {
        var meta = NoteMeta(title: title)
        meta.source = "user"
        meta.status = NoteStatus.read.rawValue
        let topic = topic.trimmingCharacters(in: .whitespaces)
        meta.topic = topic.isEmpty ? nil : topic
        meta.display = Display(style: style.rawValue, color: color)
        if style == .plan { meta.review = Review(status: ReviewStatus.pending.rawValue) }
        var created: Note?
        perform { created = try store.create(folder: folder, frontmatter: Frontmatter.node(from: meta), body: body) }
        return created
    }

    func createFolder(_ name: String) {
        perform { try store.createFolder(name) }
    }
}

/// Watches the notes root recursively so edits from the CLI, an agent or another
/// editor show up immediately.
final class FileWatcher {
    private var stream: FSEventStreamRef?
    private let onChange: () -> Void

    init(url: URL, onChange: @escaping () -> Void) {
        self.onChange = onChange
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue().onChange()
        }
        stream = FSEventStreamCreate(nil, callback, &context, [url.path] as CFArray,
                                     FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.3,
                                     FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents))
        if let stream {
            FSEventStreamSetDispatchQueue(stream, .main)
            FSEventStreamStart(stream)
        }
    }

    deinit {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }
}
