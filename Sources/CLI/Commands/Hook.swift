import ArgumentParser
import CotsCore
import Foundation

/// Thin wrappers: read the hook's JSON from stdin, let `ClaudeCodeHooks` decide, print its answer.
struct Hook: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Puntos de entrada para hooks de agentes (los instala la app).",
        subcommands: [ClaudeStop.self, ClaudePrompt.self, ClaudeSessionStart.self, ClaudeSessionEnd.self]
    )

    static func input() -> [String: Any] {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    static var hooks: ClaudeCodeHooks { ClaudeCodeHooks(store: NoteStore()) }

    struct ClaudeStop: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "claude-stop")
        func run() {
            do {
                try Hook.hooks.stop(Hook.input())
            } catch {
                FileHandle.standardError.write(Data("cots: \(error)\n".utf8))
            }
        }
    }

    struct ClaudePrompt: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "claude-prompt")
        func run() throws {
            if let output = Hook.hooks.prompt(Hook.input()) { try printJSON(output) }
        }
    }

    struct ClaudeSessionStart: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "claude-session-start")
        func run() throws {
            if let output = Hook.hooks.sessionStart(Hook.input()) { try printJSON(output) }
        }
    }

    struct ClaudeSessionEnd: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "claude-session-end")
        func run() {
            Hook.hooks.sessionEnd(Hook.input())
        }
    }
}
