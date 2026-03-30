import XCTest
@testable import TanukiBell

final class SystemNoteParserTests: XCTestCase {

    private func makeNote(
        id: Int,
        body: String,
        authorName: String = "Alice",
        system: Bool = true
    ) -> RESTNote {
        let now = Date()
        return RESTNote(
            id: id,
            body: body,
            author: RESTUser(id: 1, name: authorName, username: authorName.lowercased()),
            createdAt: now,
            updatedAt: now,
            system: system
        )
    }

    // MARK: - Changes-requested detection

    func testExactMatchDetected() {
        let notes = [makeNote(id: 1, body: "requested changes")]
        let result = SystemNoteParser.changesRequestedAuthors(in: notes, after: nil)
        XCTAssertEqual(result, ["Alice"])
    }

    func testLongerBodyContainingPhraseDetected() {
        let notes = [makeNote(id: 1, body: "requested changes on this merge request")]
        let result = SystemNoteParser.changesRequestedAuthors(in: notes, after: nil)
        XCTAssertEqual(result, ["Alice"])
    }

    func testCaseInsensitiveMatch() {
        let notes = [makeNote(id: 1, body: "Requested Changes")]
        let result = SystemNoteParser.changesRequestedAuthors(in: notes, after: nil)
        XCTAssertEqual(result, ["Alice"])
    }

    func testNonMatchingSystemNoteIgnored() {
        let notes = [makeNote(id: 1, body: "approved this merge request")]
        let result = SystemNoteParser.changesRequestedAuthors(in: notes, after: nil)
        XCTAssertTrue(result.isEmpty)
    }

    func testNonSystemNoteIgnored() {
        let notes = [makeNote(id: 1, body: "requested changes", system: false)]
        let result = SystemNoteParser.changesRequestedAuthors(in: notes, after: nil)
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - lastNoteID watermark

    func testNoteAtOrBelowWatermarkSkipped() {
        let notes = [
            makeNote(id: 5, body: "requested changes", authorName: "Bob"),
            makeNote(id: 3, body: "requested changes", authorName: "Alice"),
        ]
        let result = SystemNoteParser.changesRequestedAuthors(in: notes, after: 4)
        XCTAssertEqual(result, ["Bob"])
        XCTAssertFalse(result.contains("Alice"))
    }

    func testNilWatermarkIncludesAllNotes() {
        let notes = [
            makeNote(id: 2, body: "requested changes", authorName: "Bob"),
            makeNote(id: 1, body: "requested changes", authorName: "Alice"),
        ]
        let result = SystemNoteParser.changesRequestedAuthors(in: notes, after: nil)
        XCTAssertEqual(result.count, 2)
    }

    func testEmptyNotesReturnsEmpty() {
        let result = SystemNoteParser.changesRequestedAuthors(in: [], after: nil)
        XCTAssertTrue(result.isEmpty)
    }

    func testMultipleMatchingNotesReturnsAllAuthors() {
        let notes = [
            makeNote(id: 2, body: "requested changes", authorName: "Bob"),
            makeNote(id: 1, body: "requested changes", authorName: "Alice"),
        ]
        let result = SystemNoteParser.changesRequestedAuthors(in: notes, after: nil)
        XCTAssertTrue(result.contains("Bob"))
        XCTAssertTrue(result.contains("Alice"))
    }
}
