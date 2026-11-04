import AppKit
import CotsCore
import SwiftUI

/// Menu bar menus, visible while the expanded window makes coTs a regular app.
/// They act on the note selected in that window.
struct CotsCommands: Commands {
    let store: NotesStore
    let browser: Browser

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Nueva nota") { browser.showingNewNote = true }
                .keyboardShortcut("n")
        }

        CommandMenu("Nota") {
            let note = browser.selectedNote(in: store)
            Button(note?.meta.resolvedStatus == .unread ? "Marcar como leída" : "Marcar como no leída") {
                if let note { store.setStatus(note, note.meta.resolvedStatus == .unread ? .read : .unread) }
            }
            .keyboardShortcut("u", modifiers: [.command, .shift])
            .disabled(note == nil)
            Button(note?.meta.isPinned == true ? "Desfijar" : "Fijar") {
                if let note { store.togglePin(note) }
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .disabled(note == nil)
            Menu("Color") {
                if let note { ColorMenuItems(note: note).environment(store).environment(browser) }
            }
            .disabled(note == nil)
            Divider()
            Button("Copiar id para IAs") { if let note { Clipboard.copy(note.id) } }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(note == nil)
            Button("Mostrar en Finder") { if let note { NSWorkspace.shared.activateFileViewerSelecting([note.url]) } }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(note == nil)
            Divider()
            Button(note?.meta.resolvedStatus == .archived ? "Desarchivar" : "Archivar") {
                if let note { store.setStatus(note, note.meta.resolvedStatus == .archived ? .read : .archived) }
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])
            .disabled(note == nil)
            Button("Mover a la papelera") { if let note { store.trash(note) } }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(note == nil)
        }

        CommandGroup(before: .toolbar) {
            Button("Todas las carpetas") { browser.selectedFolder = nil }
                .keyboardShortcut("0")
            ForEach(Array(store.folders.prefix(9).enumerated()), id: \.element.id) { index, folder in
                Button(folder.title) { browser.selectedFolder = folder.name }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
            }
            Divider()
            Toggle("Ver archivadas", isOn: Binding(get: { browser.showArchived }, set: { browser.showArchived = $0 }))
                .keyboardShortcut("h", modifiers: [.command, .shift])
            Toggle("Mostrar planes terminados", isOn: Binding(get: { browser.showFinishedPlans }, set: { browser.showFinishedPlans = $0 }))
            Divider()
        }
    }
}
