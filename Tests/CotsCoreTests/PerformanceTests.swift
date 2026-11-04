@testable import CotsCore
import XCTest

final class PerformanceTests: XCTestCase {
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

    /// Notes written straight to disk, as fast as possible, shaped like real ones (~2 KB).
    private func writeNotes(_ count: Int) throws {
        let body = String(repeating: "Lorem ipsum dolor sit amet, consectetur adipiscing elit. ", count: 30)
        for i in 0..<count {
            let folder = i % 5 == 0 ? NoteStore.plansFolder : NoteStore.defaultFolder
            let created = String(format: "2026-%02d-%02dT%02d:%02d:00-05:00", 1 + i % 12, 1 + i % 28, i % 24, i % 60)
            let text = """
            ---
            title: Nota \(i)
            summary: Resumen \(i)
            created: '\(created)'
            status: \(i % 3 == 0 ? "unread" : "read")
            topic: proj\(i % 7)
            tags: [a, b]
            display:
              style: report
            ---

            ## Resumen
            \(body)

            """
            try text.write(to: root.appendingPathComponent("\(folder)/n\(i).md"), atomically: false, encoding: .utf8)
        }
    }

    private func seconds(_ work: () throws -> Void) rethrows -> TimeInterval {
        let start = Date()
        try work()
        return Date().timeIntervalSince(start)
    }

    /// The goal of the 0.6 rewrite: 2,000 notes listed in under 0.3 s (it took 8 s for
    /// 1,500). Debug builds are several times slower, so they get a looser bound.
    func testListingTwoThousandNotes() throws {
        try writeNotes(2000)
        #if DEBUG
        let limit = 3.0
        #else
        let limit = 0.3
        #endif
        let cold = try seconds { XCTAssertEqual(try store.notes().count, 2000) }
        XCTAssertLessThan(cold, limit, "cold list")
        let warm = try seconds { _ = try store.notes() }
        XCTAssertLessThan(warm, limit / 3, "warm list")
        let search = try seconds { XCTAssertEqual(try store.search("NOTA 1999").count, 1) }
        XCTAssertLessThan(search, limit / 3, "search")
        let folders = try seconds { _ = try store.folders() }
        XCTAssertLessThan(folders, limit / 3, "folders")
    }

    func testCacheSeesEveryWrite() throws {
        let note = try store.create(folder: "code-notes", frontmatter: Frontmatter.parse("title: A"), body: "uno")
        XCTAssertEqual(try store.notes().first?.body, "uno\n")
        // Same size, same second: only the content differs.
        try store.updateBody(note.id, body: "dos")
        XCTAssertEqual(try store.notes().first?.body, "dos\n")
        try store.setStatus(note.id, .read)
        XCTAssertEqual(try store.notes().first?.meta.resolvedStatus, .read)
        // Edited by someone else, through a different URL instance.
        let text = try String(contentsOf: note.url, encoding: .utf8).replacingOccurrences(of: "title: A", with: "title: B")
        try text.write(to: URL(fileURLWithPath: note.url.path), atomically: true, encoding: .utf8)
        XCTAssertEqual(try store.notes().first?.title, "B")
        try FileManager.default.removeItem(at: note.url)
        XCTAssertTrue(try store.notes().isEmpty)
    }

    func testFastTimestampMatchesFormatter() throws {
        for s in ["2026-11-02T14:30:00-05:00", "2026-02-28T23:59:59+05:30", "2024-02-29T00:00:00Z", "1999-12-31T12:00:00-00:00"] {
            let formatter = ISO8601DateFormatter()
            XCTAssertEqual(Timestamp.fastParse(s), formatter.date(from: s), s)
        }
        for s in ["2026-11-02 14:30", "2026-11-02", "2026-13-02T14:30:00Z", "nada"] {
            XCTAssertNil(Timestamp.fastParse(s), s)
        }
        XCTAssertNotNil(Timestamp.parse("2026-11-02 14:30"))
        XCTAssertEqual(Timestamp.parse(Timestamp.now()).map { Int($0.timeIntervalSince1970) }, Int(Date().timeIntervalSince1970))
    }

    func testSplitEdgeCases() {
        XCTAssertEqual(Frontmatter.split("---\ntitle: X\n---\n\ncuerpo").yaml, "title: X")
        XCTAssertEqual(Frontmatter.split("---\ntitle: X\n---\n\ncuerpo").body, "cuerpo")
        XCTAssertEqual(Frontmatter.split("---\r\ntitle: X\r\n---\r\nb").body, "b")
        XCTAssertEqual(Frontmatter.split("---\n---\nb").yaml, "")
        XCTAssertEqual(Frontmatter.split("---\ntitle: X\n...\nb").yaml, "title: X")
        XCTAssertEqual(Frontmatter.split("---\ntitle: X\n---").body, "")
        XCTAssertNil(Frontmatter.split("---\ntitle: X\nsin cierre").yaml)
        XCTAssertNil(Frontmatter.split("sin frontmatter").yaml)
        XCTAssertEqual(Frontmatter.split("---\ntítulo: ñandú\n---\n— fin").body, "— fin")
    }

    func testMatcher() {
        XCTAssertTrue(TextMatcher("jwt").matches("Migré a JWT"))
        XCTAssertTrue(TextMatcher("MIGRÉ").matches("migré a jwt"))
        XCTAssertTrue(TextMatcher("").matches("x"))
        XCTAssertFalse(TextMatcher("jwtx").matches("jwt"))
        XCTAssertTrue(TextMatcher("é a").matches("Migré a"))
    }
}
