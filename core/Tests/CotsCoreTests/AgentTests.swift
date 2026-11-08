@testable import CotsCore
import Yams
import XCTest

final class AgentTests: XCTestCase {
    var temp: URL!
    var store: NoteStore!
    var hooks: ClaudeCodeHooks!
    var repo: String!

    override func setUpWithError() throws {
        temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = NoteStore(root: temp.appendingPathComponent("notes"))
        try store.ensureRoot()
        hooks = ClaudeCodeHooks(store: store, replies: ReplyCache(directory: temp.appendingPathComponent("replies")))
        let repoURL = temp.appendingPathComponent("shop-api")
        try FileManager.default.createDirectory(at: repoURL.appendingPathComponent(".git"), withIntermediateDirectories: true)
        repo = repoURL.path
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temp)
    }

    func testDraftWritesWhatEveryCreatorExpects() throws {
        var draft = NoteDraft(folder: "ideas", body: "cuerpo")
        draft.base = try Frontmatter.parse("title: Base\nmia: 1\nai: {next: [a], context: viejo}\nactions: [{type: copy, text: x}]")
        draft.title = "Nueva"
        draft.tags = ["a", "b"]
        draft.style = "checklist"
        draft.pinned = true
        draft.ai = try Frontmatter.parse("context: nuevo")
        try draft.addAction(NoteAction(type: "reveal", path: "~/x"))
        let note = try store.create(draft)

        XCTAssertEqual(note.title, "Nueva")
        XCTAssertEqual(note.meta.tags, ["a", "b"])
        XCTAssertEqual(note.style, .checklist)
        XCTAssertTrue(note.meta.isPinned)
        XCTAssertEqual(note.meta.ai?.context, "nuevo")
        XCTAssertEqual(note.meta.ai?.next, ["a"])
        XCTAssertEqual(note.meta.actions?.map(\.type), ["copy", "reveal"])
        XCTAssertNil(note.meta.review)
        XCTAssertTrue(try String(contentsOf: note.url, encoding: .utf8).contains("mia: 1"))

        let plan = try store.create(NoteDraft.plan(title: "Plan", body: "- [ ] paso"))
        XCTAssertEqual(plan.folder, NoteStore.plansFolder)
        XCTAssertEqual(plan.style, .plan)
        XCTAssertEqual(plan.meta.review?.resolvedStatus, .pending)
    }

    func testStopCachesReplyAndMirrorsSession() throws {
        try hooks.stop(["session_id": "s1", "cwd": repo!, "last_assistant_message": "## Migración a medias\n\nPaso 2 de 3"])
        XCTAssertEqual(hooks.replies.reply(session: "s1", agent: "claude-code")?.text, "## Migración a medias\n\nPaso 2 de 3")
        XCTAssertEqual(hooks.replies.latest(cwd: repo)?.session, "s1")
        let sessions = Sessions.all(in: store)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.title, "Migración a medias")
        XCTAssertEqual(sessions.first?.meta.topic, "shop-api")
        XCTAssertEqual(sessions.first?.meta.resume?.resolvedStatus, .open)
        // Nothing to cache without a reply.
        try hooks.stop(["session_id": "s2", "cwd": repo!])
        XCTAssertNil(hooks.replies.reply(session: "s2", agent: "claude-code"))
    }

    func testRepliesWithoutDetailAreCachedButNotHandedOver() throws {
        try hooks.stop(["session_id": "s1", "cwd": repo!, "last_assistant_message": "## Diseño\n\n| a | b |\n|---|---|"])
        // A wrap-up line doesn't replace the detailed reply in the session note…
        try hooks.stop(["session_id": "s1", "cwd": repo!, "last_assistant_message": "Listo: 40 tests pasan y 3 features ya están en prod."])
        XCTAssertEqual(Sessions.all(in: store).first?.title, "Diseño")
        // …but stays cached, so "guarda en cots" still saves it.
        XCTAssertEqual(hooks.replies.reply(session: "s1", agent: "claude-code")?.text.hasPrefix("Listo"), true)
        // A session that never said anything detailed leaves no note to hand over.
        try hooks.stop(["session_id": "s2", "cwd": repo!, "last_assistant_message": "Hecho.\n\n- tests ok\n- desplegado"])
        XCTAssertEqual(Sessions.all(in: store).count, 1)

        XCTAssertTrue(Sessions.isWorthKeeping("Así queda:\n\n```swift\nlet x = 1\n```"))
        XCTAssertTrue(Sessions.isWorthKeeping(String(repeating: "Explicación larga. ", count: 100)))
        XCTAssertFalse(Sessions.isWorthKeeping("Terminé la revisión de QA; corregí lo grave."))
    }

    func testPromptSavesLastReplyWithoutReachingTheModel() throws {
        try hooks.stop(["session_id": "s1", "cwd": repo!, "last_assistant_message": "# Informe final\n\ntodo listo"])
        XCTAssertNil(hooks.prompt(["session_id": "s1", "cwd": repo!, "prompt": "guarda un resumen en cots"]))

        let output = try XCTUnwrap(hooks.prompt(["session_id": "s1", "cwd": repo!, "prompt": "Guarda en cots ideas."]))
        XCTAssertEqual(output["decision"] as? String, "block")
        let reason = try XCTUnwrap(output["reason"] as? String)
        XCTAssertTrue(reason.hasPrefix("✓ coTs → ideas/"), reason)
        let note = try XCTUnwrap(try store.notes(in: "ideas").first)
        XCTAssertEqual(note.title, "Informe final")
        XCTAssertEqual(note.meta.source, "claude-code")
        XCTAssertEqual(note.meta.topic, "shop-api")
        XCTAssertEqual(note.meta.ai?.session, "s1")
        XCTAssertEqual(note.meta.ai?.cwd, repo)
        XCTAssertEqual(note.body, "# Informe final\n\ntodo listo\n")
    }

    func testNewSessionGetsThePreviousOneOnce() throws {
        try hooks.stop(["session_id": "old", "cwd": repo!, "last_assistant_message": "## A medias\n\nFalta el paso 3"])
        hooks.sessionEnd(["session_id": "old", "reason": "exit"])
        XCTAssertNotNil(Sessions.all(in: store).first?.meta.session?.ended)
        // Resumed sessions carry their own context.
        XCTAssertNil(hooks.sessionStart(["session_id": "new", "cwd": repo!, "source": "resume"]))

        let output = try XCTUnwrap(hooks.sessionStart(["session_id": "new", "cwd": repo!, "source": "startup"]))
        let context = (output["hookSpecificOutput"] as? [String: Any])?["additionalContext"] as? String
        XCTAssertTrue(context?.contains("se cerró") == true, context ?? "")
        XCTAssertEqual(Sessions.needingNotification(in: store).count, 1)
        XCTAssertNil(hooks.sessionStart(["session_id": "newer", "cwd": repo!]))
    }

    func testHandedOverNoteIsReplacedByTheNextOne() throws {
        try hooks.stop(["session_id": "old", "cwd": repo!, "last_assistant_message": "## A medias\n\nFalta el paso 3"])
        _ = hooks.sessionStart(["session_id": "new", "cwd": repo!])
        // A reply without detail doesn't replace it yet.
        try hooks.stop(["session_id": "new", "cwd": repo!, "last_assistant_message": "listo"])
        XCTAssertEqual(Sessions.all(in: store).map { $0.meta.session?.id }, ["old"])

        try hooks.stop(["session_id": "new", "cwd": repo!, "last_assistant_message": "## Paso 3\n\nHecho"])
        XCTAssertEqual(Sessions.all(in: store).map { $0.meta.session?.id }, ["new"])
    }

    func testHandedOverNoteGoesAtTheNextStartIfNothingReplacedIt() throws {
        try hooks.stop(["session_id": "old", "cwd": repo!, "last_assistant_message": "## A medias\n\nFalta el paso 3"])
        _ = hooks.sessionStart(["session_id": "new", "cwd": repo!])
        XCTAssertEqual(Sessions.all(in: store).count, 1)
        XCTAssertNil(hooks.sessionStart(["session_id": "newer", "cwd": repo!]))
        XCTAssertTrue(Sessions.all(in: store).isEmpty)
    }
}

