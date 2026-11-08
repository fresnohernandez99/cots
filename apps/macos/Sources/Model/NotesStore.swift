import CotsCore
import Foundation
import Observation

/// The notes on disk as the app sees them, and every write the UI makes. Reads happen
/// off the main thread; writes show their result immediately.
@MainActor
@Observable
final class NotesStore {
    private(set) var disk: NoteStore
    private(set) var folders: [Folder] = []
    private(set) var notes: [Note] = []
    /// Hidden `_sessions/` notes: each agent session's latest reply, per project.
    private(set) var sessionNotes: [Note] = []
    var lastError: String?
    /// Called after each reload, so the browser can drop filters that no longer match anything.
    var didReload: (() -> Void)?

    @ObservationIgnored private var watcher: FileWatcher?
    @ObservationIgnored private var reloading = false
    @ObservationIgnored private var reloadAgain = false

    init(disk: NoteStore = NoteStore()) {
        self.disk = disk
        bootstrap()
    }

    var unreadCount: Int { notes.count { $0.meta.resolvedStatus == .unread } }

    /// Projects that have notes, most used first.
    var topics: [String] {
        let counts = Dictionary(grouping: notes.compactMap(\.meta.topic), by: { $0 }).mapValues(\.count)
        return counts.keys.sorted { counts[$0]! != counts[$1]! ? counts[$0]! > counts[$1]! : $0 < $1 }
    }

    var pendingPlans: Int {
        notes.count { $0.style == .plan && $0.meta.review?.resolvedStatus ?? .pending == .pending
            && $0.meta.resolvedStatus != .archived }
    }

    func note(_ id: String) -> Note? { notes.first { $0.id == id } ?? sessionNotes.first { $0.id == id } }

    /// Sessions handed back to a new session and not yet dismissed.
    var pendingSessions: [Note] { sessionNotes.filter { $0.meta.resume?.resolvedStatus == .requested } }

    func unread(in folder: String) -> Int {
        notes.count { $0.folder == folder && $0.meta.resolvedStatus == .unread }
    }

    func config(for note: Note) -> FolderConfig? { folders.first { $0.name == note.folder }?.config }

    // MARK: Loading

    private typealias Loaded = (scan: (folders: [Folder], notes: [Note]), sessions: [Note])

