import Foundation

/// Serializes writes to one notes folder across processes: the app, the CLI run by
/// several agents at once, the hooks. Without it two notes created in the same minute
/// got the same file name, and two edits of one note dropped one of them.
///
/// The lock is a directory: creating one is atomic on every file system and platform.
/// A lock older than `stale` belongs to a process that died, and is broken.
struct WriteLock {
    let url: URL
    var timeout: TimeInterval = 10
    var stale: TimeInterval = 15

    init(root: URL) {
        url = root.appendingPathComponent(".cots.lock", isDirectory: true)
    }

    func run<T>(_ body: () throws -> T) throws -> T {
        try acquire()
        defer { try? FileManager.default.removeItem(at: url) }
        return try body()
    }

    private func acquire() throws {
        let fm = FileManager.default
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            do {
                try fm.createDirectory(at: url, withIntermediateDirectories: false)
                return
            } catch {
                // A missing root is a real error. Otherwise the lock is taken (or was
                // released between the two calls): wait and try again.
                guard fm.fileExists(atPath: url.deletingLastPathComponent().path) else { throw error }
                if let created = (try? fm.attributesOfItem(atPath: url.path))?[.creationDate] as? Date,
                   Date().timeIntervalSince(created) > stale {
                    try? fm.removeItem(at: url)
                    continue
                }
                guard Date() < deadline else {
                    throw CotsError.invalidArgument("Otra escritura de coTs no termina (\(url.path)); inténtalo de nuevo")
                }
                Thread.sleep(forTimeInterval: 0.01)
            }
        }
    }
}
