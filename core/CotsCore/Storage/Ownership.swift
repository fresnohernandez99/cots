import Foundation

/// Agents sometimes run as root (e.g. Claude Code under sudo) with `HOME` pointing at
/// the user's home. Files they create must still belong to the user, or the app,
/// running as the user, can't edit them later.
public enum Ownership {
    public static func matchHome(_ urls: URL...) {
        #if !os(Windows)
        guard geteuid() == 0,
              let attrs = try? FileManager.default.attributesOfItem(atPath: CotsConfig.home.path),
              let uid = (attrs[.ownerAccountID] as? NSNumber)?.uint32Value, uid != 0,
              let gid = (attrs[.groupOwnerAccountID] as? NSNumber)?.uint32Value else { return }
        for url in urls { chown(url.path, uid, gid) }
        #endif
    }
}
