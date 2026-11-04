import Foundation

/// What a note's buttons and links may open. Notes are written by agents, so a note
/// could otherwise turn one click into running a program. Both apps apply these rules.
public enum ActionPolicy {
    /// Links and `open_url` actions: web pages and mail only, never `file:` or app schemes.
    public static func isWebURL(_ text: String) -> Bool {
        guard let scheme = URL(string: text.trimmingCharacters(in: .whitespaces))?.scheme?.lowercased() else { return false }
        return ["http", "https", "mailto"].contains(scheme)
    }

    /// Extensions that run something when "opened" on macOS or Windows.
    static let runnableExtensions: Set<String> = [
        "app", "command", "tool", "terminal", "workflow", "action", "pkg", "mpkg", "scpt", "applescript", "jar",
        "exe", "com", "bat", "cmd", "ps1", "psm1", "vbs", "vbe", "js", "jse", "wsf", "wsh", "hta", "lnk", "url",
        "scr", "msi", "msp", "cpl", "reg", "inf", "pif", "appref-ms", "sh", "zsh", "bash", "py", "rb", "pl",
    ]

    /// Why `open_file` refuses this path, or nil when it's a document that's safe to open.
    /// Folders are fine (they open in Finder or Explorer) unless they're app bundles.
    public static func refusalToOpen(_ path: String) -> String? {
        if path.hasPrefix("\\\\") || path.hasPrefix("//") {
            return "No abro rutas de red: \(path)"
        }
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        if runnableExtensions.contains(url.pathExtension.lowercased()) {
            return "Por seguridad, coTs no abre programas ni scripts desde una nota: \(url.lastPathComponent)"
        }
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        if exists, !isDirectory.boolValue, FileManager.default.isExecutableFile(atPath: url.path) {
            return "Por seguridad, coTs no abre archivos ejecutables desde una nota: \(url.lastPathComponent)"
        }
        return nil
    }

    /// Why a `run` command is refused: hidden lines would run without being shown in the
    /// confirmation, so a command must be one visible line.
    public static func refusalToRun(_ command: String) -> String? {
        if command.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
            return "El comando tiene saltos de línea o caracteres de control; cópialo y revísalo en tu terminal."
        }
        if command.count > 500 { return "El comando es demasiado largo para confirmarlo aquí; cópialo a tu terminal." }
        return nil
    }
}
