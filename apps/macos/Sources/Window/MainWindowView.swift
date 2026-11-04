import AppKit
import CotsCore
import SwiftUI

/// Expanded window: sidebar of folders and topics, list, detail.
struct MainWindowView: View {
    @Environment(NotesStore.self) private var store
    @Environment(Browser.self) private var browser

    var body: some View {
        @Bindable var browser = browser
        NavigationSplitView {
            SidebarView()
        } content: {
            NoteList(selection: $browser.windowSelection, showFolder: browser.selectedFolder == nil && !browser.showSessions)
                .searchable(text: $browser.search)
                .navigationSplitViewColumnWidth(min: 280, ideal: 340)
                .toolbar {
                    Button { browser.showingNewNote = true } label: { Label("Nueva nota", systemImage: "square.and.pencil") }
                }
        } detail: {
            if let selection = browser.windowSelection {
                NoteDetailView(noteID: selection).id(selection)
            } else {
                ContentUnavailableView("Selecciona una nota", systemImage: "note.text")
            }
        }
        .sheet(isPresented: $browser.showingNewNote) {
            NewNoteView(initialFolder: browser.selectedFolder) { note in
                browser.showingNewNote = false
                browser.windowSelection = note?.id
            }
            .frame(width: 480, height: 560)
        }
        .overlay(alignment: .bottom) {
            if let error = store.lastError { ErrorBanner(message: error) { store.lastError = nil } }
        }
        .frame(minWidth: 860, minHeight: 520)
        // While expanded, behave like a regular app: Dock icon and the app's menus in
        // the menu bar. Back to menu-bar-only when the window closes.
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
        .onDisappear { NSApp.setActivationPolicy(.accessory) }
    }
}
