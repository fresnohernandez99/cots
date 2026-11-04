import AppKit
import CotsCore
import CotsIntegrations
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Environment(NotesStore.self) private var store
    @Environment(Browser.self) private var browser
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    private let integrations = Integrations.all(.current())
    /// Bumped after every install or removal, so the rows read their status from disk again.
    @State private var revision = 0
    @State private var copiedMCPConfig = false
    @State private var integrationErrors = LaunchSetup.lastErrors
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
                    Text(verbatim: (store.disk.root.path as NSString).abbreviatingWithTildeInPath)
                        .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                }
                HStack {
                    Button("Cambiar…", action: chooseRoot)
                    Button("Usar iCloud Drive") { changeRoot(to: iCloudRoot) }
                        .help("Las notas quedan en iCloud Drive/coTs: visibles desde la app Archivos del iPhone.")
                    Button("Mostrar en Finder") { NSWorkspace.shared.open(store.disk.root) }
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
                ForEach(integrations.indices, id: \.self) { i in integrationRow(integrations[i]).id("\(revision)-\(i)") }
                LabeledContent("ChatGPT y otros clientes MCP") {
                    Button(copiedMCPConfig ? "Copiado" : "Copiar configuración") {
                        Clipboard.copy(ClaudeDesktopIntegration(env: .current()).manualConfig)
                        copiedMCPConfig = true
                    }
                    .font(.caption)
                }
                .help("En ChatGPT: Ajustes → Plugins → añadir servidor MCP local, con este comando y el argumento mcp.")
                ForEach(integrationErrors, id: \.self) { error in
                    Label { Text(verbatim: error) } icon: { Image(systemName: "exclamationmark.triangle.fill") }
                        .font(.caption).foregroundStyle(.red)
                }
            } header: {
                Text("Integración con IAs")
            } footer: {
                Text("«guarda en cots [carpeta]» guarda la última respuesta sin pasar por la IA (0 tokens). «hagamos un plan en cots» crea un plan que revisas aquí. Claude Desktop y ChatGPT usan coTs por MCP; reinícialos tras instalarlo.")
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
        .frame(width: 600, height: 700)
        .sheet(isPresented: $confirmingUninstall) { uninstallSheet }
    }

    private func integrationRow(_ integration: any Integration) -> some View {
        LabeledContent(LocalizedStringKey(integration.title)) {
            HStack {
                if integration.isInstalled {
                    Label { Text(verbatim: integration.location ?? "") } icon: {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                    .foregroundStyle(.secondary)
                } else {
                    Text("No instalado").foregroundStyle(.secondary)
                }
                Button(integration.isInstalled ? "Quitar" : "Instalar") { toggle(integration) }
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
                    Text(verbatim: store.disk.root.path).font(.caption).foregroundStyle(.secondary)
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
                    Uninstaller.run(deleteNotes: deleteNotes, notesRoot: store.disk.root)
                }
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private func toggle(_ integration: any Integration) {
        do {
            if integration.isInstalled { integration.remove() } else { try integration.install() }
            integrationErrors = []
        } catch {
            integrationErrors = [error.localizedDescription]
        }
        revision += 1
    }

    private func changeRoot(to url: URL) {
        store.changeRoot(to: url)
        browser.selectedFolder = nil
    }

    private func chooseRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = store.disk.root
        if panel.runModal() == .OK, let url = panel.url { changeRoot(to: url) }
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
