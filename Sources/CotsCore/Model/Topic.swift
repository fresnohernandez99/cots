import Foundation

public enum Topic {
    /// Name of the git repository containing `cwd`, else the folder's own name.
    public static func detect(cwd: String) -> String? {
        var url = URL(fileURLWithPath: cwd, isDirectory: true).standardizedFileURL
        let start = url
        while url.path != "/" {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path) { return url.lastPathComponent }
            url.deleteLastPathComponent()
        }
        // Without a repo, only folders inside the user's home count as projects
        // (not /tmp, /usr, ...).
        let home = CotsConfig.home.standardizedFileURL.path
        guard start.path.hasPrefix(home + "/") else { return nil }
        return start.lastPathComponent
    }
}
