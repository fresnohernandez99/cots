import AppKit
import CotsCore
import SwiftUI

/// The menu bar popover: filters, search, list, and an inline detail.
struct MenuContentView: View {
    @Environment(NotesStore.self) private var store
    @Environment(Browser.self) private var browser
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @State private var openNote: String?
    @State private var creating = false

    var body: some View {
        @Bindable var browser = browser
        VStack(spacing: 0) {
            if let openNote {
                NoteDetailView(noteID: openNote) { self.openNote = nil }
            } else if creating {
                NewNoteView(initialFolder: browser.selectedFolder) { created in
                    creating = false
                    openNote = created?.id
                }
            } else {
                HStack(spacing: 6) {
                    TextField("Buscar", text: $browser.search)
                        .textFieldStyle(.roundedBorder)
                    Button { creating = true } label: { Label("Nueva nota", systemImage: "square.and.pencil").labelStyle(.iconOnly) }
                        .help("Nueva nota")
                    Button { activate { openWindow(id: "main") } } label: {
                        Label("Abrir expandida", systemImage: "arrow.up.left.and.arrow.down.right").labelStyle(.iconOnly)
                    }
                    .help("Abrir expandida")
                    Menu {
                        Button("Abrir expandida") { activate { openWindow(id: "main") } }
                        Button("Ajustes…") { activate { openSettings() } }
                        Toggle("Ver archivadas", isOn: $browser.showArchived)
                        Divider()
                        Button("Salir de coTs") { NSApp.terminate(nil) }
                    } label: { Label("Más", systemImage: "ellipsis.circle").labelStyle(.iconOnly) }
                        .menuIndicator(.hidden)
                        .fixedSize()
                }
                .buttonStyle(.borderless)
                .padding(10)
                FilterChips()
                if let pending = store.pendingSessions.first {
                    Button { openNote = pending.id } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "clock.arrow.circlepath").foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Pendiente en \(pending.meta.topic ?? "")").font(.caption.weight(.semibold))
                                Text(verbatim: pending.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        .padding(8)
                        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                }
                Divider()
                NoteList(selection: Binding(get: { openNote }, set: { openNote = $0 }), showFolder: browser.selectedFolder == nil)
            }
            if let error = store.lastError {
                ErrorBanner(message: error) { store.lastError = nil }
            }
        }
        .frame(width: 400, height: 560)
        // Backup registration in case the status label's task hasn't run yet.
        .onAppear {
            StatusMenu.shared.install(store: store, browser: browser, openWindow: { openWindow(id: "main") }, openSettings: { openSettings() })
        }
    }
}

/// LSUIElement apps don't come forward on their own when opening a window.
@MainActor
func activate(_ open: () -> Void) {
    open()
    NSApp.activate(ignoringOtherApps: true)
}
