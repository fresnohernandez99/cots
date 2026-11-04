import CotsCore
import Foundation
import Observation

/// What the user is looking at: filters, search and selection, shared by the popover,
/// the expanded window, the menu bar menu and the app's commands.
@MainActor
@Observable
final class Browser {
    var selectedFolder: String?
    var selectedTopic: String?
    /// The expanded window's "Sesiones" view.
    var showSessions = false
    /// Note shown in the expanded window; the popover sets it before opening the window.
    var windowSelection: String?
    var search = ""
    var showArchived = false
    var showFinishedPlans = false
    /// Set by the menu bar command; the expanded window shows the new-note sheet.
    var showingNewNote = false

    func visibleNotes(in store: NotesStore) -> [Note] {
        let q = search.trimmingCharacters(in: .whitespaces)
        let matcher = TextMatcher(q)
        if showSessions {
            return store.sessionNotes.filter { q.isEmpty || matcher.matches($0.title) || matcher.matches($0.body) }
        }
        return store.notes.filter { note in
            (selectedFolder == nil || note.folder == selectedFolder)
                && (selectedTopic == nil || note.meta.topic == selectedTopic)
                && (showArchived ? note.meta.resolvedStatus == .archived : note.meta.resolvedStatus != .archived)
                && (q.isEmpty || note.matches(matcher) || matcher.matches(note.meta.topic ?? ""))
        }
    }

    func selectedNote(in store: NotesStore) -> Note? { windowSelection.flatMap(store.note) }

    /// Drops a folder or topic filter once nothing on disk matches it any more.
    func prune(against store: NotesStore) {
        if let folder = selectedFolder, !store.folders.contains(where: { $0.name == folder }) { selectedFolder = nil }
        if let topic = selectedTopic, !store.notes.contains(where: { $0.meta.topic == topic }) { selectedTopic = nil }
    }
}
