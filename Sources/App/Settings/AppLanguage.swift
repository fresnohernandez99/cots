import AppKit
import CotsCore

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
