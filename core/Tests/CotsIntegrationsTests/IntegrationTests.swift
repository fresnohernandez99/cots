@testable import CotsIntegrations
import XCTest

/// Everything runs against a temporary home and a fake coTs.app: the real
/// ~/.claude, Claude Desktop config and /usr/local/bin are never touched.
final class IntegrationTests: XCTestCase {
    var temp: URL!
    var env: IntegrationEnvironment!
    let fm = FileManager.default

    override func setUpWithError() throws {
        temp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let resources = temp.appendingPathComponent("coTs.app/Contents/Resources")
        try fm.createDirectory(at: resources.appendingPathComponent("skill"), withIntermediateDirectories: true)
        try "#!/bin/sh\n".write(to: resources.appendingPathComponent("cots"), atomically: true, encoding: .utf8)
        try "# coTs\n".write(to: resources.appendingPathComponent("skill/SKILL.md"), atomically: true, encoding: .utf8)
        let home = temp.appendingPathComponent("home")
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        env = IntegrationEnvironment(home: home, bundledCLI: resources.appendingPathComponent("cots"),
                                     bundledSkill: resources.appendingPathComponent("skill"),
                                     binDirectories: [temp.appendingPathComponent("missing-bin"), home.appendingPathComponent(".local/bin")])
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: temp)
    }

    private func json(_ path: String) throws -> [String: Any] {
        let data = try Data(contentsOf: env.home.appendingPathComponent(path))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func write(_ text: String, to path: String) throws {
        let url = env.home.appendingPathComponent(path)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    func testCLILinkFallsBackAndNeverClobbers() throws {
        #if os(Windows)
        try XCTSkipIf(true, "The CLI link is a macOS integration; the Windows installer puts cots on the PATH")
        #endif
        // The preferred folder doesn't exist and isn't under home, so it's skipped.
        let cli = CLIIntegration(env: env)
        XCTAssertFalse(cli.isInstalled)
        try cli.install()
        XCTAssertEqual(cli.location, env.home.appendingPathComponent(".local/bin/cots").path)
        try cli.install() // reinstall replaces our own link
        cli.remove()
        XCTAssertFalse(cli.isInstalled)

        try write("someone else's", to: ".local/bin/cots")
        XCTAssertThrowsError(try cli.install())
        XCTAssertEqual(try String(contentsOf: env.home.appendingPathComponent(".local/bin/cots"), encoding: .utf8), "someone else's")
        cli.remove()
        XCTAssertTrue(fm.fileExists(atPath: env.home.appendingPathComponent(".local/bin/cots").path))
    }

    func testSkillGoesToEveryAgent() throws {
        let skill = SkillIntegration(env: env)
        try skill.install()
        for dir in [".claude/skills/cots", ".agents/skills/cots"] {
            XCTAssertTrue(fm.fileExists(atPath: env.home.appendingPathComponent("\(dir)/SKILL.md").path), dir)
        }
        XCTAssertTrue(skill.isInstalled)
        skill.remove()
        XCTAssertFalse(skill.isInstalled)
    }

    func testHooksKeepOtherSettingsAndUpgrade() throws {
        try write("""
        {"model": "opus", "hooks": {"Stop": [{"hooks": [{"type": "command", "command": "afplay done.aiff"}]}],
          "UserPromptSubmit": [{"hooks": [{"type": "command", "command": "\\"/old/coTs.app/Contents/Resources/cots\\" hook claude-prompt"}]}]}}
        """, to: ".claude/settings.json")
        let hooks = ClaudeCodeHooksIntegration(env: env)
        // An older version installed only one hook: partly installed, so launch upgrades it.
        XCTAssertTrue(hooks.isPartlyInstalled)
        XCTAssertFalse(hooks.isInstalled)
        try hooks.install()
        XCTAssertTrue(hooks.isInstalled)

        var settings = try json(".claude/settings.json")
        XCTAssertEqual(settings["model"] as? String, "opus")
        var all = try XCTUnwrap(settings["hooks"] as? [String: [[String: Any]]])
        XCTAssertEqual(all["Stop"]?.count, 2, "the user's own Stop hook stays")
        let prompt = (all["UserPromptSubmit"]?.first?["hooks"] as? [[String: Any]])?.first?["command"] as? String
        XCTAssertEqual(prompt, "\"\(env.bundledCLI!.path)\" hook claude-prompt", "old path replaced, not duplicated")
        XCTAssertEqual(all["UserPromptSubmit"]?.count, 1)

        hooks.remove()
        settings = try json(".claude/settings.json")
        all = try XCTUnwrap(settings["hooks"] as? [String: [[String: Any]]])
        XCTAssertEqual(Array(all.keys), ["Stop"])
        XCTAssertEqual(settings["model"] as? String, "opus")
    }

    /// Where Claude Desktop keeps its config on this platform, relative to the home.
    let desktopConfig = "\(ClaudeDesktopIntegration.supportFolder)/Claude/claude_desktop_config.json"

    func testMalformedSettingsAreNeverOverwritten() throws {
        try write("{ esto no es json", to: ".claude/settings.json")
        XCTAssertThrowsError(try ClaudeCodeHooksIntegration(env: env).install())
        XCTAssertEqual(try String(contentsOf: env.home.appendingPathComponent(".claude/settings.json"), encoding: .utf8), "{ esto no es json")
        try write("[1, 2]", to: desktopConfig)
        XCTAssertThrowsError(try ClaudeDesktopIntegration(env: env).install())
    }

    func testClaudeDesktopOnlyWhenPresent() throws {
        let desktop = ClaudeDesktopIntegration(env: env)
        XCTAssertFalse(desktop.installsOnFirstLaunch)
        XCTAssertTrue(Integrations.setUp([desktop], firstLaunch: true).isEmpty)
        XCTAssertFalse(desktop.isInstalled)

        try write(#"{"mcpServers": {"other": {"command": "x"}}, "theme": "dark"}"#,
                  to: desktopConfig)
        XCTAssertTrue(desktop.installsOnFirstLaunch)
        _ = Integrations.setUp([desktop], firstLaunch: true)
        XCTAssertTrue(desktop.isInstalled)
        let config = try json(desktopConfig)
        let servers = try XCTUnwrap(config["mcpServers"] as? [String: [String: Any]])
        XCTAssertEqual(servers["cots"]?["args"] as? [String], ["mcp"])
        XCTAssertNotNil(servers["other"])
        XCTAssertEqual(config["theme"] as? String, "dark")
        XCTAssertTrue(desktop.manualConfig.contains(commandPath(env.bundledCLI!)))
    }

    func testLaunchSetupInstallsOnceThenOnlyRefreshes() throws {
        XCTAssertEqual(Integrations.setUp(Integrations.all(env), firstLaunch: true), [])
        XCTAssertTrue(CLIIntegration(env: env).isInstalled)
        XCTAssertTrue(SkillIntegration(env: env).isInstalled)
        XCTAssertTrue(ClaudeCodeHooksIntegration(env: env).isInstalled)

        // The user removed the skill: later launches respect that.
        SkillIntegration(env: env).remove()
        _ = Integrations.setUp(Integrations.all(env), firstLaunch: false)
        XCTAssertFalse(SkillIntegration(env: env).isInstalled)
        XCTAssertTrue(CLIIntegration(env: env).isInstalled)

        Integrations.removeAll(env)
        XCTAssertFalse(Integrations.all(env).contains { $0.isInstalled })
    }

    func testMissingBundleIsReported() {
        env.bundledCLI = nil
        let errors = Integrations.setUp([CLIIntegration(env: env), ClaudeCodeHooksIntegration(env: env)], firstLaunch: true)
        XCTAssertEqual(errors.count, 2)
    }

    func testWindowsAppSetupSkipsTheLinkAndRecognizesExeHooks() throws {
        var windows = env!
        windows.binDirectories = []
        XCTAssertFalse(Integrations.all(windows).contains { $0 is CLIIntegration })

        // A hook written by the Windows app (forward slashes, .exe) is still ours.
        let settings = env.home.appendingPathComponent(".claude/settings.json")
        try fm.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        let command = #""C:/Program Files/coTs/cots.exe" hook claude-stop"#
        try #"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"\#(command.replacingOccurrences(of: "\"", with: "\\\""))"}]}]}}"#
            .write(to: settings, atomically: true, encoding: .utf8)
        let hooks = ClaudeCodeHooksIntegration(env: windows)
        XCTAssertTrue(hooks.isPartlyInstalled)
        hooks.remove()
        XCTAssertFalse(hooks.isPartlyInstalled)

        XCTAssertEqual(commandPath(URL(fileURLWithPath: "/C:/Program Files/coTs/cots.exe")), "C:/Program Files/coTs/cots.exe")
    }
}