final class PendingTests: XCTestCase {
    func testOpenTasksSkipCheckedAndCode() throws {
        let store = NoteStore(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        try store.ensureRoot()
        let body = "- [ ] uno\n  * [ ] dos anidada\n- [x] hecha\n```\n- [ ] ejemplo\n```\n+ [ ] tres"
        var draft = NoteDraft(body: body)
        draft.title = "Tareas"
        let note = try store.create(draft)
        XCTAssertEqual(note.openTasks, ["uno", "dos anidada", "tres"])

        let (checked, ticked) = note.checkingTasks { $0.contains("dos") }
        XCTAssertEqual(ticked, ["dos anidada"])
        XCTAssertEqual(checked, note.body.replacingOccurrences(of: "* [ ] dos", with: "* [x] dos"))
    }

    func testPlansAwaitReviewUntilDecided() throws {
        let store = NoteStore(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        try store.ensureRoot()
        var draft = NoteDraft.plan(title: "P", body: "x")
        draft.topic = "Shop-API"
        let plan = try store.create(draft)
        XCTAssertTrue(plan.awaitsReview)
        XCTAssertTrue(plan.belongs(toTopic: "shop-api"))
        XCTAssertFalse(try store.setReview(plan.id, .approved, comment: nil).awaitsReview)
    }
}