    /// Reads the disk off the main thread, so thousands of notes never freeze the UI.
    /// File events arriving meanwhile coalesce into a single extra pass.
    func reload() {
        guard !reloading else { reloadAgain = true; return }
        reloading = true
        let disk = disk
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result { () throws -> Loaded in (try disk.scan(), Sessions.all(in: disk)) }
            }.value
            // The root may have changed while reading; that load is stale.
            if disk === self.disk { apply(result) }
            reloading = false
            if reloadAgain {
                reloadAgain = false
                reload()
            }
        }
    }

    /// Blocking load, for snapshot runs that render right after creating the store.
    func reloadSynchronously() {
        apply(Result { (try disk.scan(), Sessions.all(in: disk)) })
    }

    private func apply(_ result: Result<Loaded, Error>) {
        switch result {
        case .success(let loaded):
            // Only publish real changes: reassigning identical arrays makes the
            // lists re-diff (and jump) on every file event, including our own writes.
            if loaded.scan.folders != folders { folders = loaded.scan.folders }
            if loaded.scan.notes != notes { notes = loaded.scan.notes }
            if loaded.sessions != sessionNotes { sessionNotes = loaded.sessions }
            notifyPendingSessions()
            didReload?()
        case .failure(let error):
            lastError = error.localizedDescription
        }
    }

    func changeRoot(to url: URL) {
        do {
            try CotsConfig.saveRoot(url)
            disk = NoteStore(root: url)
            bootstrap()
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func bootstrap() {
        do { try disk.ensureRoot() } catch { lastError = error.localizedDescription }
        reload()
        watcher = FileWatcher(url: disk.root) { [weak self] in
            Task { @MainActor in self?.reload() }
        }
    }

    /// Each handed-back session is notified once; the mark lives in the note so it
    /// survives relaunches.
    private func notifyPendingSessions() {
        for note in Sessions.needingNotification(in: disk) {
            Notifier.shared.post(note)
            try? Sessions.markNotified(note.id, in: disk)
        }
    }

    // MARK: Writes

    /// Runs a write and shows its result right away; the background reload that follows
    /// catches everything else (counts, other files the write touched).
    private func perform(_ work: () throws -> Note?) {
        do {
            if let note = try work() { upsert(note) }
        } catch {
            lastError = error.localizedDescription
        }
        reload()
    }

    private func upsert(_ note: Note) {
        if note.folder == Sessions.folder {
            if let i = sessionNotes.firstIndex(where: { $0.id == note.id }) { sessionNotes[i] = note }
            return
        }
        var updated = notes.filter { $0.id != note.id }
        updated.append(note)
        notes = NoteStore.sorted(updated)
    }

    func markRead(_ note: Note) {
        guard note.meta.resolvedStatus == .unread else { return }
        perform { try disk.setStatus(note.id, .read) }
    }

    func setStatus(_ note: Note, _ status: NoteStatus) { perform { try disk.setStatus(note.id, status) } }

    func dismissSession(_ note: Note) { perform { try Sessions.setResume(note.id, .dismissed, in: disk) } }

    /// Keeps the session's last message as a regular note, then dismisses the reminder.
    @discardableResult
    func promoteSession(_ note: Note) -> Note? {
        var draft = NoteDraft(body: note.body)
        draft.title = note.title
        draft.topic = note.meta.topic
        draft.source = note.meta.source
        draft.status = NoteStatus.read.rawValue
        var created: Note?
        perform {
            let kept = try disk.create(draft)
            created = kept
            upsert(kept)
            return try Sessions.setResume(note.id, .dismissed, in: disk)
        }
        return created
    }

    func setReview(_ note: Note, _ status: ReviewStatus, comment: String) {
        perform { try disk.setReview(note.id, status, comment: comment) }
    }

    /// nil = automatic (topic, then folder color).
    func setColor(_ note: Note, _ color: String?) { perform { try disk.setColor(note.id, color) } }

    func togglePin(_ note: Note) { perform { try disk.setPinned(note.id, !note.meta.isPinned) } }
    /// `base` is the body the edit started from; if an agent changed the note meanwhile the
    /// save fails with a message instead of erasing what the agent wrote.
    func saveBody(_ note: Note, _ body: String, base: String) {
        perform { try disk.updateBody(note.id, body: body, expected: base) }
    }

    func trash(_ note: Note) {
        perform {
            try disk.trash(note.id)
            notes.removeAll { $0.id == note.id }
            sessionNotes.removeAll { $0.id == note.id }
            return nil
        }
    }

    /// Edits only that line of the file as it is now, so text an agent added meanwhile stays.
    func toggleTask(_ note: Note, line: Int) {
        perform { try disk.toggleTask(note.id, line: line + 1) }
    }

    @discardableResult
    func create(folder: String, title: String, style: DisplayStyle, topic: String, color: String?, body: String) -> Note? {
        var draft = style == .plan ? NoteDraft.plan(title: title, body: body) : NoteDraft(body: body)
        draft.folder = folder
        draft.title = title
        draft.source = "user"
        draft.status = NoteStatus.read.rawValue
        let topic = topic.trimmingCharacters(in: .whitespaces)
        draft.topic = topic.isEmpty ? nil : topic
        draft.style = style.rawValue
        draft.color = color
        var created: Note?
        perform {
            created = try disk.create(draft)
            return created
        }
        return created
    }

    func createFolder(_ name: String) {
        perform {
            try disk.createFolder(name)
            return nil
        }
    }
}
