import Foundation

public enum FileName {
    /// A file name built from outside input (session ids, project names from hooks):
    /// letters, digits, `-` and `_` only, so it can never name a parent directory or
    /// carry a separator on any platform (`/`, `\\`, `:`).
    public static func safe(_ text: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let mapped = String(String.UnicodeScalarView(text.unicodeScalars.map { allowed.contains($0) ? $0 : "_" }))
        return mapped.isEmpty ? "_" : String(mapped.prefix(120))
    }
}
