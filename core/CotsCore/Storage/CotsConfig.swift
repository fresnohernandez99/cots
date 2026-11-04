import Foundation

public enum CotsConfig {
    /// Must match CFBundleIdentifier in scripts/build-app.sh; the CLI uses it for cache paths.
    public static let bundleID = "com.fresnohernandez.cots"
    /// Identifier used before 0.4.1; its leftovers are cleaned up on launch and on uninstall.
    public static let legacyBundleID = "com.neomambi.cots"

    /// `$HOME` when set (so tests and sandboxes can redirect everything), else the account's home.
    public static var home: URL {
        if let env = ProcessInfo.processInfo.environment["HOME"], !env.isEmpty {
            return URL(fileURLWithPath: env, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    /// Per-user caches: `~/Library/Caches/<bundle id>` on macOS, `%LOCALAPPDATA%\coTs`
    /// on Windows, `$XDG_CACHE_HOME/cots` (or `~/.cache/cots`) elsewhere.
    public static var cacheDirectory: URL {
        #if os(macOS)
        return home.appendingPathComponent("Library/Caches/\(bundleID)", isDirectory: true)
        #else
        let env = ProcessInfo.processInfo.environment
        #if os(Windows)
        if let local = env["LOCALAPPDATA"], !local.isEmpty {
            return URL(fileURLWithPath: local, isDirectory: true).appendingPathComponent("coTs", isDirectory: true)
        }
        #endif
        if let xdg = env["XDG_CACHE_HOME"], !xdg.isEmpty {
            return URL(fileURLWithPath: xdg, isDirectory: true).appendingPathComponent("cots", isDirectory: true)
        }
        return home.appendingPathComponent(".cache/cots", isDirectory: true)
        #endif
    }

    public static var configURL: URL { home.appendingPathComponent(".config/cots/config.json") }

    public static var defaultRoot: URL { home.appendingPathComponent("coTs", isDirectory: true) }

    /// `COTS_HOME` > `~/.config/cots/config.json` > `~/coTs`.
    /// The app and the CLI share this so both always look at the same folder.
    public static func resolveRoot() -> URL {
        if let env = ProcessInfo.processInfo.environment["COTS_HOME"], !env.isEmpty {
            return URL(fileURLWithPath: (env as NSString).expandingTildeInPath, isDirectory: true)
        }
        if let data = try? Data(contentsOf: configURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let root = json["root"] as? String, !root.isEmpty {
            return URL(fileURLWithPath: (root as NSString).expandingTildeInPath, isDirectory: true)
        }
        return defaultRoot
    }

    public static func saveRoot(_ url: URL) throws {
        let dir = configURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: ["root": url.path], options: [.prettyPrinted])
        try data.write(to: configURL, options: .atomic)
    }
}
