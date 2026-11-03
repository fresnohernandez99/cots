import AppKit
import CotsCore
import ServiceManagement
import SwiftUI

/// The menu bar popover: filters, search, list, and an inline detail.
struct MenuContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @State private var openNote: String?
    @State private var creating = false

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            if let openNote {
                NoteDetailView(noteID: openNote) { self.openNote = nil }
            } else if creating {
                NewNoteView(initialFolder: model.selectedFolder) { created in
                    creating = false
                    openNote = created?.id
                }
            } else {
                HStack(spacing: 6) {
                    TextField("Buscar", text: $model.search)
                        .textFieldStyle(.roundedBorder)
                    Button { creating = true } label: { Image(systemName: "square.and.pencil") }
                        .help("Nueva nota")
                    Button { activate { openWindow(id: "main") } } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                    }
                    .help("Abrir expandida")
                    Menu {
                        Button("Abrir expandida") { activate { openWindow(id: "main") } }
                        Button("Ajustes…") { activate { openSettings() } }
                        Toggle("Ver archivadas", isOn: $model.showArchived)
                        Divider()
                        Button("Salir de coTs") { NSApp.terminate(nil) }
                    } label: { Image(systemName: "ellipsis.circle") }
                        .menuIndicator(.hidden)
                        .fixedSize()
                }
                .buttonStyle(.borderless)
                .padding(10)
                FilterChips()
                Divider()
                NoteList(selection: Binding(get: { openNote }, set: { openNote = $0 }), showFolder: model.selectedFolder == nil)
            }
            if let error = model.lastError {
                ErrorBanner(message: error) { model.lastError = nil }
            }
        }
        .frame(width: 400, height: 560)
        // Backup registration in case the status label's task hasn't run yet.
        .onAppear {
            StatusMenu.shared.install(model: model, openWindow: { openWindow(id: "main") }, openSettings: { openSettings() })
        }
    }
}

/// LSUIElement apps don't come forward on their own when opening a window.
@MainActor
func activate(_ open: () -> Void) {
    open()
    NSApp.activate(ignoringOtherApps: true)
}

