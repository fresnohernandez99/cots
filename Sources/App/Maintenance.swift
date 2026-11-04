import AppKit
import CotsCore
import CotsIntegrations
import Foundation
import ServiceManagement

/// The CLI, the agent skill and the agent hooks ship inside the bundle. Dragging the
/// app from the DMG doesn't run any installer, so the app sets them up itself.
@MainActor
enum LaunchSetup {
    private static let firstLaunchKey = "didInstallIntegrations"

    /// Failures from the last automatic setup, shown in Settings instead of being swallowed.
    static var lastErrors: [String] = []

    static func run() {
        guard Bundle.main.isInstalledCopy else { return }
        let first = !UserDefaults.standard.bool(forKey: firstLaunchKey)
        lastErrors = Integrations.setUp(Integrations.all(.current()), firstLaunch: first)
        UserDefaults.standard.set(true, forKey: firstLaunchKey)
    }
}

/// Removes everything the app put on the system. Notes are only removed on request,
/// and go to the Trash rather than being deleted.
enum Uninstaller {
    private static let fm = FileManager.default

    static var bundleID: String { Bundle.main.bundleIdentifier ?? CotsConfig.bundleID }

    /// Files macOS or the app create outside the bundle, for the current and the legacy identifier.
    static var residues: [URL] {
        [bundleID, CotsConfig.legacyBundleID].flatMap(residues(for:))
            + [CotsConfig.home.appendingPathComponent(".config/cots")]
    }

    static func residues(for id: String) -> [URL] {
        let lib = CotsConfig.home.appendingPathComponent("Library")
        return [
            lib.appendingPathComponent("Preferences/\(id).plist"),
            lib.appendingPathComponent("Caches/\(id)"),
            lib.appendingPathComponent("HTTPStorages/\(id)"),
            lib.appendingPathComponent("HTTPStorages/\(id).binarycookies"),
            lib.appendingPathComponent("Saved Application State/\(id).savedState"),
            lib.appendingPathComponent("Application Support/\(id)"),
            lib.appendingPathComponent("WebKit/\(id)"),
        ]
    }

    /// Removes what versions before 0.4.1 left under the old identifier.
    static func cleanUpLegacy() {
        let legacy = CotsConfig.legacyBundleID
        guard UserDefaults.standard.persistentDomain(forName: legacy) != nil
                || residues(for: legacy).contains(where: { fm.fileExists(atPath: $0.path) }) else { return }
        UserDefaults.standard.removePersistentDomain(forName: legacy)
        for url in residues(for: legacy) { try? fm.removeItem(at: url) }
    }

    /// Never returns: the app quits, and a detached shell removes the residues the
    /// system may still rewrite while we're running (preferences, saved state).
    static func run(deleteNotes: Bool, notesRoot: URL) -> Never {
        try? SMAppService.mainApp.unregister()
        Integrations.removeAll(.current())
        if deleteNotes { try? fm.trashItem(at: notesRoot, resultingItemURL: nil) }
        UserDefaults.standard.removePersistentDomain(forName: bundleID)
        UserDefaults.standard.synchronize()

        let paths = residues.map { "'" + $0.path.replacingOccurrences(of: "'", with: "'\\''") + "'" }.joined(separator: " ")
        let cleanup = Process()
        cleanup.executableURL = URL(fileURLWithPath: "/bin/sh")
        cleanup.arguments = ["-c", "while kill -0 \(getpid()) 2>/dev/null; do sleep 0.2; done; rm -rf \(paths); defaults delete \(bundleID) 2>/dev/null; true"]
        try? cleanup.run()
        cleanUpLegacy()

        if Bundle.main.isInstalledCopy {
            try? fm.trashItem(at: Bundle.main.bundleURL, resultingItemURL: nil)
        }
        exit(0)
    }
}

extension Bundle {
    /// Running from /Applications or ~/Applications, as opposed to a dev build.
    var isInstalledCopy: Bool {
        let path = bundlePath
        let userApps = CotsConfig.home.appendingPathComponent("Applications").path
        return path.hasSuffix(".app") && (path.hasPrefix("/Applications/") || path.hasPrefix(userApps + "/"))
    }
}
