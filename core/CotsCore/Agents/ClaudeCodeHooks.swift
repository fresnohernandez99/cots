import Foundation

/// What each Claude Code hook does with the JSON it receives on stdin. The CLI's
/// `cots hook claude-*` commands only read stdin and print what these return, so the
/// behavior is testable without a running agent.
public struct ClaudeCodeHooks {
    public static let agent = "claude-code"

    public let store: NoteStore
    public let replies: ReplyCache

    public init(store: NoteStore, replies: ReplyCache = .standard) {
        self.store = store
        self.replies = replies
    }

    /// `Stop`: caches the final reply so saving it later costs nothing, and mirrors it
    /// into the project's hidden session note so it survives a crash or shutdown.
    public func stop(_ input: [String: Any]) throws {
        guard let session = input["session_id"] as? String,
              let text = input["last_assistant_message"] as? String, !text.isEmpty else { return }
        let cwd = input["cwd"] as? String
        let reply = CachedReply(agent: Self.agent, session: session, cwd: cwd, text: text)
        try replies.store(reply)
        if let topic = cwd.flatMap(Topic.detect) {
            try store.ensureRoot()
            try Sessions.record(reply, topic: topic, in: store)
        }
    }

    /// `UserPromptSubmit`: "guarda en cots [carpeta]" saves the cached last reply and
    /// blocks the prompt, so it never reaches the model. nil lets anything else through.
    public func prompt(_ input: [String: Any]) -> [String: Any]? {
        guard let prompt = input["prompt"] as? String, let command = SaveCommand.parse(prompt),
              let session = input["session_id"] as? String,
              let reply = replies.reply(session: session, agent: Self.agent) else { return nil }
        let cwd = input["cwd"] as? String
        let message: String
        do {
            var draft = NoteDraft(folder: command.folder ?? NoteStore.defaultFolder, body: reply.text)
            draft.title = ReplyCache.title(from: reply.text)
            draft.source = Self.agent
            draft.topic = cwd.flatMap(Topic.detect)
            var ai = AIContext()
            ai.agent = Self.agent
            ai.session = session
            ai.cwd = cwd
            ai.branch = cwd.flatMap(Git.branch)
            try draft.setAI(ai)
            try store.ensureRoot()
            message = "✓ coTs → \(try store.create(draft).id)"
        } catch {
            message = "✗ coTs: \(error.localizedDescription)"
        }
        return ["decision": "block", "reason": message,
                "hookSpecificOutput": ["hookEventName": "UserPromptSubmit", "suppressOriginalPrompt": true]]
    }

    /// `SessionStart`: if the previous session in this project left a last message,
    /// flags it for the app's notification and tells the new session in a few lines.
    public func sessionStart(_ input: [String: Any]) -> [String: Any]? {
        // Resumed/cleared/compacted sessions already carry their own context.
        guard (input["source"] as? String ?? "startup") == "startup",
              let session = input["session_id"] as? String,
              let topic = (input["cwd"] as? String).flatMap(Topic.detect),
              let pending = try? Sessions.takePending(topic: topic, excluding: session, in: store) else { return nil }
        return ["hookSpecificOutput": ["hookEventName": "SessionStart",
                                       "additionalContext": Sessions.startupContext(for: pending)]]
    }

    /// `SessionEnd`: records a normal close (absent after a crash or shutdown).
    public func sessionEnd(_ input: [String: Any]) {
        guard let session = input["session_id"] as? String else { return }
        Sessions.end(session: session, reason: input["reason"] as? String, in: store)
    }
}

public enum Executable {
    /// First `name` on the PATH (`name.exe` on Windows), like a shell would run it.
    public static func find(_ name: String) -> URL? {
        let env = ProcessInfo.processInfo.environment
        #if os(Windows)
        let separator: Character = ";"
        let file = name.hasSuffix(".exe") ? name : name + ".exe"
        let path = env["Path"] ?? env["PATH"] ?? ""
        #else
        let separator: Character = ":"
        let file = name
        let path = env["PATH"] ?? "/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin"
        #endif
        return path.split(separator: separator).lazy
            .map { URL(fileURLWithPath: String($0), isDirectory: true).appendingPathComponent(file) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}

public enum Git {
    /// Current branch of the repository containing `cwd`, nil outside a repo.
    public static func branch(_ cwd: String) -> String? {
        guard let git = Executable.find("git") else { return nil }
        let p = Process()
        p.executableURL = git
        p.arguments = ["-C", cwd, "rev-parse", "--abbrev-ref", "HEAD"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        p.waitUntilExit()
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return p.terminationStatus == 0 && !out.isEmpty ? out : nil
    }
}
