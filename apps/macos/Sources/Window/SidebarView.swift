import CotsCore
import SwiftUI

/// What the expanded window's sidebar can select. One typed selection replaces the
/// previous mix of `String?` tags (which never matched the list's `String` selection,
/// so clicks didn't register) and plain buttons for topics.
enum SidebarItem: Hashable {
    case all, folder(String), topic(String), sessions
}

struct SidebarView: View {
    @Environment(NotesStore.self) private var store
    @Environment(Browser.self) private var browser

    var body: some View {
        @Bindable var browser = browser
        List(selection: selection) {
            Label("Todas", systemImage: "tray.full")
                .badge(store.unreadCount)
                .tag(SidebarItem.all)
            Section("Carpetas") {
                ForEach(store.folders) { folder in
                    Label { Text(verbatim: folder.title) } icon: {
                        Image(systemName: folder.config.icon ?? "folder")
                            .foregroundStyle(Palette.color(folder.config.color) ?? .accentColor)
                    }
                    .badge(folder.name == NoteStore.plansFolder ? store.pendingPlans : store.unread(in: folder.name))
                    .tag(SidebarItem.folder(folder.name))
                    .help(folder.config.description ?? "")
                }
            }
            Section("Sistema") {
                Label("Sesiones", systemImage: "clock.arrow.circlepath")
                    .badge(store.pendingSessions.count)
                    .tag(SidebarItem.sessions)
                    .help("Último mensaje de cada sesión de IA, por proyecto")
            }
            if !store.topics.isEmpty {
                Section("Topics") {
                    ForEach(store.topics, id: \.self) { topic in
                        Label { Text(verbatim: topic) } icon: {
                            Image(systemName: "circle.fill").foregroundStyle(Palette.topicColor(topic)).imageScale(.small)
                        }
                        .badge(store.notes.filter { $0.meta.topic == topic && $0.meta.resolvedStatus == .unread }.count)
                        .tag(SidebarItem.topic(topic))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Ver archivadas", isOn: $browser.showArchived)
                Toggle("Mostrar planes terminados", isOn: $browser.showFinishedPlans)
            }
            .toggleStyle(.checkbox)
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
        }
    }

    /// Folder and topic filters are exclusive in the sidebar; the popover can still combine them.
    private var selection: Binding<SidebarItem?> {
        Binding {
            if browser.showSessions { return .sessions }
            if let topic = browser.selectedTopic { return .topic(topic) }
            if let folder = browser.selectedFolder { return .folder(folder) }
            return .all
        } set: { item in
            browser.showSessions = item == .sessions
            switch item {
            case .folder(let name):
                browser.selectedFolder = name
                browser.selectedTopic = nil
            case .topic(let topic):
                browser.selectedTopic = topic
                browser.selectedFolder = nil
            case .all, .sessions, nil:
                browser.selectedFolder = nil
                browser.selectedTopic = nil
            }
        }
    }
}
