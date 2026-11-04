import Foundation

/// A `cots` symlink on the PATH pointing at the CLI inside the bundle.
public struct CLIIntegration: Integration {
    public let env: IntegrationEnvironment
    public init(env: IntegrationEnvironment) { self.env = env }

    public var title: String { "CLI `cots`" }
    public var location: String? { installedLink?.path }
    public var isInstalled: Bool { installedLink != nil }

    var links: [URL] { env.binDirectories.map { $0.appendingPathComponent("cots") } }

    public var installedLink: URL? { links.first(where: isOurLink) }

    /// Only links that point into a coTs.app are ours to replace or remove.
    func isOurLink(_ url: URL) -> Bool {
        guard let dest = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path) else { return false }
        return dest.hasSuffix("coTs.app/Contents/Resources/cots")
    }

    public func install() throws {
        guard let source = env.bundledCLI else { throw IntegrationError("El bundle no incluye el CLI") }
        let fm = FileManager.default
        for link in links {
            let dir = link.deletingLastPathComponent()
            if dir.path.hasPrefix(env.home.path) { try? fm.createDirectory(at: dir, withIntermediateDirectories: true) }
            guard fm.isWritableFile(atPath: dir.path) else { continue }
            if isOurLink(link) {
                try fm.removeItem(at: link)
            } else if (try? fm.attributesOfItem(atPath: link.path)) != nil {
                continue // Someone else's `cots`; don't clobber it.
            }
            try fm.createSymbolicLink(at: link, withDestinationURL: source)
            return
        }
        throw IntegrationError("No hay permiso de escritura en \(env.binDirectories.map(\.path).joined(separator: " ni en "))")
    }

    public func remove() {
        for link in links where isOurLink(link) { try? FileManager.default.removeItem(at: link) }
    }
}