/// Folder chips, plus a second row of topic chips when notes have topics.
struct FilterChips: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip(Text("Todas"), icon: "tray.full", tint: .accentColor, count: model.unreadCount, selected: model.selectedFolder == nil) {
                        model.selectedFolder = nil
                    }
                    ForEach(model.folders) { folder in
                        // Plans show how many wait for a decision, which matters more than unread.
                        chip(Text(verbatim: folder.title), icon: folder.config.icon ?? "folder",
                             tint: Palette.color(folder.config.color) ?? .accentColor,
                             count: folder.name == NoteStore.plansFolder ? model.pendingPlans : model.unread(in: folder.name),
                             selected: model.selectedFolder == folder.name) {
                            model.selectedFolder = folder.name
                        }
                    }
                }
                .padding(.horizontal, 10)
            }
            if !model.topics.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(model.topics, id: \.self) { topic in
                            Button {
                                model.selectedTopic = model.selectedTopic == topic ? nil : topic
                            } label: {
                                TopicChip(topic: topic, selected: model.selectedTopic == topic)
                                    .overlay(Capsule().stroke(Palette.topicColor(topic), lineWidth: model.selectedTopic == topic ? 1 : 0))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10)
                }
            }
        }
        .padding(.bottom, 8)
    }

    private func chip(_ title: Text, icon: String, tint: Color, count: Int, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon).foregroundStyle(tint)
                title
                if count > 0 { Text(verbatim: "\(count)").fontWeight(.bold) }
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(selected ? AnyShapeStyle(tint.opacity(0.25)) : AnyShapeStyle(.quaternary), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct NoteList: View {
    @Environment(AppModel.self) private var model
    @Binding var selection: String?
    var showFolder = true

    var body: some View {
        @Bindable var model = model
        let notes = model.visibleNotes
        let active = notes.filter { !$0.isFinishedPlan }
        let finished = notes.filter(\.isFinishedPlan)
        if notes.isEmpty {
            if model.search.isEmpty {
                ContentUnavailableView("Sin notas", systemImage: "note.text",
                                       description: Text("Pídele a una IA «guarda en cots», o crea una nota."))
                    .frame(maxHeight: .infinity)
            } else {
                ContentUnavailableView.search(text: model.search)
                    .frame(maxHeight: .infinity)
            }
        } else {
            List(selection: $selection) {
                ForEach(active) { row($0) }
                if !finished.isEmpty {
                    Button {
                        withAnimation(.snappy) { model.showFinishedPlans.toggle() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.right")
                                .rotationEffect(.degrees(model.showFinishedPlans ? 90 : 0))
                            Text("Planes terminados")
                            Text(verbatim: "\(finished.count)").foregroundStyle(.tertiary)
                            Spacer()
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 4, trailing: 12))
                    .selectionDisabled()
                    if model.showFinishedPlans {
                        ForEach(finished) { row($0) }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private func row(_ note: Note) -> some View {
        NoteRow(note: note, showFolder: showFolder)
            .tag(note.id)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 10))
            .contextMenu { NoteMenuItems(note: note) }
    }
}

struct ErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(verbatim: message).font(.caption).lineLimit(3)
            Spacer()
            Button(action: dismiss) { Image(systemName: "xmark") }.buttonStyle(.borderless)
        }
        .padding(8)
        .background(.orange.opacity(0.1))
    }
}

struct NewNoteView: View {
    @Environment(AppModel.self) private var model
    let initialFolder: String?
    let done: (Note?) -> Void

    @State private var folder = ""
    @State private var newFolder = ""
    @State private var title = ""
    @State private var topic = ""
    @State private var color: String?
    @State private var style: DisplayStyle = .document
    @State private var text = ""

    var body: some View {
        Form {
            TextField("Título", text: $title)
            Picker("Carpeta", selection: $folder) {
                ForEach(model.folders) { Text(verbatim: $0.title).tag($0.name) }
                Text("Nueva carpeta…").tag("")
            }
            if folder.isEmpty {
                TextField("Nombre de la carpeta", text: $newFolder)
            }
            HStack {
                TextField("Topic (proyecto)", text: $topic)
                if !model.topics.isEmpty {
                    Menu {
                        ForEach(model.topics, id: \.self) { t in Button(t) { topic = t } }
                    } label: { Image(systemName: "chevron.down") }
                        .menuIndicator(.hidden)
                        .fixedSize()
                }
            }
            Picker("Estilo", selection: $style) {
                ForEach(DisplayStyle.allCases, id: \.self) { Label($0.label, systemImage: $0.symbol).tag($0) }
            }
            LabeledContent("Color") {
                HStack(spacing: 5) {
                    swatch(nil)
                    ForEach(Palette.names, id: \.self) { swatch($0) }
                }
            }
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 140)
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button("Cancelar") { done(nil) }
                Spacer()
                Button("Crear") {
                    done(model.create(folder: folder.isEmpty ? newFolder : folder, title: title, style: style,
                                      topic: topic, color: color, body: text))
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.isEmpty || (folder.isEmpty && newFolder.isEmpty))
            }
            .padding(10)
        }
        .onAppear {
            folder = initialFolder ?? model.folders.first?.name ?? ""
            topic = model.selectedTopic ?? ""
        }
    }

    /// nil = automatic (topic or folder color).
    private func swatch(_ name: String?) -> some View {
        Button { color = name } label: {
            Circle()
                .fill(name.flatMap(Palette.color) ?? Color.secondary.opacity(0.25))
                .frame(width: 14, height: 14)
                .overlay { if name == nil { Image(systemName: "wand.and.stars").font(.system(size: 7)) } }
                .overlay(Circle().stroke(Color.primary, lineWidth: color == name ? 2 : 0))
        }
        .buttonStyle(.plain)
        .help(name == nil ? Text("Automático") : Text(verbatim: name!))
    }
}

