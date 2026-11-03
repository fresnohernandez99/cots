@testable import CotsCore
import Yams
import XCTest

final class NoteStoreTests: XCTestCase {
    var root: URL!
    var store: NoteStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = NoteStore(root: root)
        try store.ensureRoot()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testCreateFillsDefaultsAndRoundTrips() throws {
        try store.createFolder("code", config: FolderConfig(defaults: {
            var d = NoteMeta()
            d.display = Display(style: "report", icon: "hammer")
            d.tags = ["code"]
            return d
        }()))
        var node = try Frontmatter.parse("title: Informe\ndisplay: {color: blue}\n")
        Frontmatter.set(Node("claude-code"), at: ["source"], in: &node)
        let note = try store.create(folder: "code", frontmatter: node, body: "## Hola\ncuerpo")

        XCTAssertEqual(note.title, "Informe")
        XCTAssertEqual(note.meta.resolvedStatus, .unread)
        XCTAssertEqual(note.meta.display, Display(style: "report", icon: "hammer", color: "blue"))
        XCTAssertEqual(note.meta.tags, ["code"])
        XCTAssertNotNil(note.meta.createdDate)
        XCTAssertEqual(note.body, "## Hola\ncuerpo\n")
        XCTAssertTrue(note.id.hasPrefix("code/"))
        XCTAssertNotNil(note.id.range(of: #"^code/\d{6}-\d{4}$"#, options: .regularExpression), note.id)
    }

    func testUnknownKeysSurviveEdits() throws {
        let node = try Frontmatter.parse("title: X\nmi_clave: valor\nai:\n  extra: 1\n")
        let note = try store.create(folder: "code-notes", frontmatter: node, body: "b")
        try store.setStatus(note.id, .read)
        try store.setPinned(note.id, true)
        try store.updateBody(note.id, body: "nuevo")

        let text = try String(contentsOf: note.url, encoding: .utf8)
        XCTAssertTrue(text.contains("mi_clave: valor"))
        XCTAssertTrue(text.contains("extra: 1"))
        let reloaded = try store.note(id: note.id)
        XCTAssertEqual(reloaded.meta.resolvedStatus, .read)
        XCTAssertTrue(reloaded.meta.isPinned)
        XCTAssertEqual(reloaded.body, "nuevo\n")
        XCTAssertNotNil(reloaded.meta.updated)
    }

    func testTolerantOfUnknownValuesAndBrokenFrontmatter() throws {
        let url = root.appendingPathComponent("code-notes/rota.md")
        try "---\ntitle: [sin cerrar\n---\ncuerpo".write(to: url, atomically: true, encoding: .utf8)
        let broken = try store.note(id: "code-notes/rota")
        XCTAssertNotNil(broken.parseError)
        XCTAssertEqual(broken.title, "rota")

        let odd = try store.create(folder: "code-notes", frontmatter: Frontmatter.parse("title: Y\ndisplay: {style: futurista}\nstatus: raro"), body: "")
        XCTAssertEqual(odd.style, .document)
        XCTAssertEqual(odd.meta.resolvedStatus, .read)
    }

    func testAppendAndLatest() throws {
        let note = try store.create(folder: "code-notes", frontmatter: Frontmatter.parse("title: Log"), body: "inicio")
        try store.setStatus(note.id, .read)
        let appended = try store.append("code-notes/latest", text: "entrada")
        XCTAssertEqual(appended.id, note.id)
        XCTAssertEqual(appended.meta.resolvedStatus, .unread)
        XCTAssertTrue(appended.body.contains("## "))
        XCTAssertTrue(appended.body.hasSuffix("entrada\n"))
    }

    func testRejectsMissingTitleAndBadFolder() {
        XCTAssertThrowsError(try store.create(folder: "code-notes", body: "x"))
        XCTAssertThrowsError(try store.create(folder: "../fuera", frontmatter: Frontmatter.parse("title: x"), body: ""))
        XCTAssertThrowsError(try store.create(folder: "_oculta", frontmatter: Frontmatter.parse("title: x"), body: ""))
    }

    func testSplitWithoutFrontmatter() {
        let (yaml, body) = Frontmatter.split("solo texto\n---\nmas")
        XCTAssertNil(yaml)
        XCTAssertEqual(body, "solo texto\n---\nmas")
    }

    func testDefaultFoldersAndPlanReview() throws {
        XCTAssertEqual(try store.folders().map(\.name), ["code-notes", "plans"])
        var node = try Frontmatter.parse("title: Plan")
        Frontmatter.set(Node("pending"), at: ["review", "status"], in: &node)
        let plan = try store.create(folder: "plans", frontmatter: node, body: "- [ ] paso")
        XCTAssertEqual(plan.style, .plan)
        XCTAssertEqual(plan.meta.review?.resolvedStatus, .pending)
        let reviewed = try store.setReview(plan.id, .changes, comment: "más tests")
        XCTAssertEqual(reviewed.meta.review?.resolvedStatus, .changes)
        XCTAssertEqual(reviewed.meta.review?.comment, "más tests")
        XCTAssertNotNil(reviewed.meta.review?.at)
    }

    func testSaveCommand() {
        XCTAssertEqual(SaveCommand.parse("guarda en cots"), SaveCommand(folder: nil))
        XCTAssertEqual(SaveCommand.parse("Guárdalo en coTs."), SaveCommand(folder: nil))
        XCTAssertEqual(SaveCommand.parse("guarda esto en cots ideas"), SaveCommand(folder: "ideas"))
        XCTAssertEqual(SaveCommand.parse("save in cots code-notes"), SaveCommand(folder: "code-notes"))
        XCTAssertNil(SaveCommand.parse("guarda un resumen con pendientes en cots"))
        XCTAssertNil(SaveCommand.parse("hagamos un plan en cots"))
    }

    func testTopicAndTitle() throws {
        let repo = root.appendingPathComponent("mi-repo/src")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("mi-repo/.git"), withIntermediateDirectories: true)
        XCTAssertEqual(Topic.detect(cwd: repo.path), "mi-repo")
        XCTAssertEqual(ReplyCache.title(from: "\n## **Informe** final\ncuerpo"), "Informe final")
    }
}
