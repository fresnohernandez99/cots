import Foundation

/// Parsed notes keyed by path, reused while the file stays the same. Parsing YAML is
/// what makes listing slow; `stat` is cheap, so only changed files are read again.
final class NoteCache: @unchecked Sendable {
    /// What identifies one version of a file: if none of these changed, neither did the note.
    struct Stamp: Equatable {
        var inode: UInt64
        var size: Int64
        var seconds: Int
        var nanoseconds: Int

        /// Read with `stat` rather than `URL.resourceValues`, which caches values per URL
        /// and would miss a write made through the same URL.
        init?(path: String) {
            #if os(Windows)
            // No inodes there; size and modification time (100 ns resolution) are enough.
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
                  let date = attrs[.modificationDate] as? Date else { return nil }
            let time = date.timeIntervalSince1970
            inode = 0
            size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            seconds = Int(time.rounded(.down))
            nanoseconds = Int((time - time.rounded(.down)) * 1_000_000_000)
            #else
            var info = stat()
            guard stat(path, &info) == 0 else { return nil }
            inode = UInt64(info.st_ino)
            size = Int64(info.st_size)
            #if canImport(Darwin)
            seconds = Int(info.st_mtimespec.tv_sec)
            nanoseconds = Int(info.st_mtimespec.tv_nsec)
            #else
            seconds = Int(info.st_mtim.tv_sec)
            nanoseconds = Int(info.st_mtim.tv_nsec)
            #endif
            #endif
        }

        var modified: Date {
            Date(timeIntervalSince1970: TimeInterval(seconds) + TimeInterval(nanoseconds) / 1_000_000_000)
        }
    }

    private var entries: [String: (Stamp, Note)] = [:]
    private let lock = NSLock()

    func note(at path: String, stamp: Stamp) -> Note? {
        lock.withLock {
            guard let (cached, note) = entries[path], cached == stamp else { return nil }
            return note
        }
    }

    func store(_ note: Note, at path: String, stamp: Stamp) {
        lock.withLock { entries[path] = (stamp, note) }
    }

    /// Drops entries whose files are gone, so a long-running app doesn't keep them forever.
    func retain(only paths: Set<String>, under prefix: String) {
        lock.withLock {
            for key in entries.keys where key.hasPrefix(prefix) && !paths.contains(key) { entries[key] = nil }
        }
    }
}
