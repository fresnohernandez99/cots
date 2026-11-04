import Foundation

public enum CotsError: LocalizedError, Equatable {
    case invalidFrontmatter(String)
    case invalidFolderName(String)
    case noteNotFound(String)
    case folderNotFound(String)
    case invalidArgument(String)

    public var errorDescription: String? {
        switch self {
        case .invalidFrontmatter(let m): return "Frontmatter inválido: \(m)"
        case .invalidFolderName(let n): return "Nombre de carpeta inválido: '\(n)' (usa letras, números, - y _)"
        case .noteNotFound(let id): return "No existe la nota '\(id)'"
        case .folderNotFound(let n): return "No existe la carpeta '\(n)'"
        case .invalidArgument(let m): return m
        }
    }
}
