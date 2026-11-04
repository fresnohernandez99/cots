import Foundation

public enum Topic {
    /// Name of the git repository containing `cwd`, else the folder's own name.
    public static func detect(cwd: String) -> String? {
        var url = URL(fileURLWithPath: CotsConfig.nativePath(cwd), isDirectory: true).standardizedFileURL
        let start = url
        while true {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path) { return url.lastPathComponent }
            let parent = url.deletingLastPathComponent().standardizedFileURL
            if parent.path == url.path || url.pathComponents.count <= 1 { break } // "/" or "C:\"
            url = parent
        }
        // Without a repo, only folders inside the user's home count as projects
        // (not /tmp, /usr, ...).
        // Components, not strings: on Windows paths use `\` and drive letters vary in case.
        let home = CotsConfig.home.standardizedFileURL.pathComponents.map { $0.lowercased() }
        let here = start.pathComponents.map { $0.lowercased() }
        guard here.count > home.count, Array(here.prefix(home.count)) == home else { return nil }
        return start.lastPathComponent
    }
}
