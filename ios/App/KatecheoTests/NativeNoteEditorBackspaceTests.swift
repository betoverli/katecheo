import XCTest
@testable import Katecheo

/// Backspace parity: empty plain line merges in 1 press; empty bullet + reference keep 2 presses.
@MainActor
final class NativeNoteEditorBackspaceTests: XCTestCase {
    private var editor: NativeNoteEditorView!

    override func setUp() async throws {
        try await super.setUp()
        editor = NativeNoteEditorView(frame: CGRect(x: 0, y: 0, width: 390, height: 720))
        editor.testing_prepare(size: CGSize(width: 390, height: 720))
    }

    override func tearDown() async throws {
        editor = nil
        try await super.tearDown()
    }

    func testEmptyPlainLine_backspaceMergesInOnePress() {
        var note = NativeAPIClient.emptyNote(id: "bs-plain")
        note.title = "Titulo"
        note.body.blocks = [
            NativeAPIClient.LineBlock(
                id: "p1",
                type: "paragraph",
                spans: [.init(type: "text", text: "linha A", marks: nil, bookId: nil, chapter: nil, verseStart: nil, verseEnd: nil, href: nil)],
                speakerId: nil,
                title: nil,
                collapsed: nil,
                checked: nil,
                blocks: nil
            ),
            NativeAPIClient.LineBlock(
                id: "p2",
                type: "paragraph",
                spans: [],
                speakerId: nil,
                title: nil,
                collapsed: nil,
                checked: nil,
                blocks: nil
            ),
        ]
        editor.pushNote(note)
        let storage = editor.testing_textStorage()
        let ns = storage.string as NSString
        // Park caret on the trailing empty body paragraph (ZWSP).
        let lastPara = ns.paragraphRange(for: NSRange(location: max(0, ns.length - 1), length: 0))
        editor.testing_setSelectedRange(NSRange(location: lastPara.location, length: 0))
        XCTAssertTrue(
            editor.testing_paragraphBlockType() == "paragraph",
            "precondition: caret on empty plain paragraph"
        )

        let beforeParas = (storage.string as NSString).components(separatedBy: "\n").count
        editor.testing_deleteBackward()
        let afterStorage = editor.testing_textStorage()
        let after = afterStorage.string
        let afterParas = (after as NSString).components(separatedBy: "\n").count

        XCTAssertLessThan(afterParas, beforeParas, "one Backspace must join/remove the empty plain line")
        XCTAssertTrue(after.contains("linha A"), "previous line content must remain")
        // Empty plain paragraph must be gone after 1 Backspace (no leftover ZWSP-only body line).
        let doc = editor.currentDocument()
        let emptyBodyCount = doc.body.blocks.filter {
            $0.type == "paragraph" && ($0.spans?.isEmpty ?? true)
        }.count
        XCTAssertEqual(emptyBodyCount, 0, "empty plain paragraph must be gone after 1 Backspace")
    }

    func testEmptyBullet_backspaceNeedsTwoPresses() {
        var note = NativeAPIClient.emptyNote(id: "bs-bullet")
        note.title = "Titulo"
        note.body.blocks = [
            NativeAPIClient.LineBlock(
                id: "p1",
                type: "paragraph",
                spans: [.init(type: "text", text: "antes", marks: nil, bookId: nil, chapter: nil, verseStart: nil, verseEnd: nil, href: nil)],
                speakerId: nil,
                title: nil,
                collapsed: nil,
                checked: nil,
                blocks: nil
            ),
            NativeAPIClient.LineBlock(
                id: "b1",
                type: "bullet",
                spans: [],
                speakerId: nil,
                title: nil,
                collapsed: nil,
                checked: nil,
                blocks: nil
            ),
        ]
        editor.pushNote(note)
        let storage = editor.testing_textStorage()
        let ns = storage.string as NSString
        let lastPara = ns.paragraphRange(for: NSRange(location: max(0, ns.length - 1), length: 0))
        // Place caret after the marker / on the ZWSP of the empty bullet.
        editor.testing_setSelectedRange(NSRange(location: NSMaxRange(lastPara) - 1, length: 0))
        XCTAssertEqual(editor.testing_paragraphBlockType(), "bullet")

        // Press 1 → demote (remove bullet marker), line still present as plain empty.
        editor.testing_deleteBackward()
        XCTAssertEqual(
            editor.testing_paragraphBlockType(),
            "paragraph",
            "first Backspace on empty bullet must remove the marker only"
        )
        let afterFirst = editor.currentDocument()
        XCTAssertTrue(
            afterFirst.body.blocks.contains(where: { $0.type == "paragraph" && ($0.spans?.isEmpty ?? true) })
                || editor.testing_textStorage().string.contains("\u{200B}"),
            "empty line must still exist after demote"
        )
        XCTAssertTrue(editor.testing_textStorage().string.contains("antes"))

        // Press 2 → merge with previous line.
        editor.testing_deleteBackward()
        let afterSecond = editor.currentDocument()
        let emptyLeft = afterSecond.body.blocks.filter {
            ($0.type == "paragraph" || $0.type == "bullet") && ($0.spans?.isEmpty ?? true)
        }.count
        XCTAssertEqual(emptyLeft, 0, "second Backspace must remove the empty line")
        XCTAssertTrue(editor.testing_textStorage().string.contains("antes"))
    }

    func testReferencePill_backspaceNeedsTwoPresses() {
        var note = NativeAPIClient.emptyNote(id: "bs-ref")
        note.title = "Titulo"
        note.body.blocks = [
            NativeAPIClient.LineBlock(
                id: "p1",
                type: "paragraph",
                spans: [
                    .init(
                        type: "bibleRef",
                        text: nil,
                        marks: nil,
                        bookId: "JHN",
                        chapter: 3,
                        verseStart: 16,
                        verseEnd: nil,
                        href: nil
                    ),
                ],
                speakerId: nil,
                title: nil,
                collapsed: nil,
                checked: nil,
                blocks: nil
            ),
        ]
        editor.pushNote(note)
        let storage = editor.testing_textStorage()
        var pillRange: NSRange?
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, stop in
            guard value is BibleRefPillAttachment else { return }
            pillRange = range
            stop.pointee = true
        }
        guard let pill = pillRange else {
            return XCTFail("missing bible ref attachment")
        }

        // Caret just after the pill.
        editor.testing_setSelectedRange(NSRange(location: NSMaxRange(pill), length: 0))

        // Press 1 → select (arm) the reference; do not delete yet.
        editor.testing_deleteBackward()
        let selected = editor.testing_selectedRange()
        XCTAssertGreaterThan(selected.length, 0, "first Backspace must select the reference pill")
        XCTAssertEqual(
            NSIntersectionRange(selected, pill).length,
            pill.length,
            "selection must cover the reference attachment"
        )
        XCTAssertNotNil(
            editor.testing_textStorage().attribute(.attachment, at: pill.location, effectiveRange: nil) as? BibleRefPillAttachment,
            "pill must still be present after arming"
        )

        // Press 2 → delete.
        editor.testing_deleteBackward()
        var stillThere = false
        let after = editor.testing_textStorage()
        after.enumerateAttribute(.attachment, in: NSRange(location: 0, length: after.length)) { value, _, stop in
            if value is BibleRefPillAttachment {
                stillThere = true
                stop.pointee = true
            }
        }
        XCTAssertFalse(stillThere, "second Backspace must delete the reference pill")
    }
}
