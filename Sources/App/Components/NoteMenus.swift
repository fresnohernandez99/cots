import AppKit
import CotsCore
import SwiftUI

/// Color choices for a note; shared by the detail toolbar, the row context menu and the menu bar.
struct ColorMenuItems: View {
    @Environment(NotesStore.self) private var store
    let note: Note

    var body: some View {
        let current = note.meta.display?.color
        Button { store.setColor(note, nil) } label: {
            Label("Automático", systemImage: current == nil ? "checkmark" : "wand.and.stars")
        }
        Divider()
        ForEach(Palette.names, id: \.self) { name in
            Button { store.setColor(note, name) } label: {
                Label { Text(Palette.label(name)) + Text(current == name ? "  ✓" : "") } icon: { Palette.swatch(Palette.color(name)!) }
            }
        }
    }
}

/// Everything you can do to a note; used as the row context menu and the detail "More" menu.
struct NoteMenuItems: View {
    @Environment(NotesStore.self) private var store
    let note: Note

    var body: some View {
        if note.meta.resolvedStatus == .unread {
            Button("Marcar como leída") { store.setStatus(note, .read) }
        } else if note.meta.resolvedStatus == .read {
            Button("Marcar como no leída") { store.setStatus(note, .unread) }
        }
        Button(note.meta.isPinned ? "Desfijar" : "Fijar") { store.togglePin(note) }
        Menu("Color") { ColorMenuItems(note: note) }
        Divider()
        Button("Copiar id para IAs") { Clipboard.copy(note.id) }
        Button("Copiar contenido") { Clipboard.copy(note.body) }
        Button("Mostrar en Finder") { NSWorkspace.shared.activateFileViewerSelecting([note.url]) }
        Button("Abrir en editor externo") { NSWorkspace.shared.open(note.url) }
        Divider()
        if note.meta.resolvedStatus == .archived {
            Button("Desarchivar") { store.setStatus(note, .read) }
        } else {
            Button("Archivar") { store.setStatus(note, .archived) }
        }
        Button("Mover a la papelera", role: .destructive) { store.trash(note) }
    }
}

enum Clipboard {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
