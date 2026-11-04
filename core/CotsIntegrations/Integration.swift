import CotsCore
import Foundation

/// Something coTs sets up outside its bundle so agents can use it: the CLI on the
/// PATH, the skill, hooks, an MCP entry. Settings and the launch-time setup walk the
/// list, so adding one (Codex, Gemini…) means adding a type here and nothing else.
public protocol Integration: Sendable {
    /// Settings row title, also its localization key.
    var title: String { get }
    /// Where it was installed, shown next to the checkmark.
    var location: String? { get }
    var isInstalled: Bool { get }
    /// Some of it is there (an older version installed less); kept in sync on launch.
    var isPartlyInstalled: Bool { get }
    /// Set up on the first launch without asking. False for apps that may not be there.
    var installsOnFirstLaunch: Bool { get }
    func install() throws
    func remove()
}

public extension Integration {
    var isPartlyInstalled: Bool { isInstalled }
    var installsOnFirstLaunch: Bool { true }
}

/// Where integrations read and write. `current` is the real system; tests pass a
/// temporary home so nothing on the machine is touched.
public struct IntegrationEnvironment: Sendable {
    public var home: URL
    /// The `cots` binary and the skill folder shipped inside coTs.app.
    public var bundledCLI: URL?
    public var bundledSkill: URL?
    /// Where the CLI link may go, preferred first.
    public var binDirectories: [URL]

    public init(home: URL, bundledCLI: URL?, bundledSkill: URL?, binDirectories: [URL]) {
        self.home = home
        self.bundledCLI = bundledCLI
        self.bundledSkill = bundledSkill
        self.binDirectories = binDirectories
    }

    /// `/usr/local/bin` is on every shell's PATH. `COTS_BIN_DIR` confines the link to one
    /// folder, so an isolated test install can't touch the real one.
    public static func current(bundle: Bundle = .main) -> IntegrationEnvironment {
        let home = CotsConfig.home
        let bins: [URL]
        if let dir = ProcessInfo.processInfo.environment["COTS_BIN_DIR"], !dir.isEmpty {
            bins = [URL(fileURLWithPath: dir)]
        } else {
            bins = [URL(fileURLWithPath: "/usr/local/bin"), home.appendingPathComponent(".local/bin")]
        }
        return IntegrationEnvironment(home: home, bundledCLI: bundle.url(forResource: "cots", withExtension: nil),
                                      bundledSkill: bundle.url(forResource: "skill", withExtension: nil), binDirectories: bins)
    }
}

public struct IntegrationError: LocalizedError {
    public let errorDescription: String?
    public init(_ message: String) { errorDescription = message }
}

public enum Integrations {
    /// In the order Settings shows them.
    public static func all(_ env: IntegrationEnvironment) -> [any Integration] {
        [CLIIntegration(env: env), SkillIntegration(env: env), ClaudeCodeHooksIntegration(env: env), ClaudeDesktopIntegration(env: env)]
    }

    /// The first launch installs everything; later launches refresh what's installed, so
    /// it matches this copy of the app (new skill text, CLI and hook paths if the app
    /// moved). Returns the failures, to show in Settings instead of swallowing them.
    public static func setUp(_ integrations: [any Integration], firstLaunch: Bool) -> [String] {
        var errors: [String] = []
        for integration in integrations
        where (firstLaunch && integration.installsOnFirstLaunch) || integration.isPartlyInstalled {
            do { try integration.install() } catch { errors.append("\(integration.title): \(error.localizedDescription)") }
        }
        return errors
    }

    public static func removeAll(_ env: IntegrationEnvironment) {
        for integration in all(env) { integration.remove() }
    }
}

/// Reads a JSON object file, nil when missing. A file that isn't a JSON object throws,
/// so callers never overwrite settings they couldn't parse.
func readJSONObject(_ url: URL, name: String) throws -> [String: Any]? {
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    let data = try Data(contentsOf: url)
    if data.isEmpty { return [:] }
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw IntegrationError("\(name) no es un objeto JSON; no lo toco")
    }
    return object
}

func writeJSONObject(_ object: [String: Any], to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    try data.write(to: url, options: .atomic)
}
