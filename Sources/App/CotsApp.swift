import AppKit
import CotsCore
import ServiceManagement
import SwiftUI

@main
struct CotsApp: App {
    @State private var model = AppModel()

    init() {
        if CommandLine.arguments.contains("--unregister-login-item") {
            try? SMAppService.mainApp.unregister()
            UserDefaults.standard.removeObject(forKey: Self.loginItemKey)
            exit(0)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
            Snapshots.run(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
        }
        if CommandLine.arguments.contains("--uninstall") {
            Uninstaller.run(deleteNotes: CommandLine.arguments.contains("--delete-notes"),
                            notesRoot: CotsConfig.resolveRoot())
        }
        // A second copy (e.g. a stale login item from the old identifier) just quits.
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id)
               .contains(where: { $0.processIdentifier != getpid() }) {
            exit(0)
        }
        Self.registerLoginItemOnFirstLaunch()
        LaunchSetup.run()
        Uninstaller.cleanUpLegacy()
        Notifier.shared.setUp()
    }

    private static let loginItemKey = "didRegisterLoginItem"

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environment(model)
        } label: {
            StatusLabel()
                .environment(model)
        }
        .menuBarExtraStyle(.window)

        Window("coTs", id: "main") {
            MainWindowView()
                .environment(model)
        }
        .defaultSize(width: 1000, height: 640)
        .commands { CotsCommands(model: model) }

        Settings {
            SettingsView()
                .environment(model)
        }
    }

    /// The app is meant to always be in the menu bar, so opt in to launch-at-login
    /// once; after that the toggle in Settings is the source of truth. Only from an
    /// installed copy, so dev builds don't leave login items pointing at build/.
    private static func registerLoginItemOnFirstLaunch() {
        guard Bundle.main.isInstalledCopy, !UserDefaults.standard.bool(forKey: loginItemKey) else { return }
        if (try? SMAppService.mainApp.register()) != nil {
            UserDefaults.standard.set(true, forKey: loginItemKey)
        }
    }
}
