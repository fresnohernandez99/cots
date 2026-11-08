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
    /// Note open in the menu bar popover.
    var popoverSelection: String?
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

    /// Closes the note wherever it's open, and leaves the Sessions view once it's empty.
    /// Done before trashing it, so no view is left on a note that's gone.
    func close(_ id: String, in store: NotesStore) {
        if windowSelection == id { windowSelection = nil }
        if popoverSelection == id { popoverSelection = nil }
        if showSessions, !store.sessionNotes.contains(where: { $0.id != id }) { showSessions = false }
    }

    /// Closes the note and shows the list of its project (all its notes, any folder).
    func returnToProject(of note: Note) {
        if windowSelection == note.id { windowSelection = nil }
        if popoverSelection == note.id { popoverSelection = nil }
        showSessions = false
        search = ""
        selectedFolder = nil
        selectedTopic = note.meta.topic
    }

    /// Drops a folder or topic filter once nothing on disk matches it any more, and closes
    /// notes deleted from outside (an agent, Finder, a newer session note replacing it).
    func prune(against store: NotesStore) {
        if let id = windowSelection, store.note(id) == nil { close(id, in: store) }
        if let id = popoverSelection, store.note(id) == nil { close(id, in: store) }
        if showSessions, store.sessionNotes.isEmpty { showSessions = false }
        if let folder = selectedFolder, !store.folders.contains(where: { $0.name == folder }) { selectedFolder = nil }
        if let topic = selectedTopic, !store.notes.contains(where: { $0.meta.topic == topic }) { selectedTopic = nil }
    }
}