/// What the expanded window's sidebar can select. One typed selection replaces the
/// previous mix of `String?` tags (which never matched the list's `String` selection,
/// so clicks didn't register) and plain buttons for topics.
enum SidebarItem: Hashable {
    case all, folder(String), topic(String)
}

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: selection) {
            Label("Todas", systemImage: "tray.full")
                .badge(model.unreadCount)
                .tag(SidebarItem.all)
            Section("Carpetas") {
                ForEach(model.folders) { folder in
                    Label { Text(verbatim: folder.title) } icon: {
                        Image(systemName: folder.config.icon ?? "folder")
                            .foregroundStyle(Palette.color(folder.config.color) ?? .accentColor)
                    }
                    .badge(folder.name == NoteStore.plansFolder ? model.pendingPlans : model.unread(in: folder.name))
                    .tag(SidebarItem.folder(folder.name))
                    .help(folder.config.description ?? "")
                }
            }
            if !model.topics.isEmpty {
                Section("Topics") {
                    ForEach(model.topics, id: \.self) { topic in
                        Label { Text(verbatim: topic) } icon: {
                            Image(systemName: "circle.fill").foregroundStyle(Palette.topicColor(topic)).imageScale(.small)
                        }
                        .badge(model.notes.filter { $0.meta.topic == topic && $0.meta.resolvedStatus == .unread }.count)
                        .tag(SidebarItem.topic(topic))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Ver archivadas", isOn: $model.showArchived)
                Toggle("Mostrar planes terminados", isOn: $model.showFinishedPlans)
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
            if let topic = model.selectedTopic { return .topic(topic) }
            if let folder = model.selectedFolder { return .folder(folder) }
            return .all
        } set: { item in
            switch item {
            case .folder(let name):
                model.selectedFolder = name
                model.selectedTopic = nil
            case .topic(let topic):
                model.selectedTopic = topic
                model.selectedFolder = nil
            case .all, nil:
                model.selectedFolder = nil
                model.selectedTopic = nil
            }
        }
    }
}

/// Expanded window: sidebar of folders and topics, list, detail.
struct MainWindowView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView()
        } content: {
            NoteList(selection: $model.windowSelection, showFolder: model.selectedFolder == nil)
                .searchable(text: $model.search)
                .navigationSplitViewColumnWidth(min: 280, ideal: 340)
                .toolbar {
                    Button { model.showingNewNote = true } label: { Label("Nueva nota", systemImage: "square.and.pencil") }
                }
        } detail: {
            if let selection = model.windowSelection {
                NoteDetailView(noteID: selection).id(selection)
            } else {
                ContentUnavailableView("Selecciona una nota", systemImage: "note.text")
            }
        }
        .sheet(isPresented: $model.showingNewNote) {
            NewNoteView(initialFolder: model.selectedFolder) { note in
                model.showingNewNote = false
                model.windowSelection = note?.id
            }
            .frame(width: 480, height: 560)
        }
        .overlay(alignment: .bottom) {
            if let error = model.lastError { ErrorBanner(message: error) { model.lastError = nil } }
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

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var cliLink = Integrations.installedCLI
    @State private var skillInstalled = Integrations.skillInstalled
    @State private var hooksInstalled = Integrations.hooksInstalled
    @State private var integrationErrors = Integrations.lastErrors
    @State private var language = AppLanguage.current
    @State private var confirmingUninstall = false
    @State private var deleteNotes = false

    private var iCloudRoot: URL {
        CotsConfig.home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/coTs", isDirectory: true)
    }

    var body: some View {
        Form {
            Section("Notas") {
                LabeledContent("Carpeta") {
                    Text(verbatim: model.store.root.path).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                }
                HStack {
                    Button("Cambiar…", action: chooseRoot)
                    Button("Usar iCloud Drive") { model.changeRoot(to: iCloudRoot) }
                        .help("Las notas quedan en iCloud Drive/coTs: visibles desde la app Archivos del iPhone.")
                    Button("Mostrar en Finder") { NSWorkspace.shared.open(model.store.root) }
                }
            }
            Section("General") {
                Toggle("Abrir al iniciar sesión", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in setLaunchAtLogin(on) }
                if let loginError { Text(verbatim: loginError).font(.caption).foregroundStyle(.red) }
                Picker("Idioma", selection: $language) {
                    Text("Sistema").tag(AppLanguage.system)
                    Text(verbatim: "Español").tag(AppLanguage.spanish)
                    Text(verbatim: "English").tag(AppLanguage.english)
                }
                .onChange(of: language) { _, value in value.apply() }
                if language != AppLanguage.current {
                    HStack {
                        Text("Reinicia coTs para cambiar el idioma.").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Reiniciar") { AppLanguage.relaunch() }
                    }
                }
            }
            Section {
                integrationRow("CLI `cots`", installed: cliLink != nil, detail: cliLink?.path) {
                    if cliLink == nil { try Integrations.installCLI() } else { Integrations.removeCLI() }
                }
                integrationRow("Skill (Claude Code, Codex, Gemini)", installed: skillInstalled,
                               detail: "~/.claude/skills · ~/.agents/skills") {
                    if skillInstalled { Integrations.removeSkill() } else { try Integrations.installSkill() }
                }
                integrationRow("Guardado directo en Claude Code (hooks)", installed: hooksInstalled,
                               detail: "~/.claude/settings.json") {
                    if hooksInstalled { Integrations.removeHooks() } else { try Integrations.installHooks() }
                }
                ForEach(integrationErrors, id: \.self) { error in
                    Label { Text(verbatim: error) } icon: { Image(systemName: "exclamationmark.triangle.fill") }
                        .font(.caption).foregroundStyle(.red)
                }
            } header: {
                Text("Integración con IAs")
            } footer: {
                Text("«guarda en cots [carpeta]» guarda la última respuesta sin pasar por la IA (0 tokens). «hagamos un plan en cots» crea un plan que revisas aquí.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Desinstalar") {
                HStack {
                    Text("Quita la app, el CLI, la skill, los hooks, el inicio automático, preferencias y cachés.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Desinstalar coTs…", role: .destructive) { confirmingUninstall = true }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 600, height: 640)
        .sheet(isPresented: $confirmingUninstall) { uninstallSheet }
    }

    private func integrationRow(_ title: LocalizedStringKey, installed: Bool, detail: String?,
                                toggle: @escaping () throws -> Void) -> some View {
        LabeledContent(title) {
            HStack {
                if installed {
                    Label { Text(verbatim: detail ?? "") } icon: { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                        .foregroundStyle(.secondary)
                } else {
                    Text("No instalado").foregroundStyle(.secondary)
                }
                Button(installed ? "Quitar" : "Instalar") { integration(toggle) }
            }
            .font(.caption)
        }
    }

    private var uninstallSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("¿Desinstalar coTs?", systemImage: "trash").font(.headline)
            Text("Se eliminarán la app (a la Papelera), el CLI, la skill, los hooks, el inicio automático, las preferencias y las cachés. La app se cerrará.")
                .fixedSize(horizontal: false, vertical: true)
            Toggle(isOn: $deleteNotes) {
                VStack(alignment: .leading) {
                    Text("Borrar también mis notas")
                    Text(verbatim: model.store.root.path).font(.caption).foregroundStyle(.secondary)
                }
            }
            if deleteNotes {
                Text("La carpeta de notas irá a la Papelera; podrás recuperarla desde ahí.")
                    .font(.caption).foregroundStyle(.orange)
            } else {
                Text("Tus notas se quedan donde están; si reinstalas, vuelve a elegir esa carpeta en Ajustes.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancelar") { confirmingUninstall = false }.keyboardShortcut(.cancelAction)
                Button("Desinstalar", role: .destructive) {
                    Uninstaller.run(deleteNotes: deleteNotes, notesRoot: model.store.root)
                }
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private func integration(_ work: () throws -> Void) {
        do {
            try work()
            integrationErrors = []
        } catch {
            integrationErrors = [error.localizedDescription]
        }
        cliLink = Integrations.installedCLI
        skillInstalled = Integrations.skillInstalled
        hooksInstalled = Integrations.hooksInstalled
    }

    private func chooseRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = model.store.root
        if panel.runModal() == .OK, let url = panel.url { model.changeRoot(to: url) }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

/// Per-app language override via `AppleLanguages`; takes effect on relaunch.
enum AppLanguage: String, Hashable {
    case system, spanish = "es", english = "en"

    static var current: AppLanguage {
        guard let langs = UserDefaults.standard.persistentDomain(forName: Uninstaller.bundleID)?["AppleLanguages"] as? [String],
              let first = langs.first else { return .system }
        return first.hasPrefix("es") ? .spanish : first.hasPrefix("en") ? .english : .system
    }

    func apply() {
        if self == .system {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([rawValue], forKey: "AppleLanguages")
        }
    }

    @MainActor
    static func relaunch() {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
