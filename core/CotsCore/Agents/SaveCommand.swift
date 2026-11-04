import Foundation

/// Parses "guarda en cots [carpeta]" style prompts. Deliberately strict: anything
/// longer ("guarda un resumen con pendientes en cots") goes to the agent instead.
public struct SaveCommand: Equatable, Sendable {
    /// Folder named in the prompt, nil for the default one.
    public var folder: String?

    public static func parse(_ prompt: String) -> SaveCommand? {
        let normalized = prompt
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es"))
            .lowercased()
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".!¡")))
        let pattern = #"^(guarda|guardalo|guardala|guardar|save)( (esto|eso|this|it|el ultimo mensaje|la ultima respuesta|el ultimo informe|lo ultimo|last reply))? (en|in|to) cots( [a-z0-9_-]+)?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)) else {
            return nil
        }
        let range = match.range(at: 5)
        guard range.location != NSNotFound, let r = Range(range, in: normalized) else { return SaveCommand(folder: nil) }
        return SaveCommand(folder: normalized[r].trimmingCharacters(in: .whitespaces))
    }
}
