@testable import CotsCore
import XCTest

/// Ids and writes that come from agents: nothing may leave the notes folder, blow up on
/// write, or erase what another writer just added.
final class SafetyTests: XCTestCase {
    var store: NoteStore!
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = NoteStore(root: dir.appendingPathComponent("notes"))
        try store.ensureRoot()
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func note(_ body: String) throws -> Note {
        var draft = NoteDraft(body: body)
        draft.title = "n"
        return try store.create(draft)
    }

    func testIdsCannotLeaveTheRoot() throws {
        try "---\ntitle: fuera\n---\nsecreto\n".write(to: dir.appendingPathComponent("outside.md"), atomically: true, encoding: .utf8)
        for id in ["../outside", "code-notes/../../outside", ".hidden/x", "code-notes/..\\outside"] {
            XCTAssertThrowsError(try store.note(id: id), id)
            XCTAssertThrowsError(try store.append(id, text: "x"), id)
        }
        XCTAssertThrowsError(try store.notes(in: ".."))
        XCTAssertEqual(try String(contentsOf: dir.appendingPathComponent("outside.md"), encoding: .utf8), "---\ntitle: fuera\n---\nsecreto\n")
    }

    func testAliasBombIsRefused() {
        var yaml = "title: x\na0: &a0 [x,x,x,x,x,x,x,x,x,x]\n"
        for i in 1...7 { yaml += "a\(i): &a\(i) [" + Array(repeating: "*a\(i - 1)", count: 10).joined(separator: ",") + "]\n" }
        XCTAssertThrowsError(try Frontmatter.parse(yaml))
    }

    func testStaleEditIsRefusedAndAppendSurvives() throws {
        let n = try note("uno")
        try store.append(n.id, text: "de un agente")
        XCTAssertThrowsError(try store.updateBody(n.id, body: "uno editado", expected: n.body))
        XCTAssertTrue(try store.note(id: n.id).body.contains("de un agente"))
    }

    func testToggleTaskOnlyTouchesTheCheckbox() throws {
        let n = try note("texto con [ ] corchetes\n- [ ] tarea [ ] con corchetes")
        try store.toggleTask(n.id, line: 1)
        try store.toggleTask(n.id, line: 2)
        XCTAssertEqual(try store.note(id: n.id).body.components(separatedBy: "\n").prefix(2),
                       ["texto con [ ] corchetes", "- [x] tarea [ ] con corchetes"])
    }

    func testCheckByLineIsExact() throws {
        let n = try note("- [ ] test\n- [ ] write tests")
        let (_, checked) = try store.checkTasks(n.id) { line, _ in line == 1 }
        XCTAssertEqual(checked, ["test"])
        XCTAssertEqual(try store.note(id: n.id).openTasks, ["write tests"])
    }

    func testConcurrentCreatesKeepEveryNote() throws {
        let store = self.store!
        DispatchQueue.concurrentPerform(iterations: 12) { i in
            var draft = NoteDraft(body: "\(i)")
            draft.title = "c\(i)"
            _ = try? store.create(draft)
        }
        XCTAssertEqual(try store.notes(in: "code-notes").count, 12)
    }

    func testSessionFileNamesAreSanitized() {
        XCTAssertEqual(FileName.safe("x\\..\\..\\evil:/y"), "x_______evil__y")
    }
}
