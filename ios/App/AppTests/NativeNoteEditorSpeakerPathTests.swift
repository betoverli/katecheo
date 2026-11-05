import XCTest
@testable import App

/// Drives `NativeNoteEditorView`'s real `shouldChangeTextIn` path (what PR #60 never tested).
/// Does **not** create a key window — AppTests host inside the app and a second UIWindow hangs CI.
@MainActor
final class NativeNoteEditorSpeakerPathTests: XCTestCase {
    private var editor: NativeNoteEditorView!
    private let speakers = [
        NativeAPIClient.SpeakerDTO(
            id: "sp1",
            name: "Beto",
            color: "#C4A574",
            updatedAt: "2026-01-01T00:00:00Z"
        ),
    ]

    override func setUp() async throws {
        try await super.setUp()
        editor = NativeNoteEditorView(frame: .zero)
        editor.testing_prepare()
        var note = NativeAPIClient.emptyNote(id: "note-speaker-path")
        note.title = "Reunião"
        editor.pushNote(note, speakers: speakers)

        let storage = editor.testing_textStorage()
        editor.testing_setSelectedRange(NSRange(location: storage.length, length: 0))

        // Accessory toolbar, `/` → Speaker, and `@` menu all call this.
        editor.insertSpeakerSection(speakerId: "sp1", name: "Beto")
        XCTAssertEqual(
            editor.testing_paragraphBlockType(),
            "speakerSection",
            "caret should sit on speaker name after insert"
        )
    }

    override func tearDown() async throws {
        editor = nil
        try await super.tearDown()
    }

    func testToolbarSlashAtAllCallSameInsertSpeakerSection() {
        let storage = editor.testing_textStorage()
        var found = false
        storage.enumerateAttribute(
            NoteDocumentCodec.blockTypeKey,
            in: NSRange(location: 0, length: storage.length)
        ) { value, _, stop in
            if (value as? String) == "speakerSection" {
                found = true
                stop.pointee = true
            }
        }
        XCTAssertTrue(found)
    }

    func testRealReturnOnNameThenType_landsInSectionBodyAndRail() {
        // Edit the name (previously demoted typingAttributes to paragraph mid-header).
        editor.testing_insertText(" X")
        XCTAssertEqual(editor.testing_paragraphBlockType(), "speakerSection")

        editor.testing_insertText("\n")
        let caret = editor.testing_selectedRange().location
        XCTAssertGreaterThan(caret, 0)
        let bodyAttrs = editor.testing_textStorage().attributes(
            at: caret - 1,
            effectiveRange: nil
        )
        XCTAssertTrue(
            NoteDocumentCodec.isSpeakerBody(bodyAttrs),
            "After Return on the name line, caret must be in a speaker-body run"
        )

        editor.testing_insertText("corpo dentro")
        let doc = editor.currentDocument()
        XCTAssertEqual(doc.body.blocks.count, 1, "body text must not escape as a sibling block; got \(doc.body.blocks.map(\.type))")
        XCTAssertEqual(doc.body.blocks[0].type, "speakerSection")
        XCTAssertEqual(doc.body.blocks[0].blocks?.count, 1)
        let bodyText = doc.body.blocks[0].blocks?.first?.spans?.map { $0.text ?? "" }.joined() ?? ""
        XCTAssertTrue(bodyText.contains("corpo dentro"), "got \(bodyText)")

        let rails = editor.testing_railCharacterRanges()
        XCTAssertFalse(rails.isEmpty, "rail must be drawn")
        let bodyLoc = max(0, editor.testing_selectedRange().location - 1)
        let covered = rails.contains {
            NSLocationInRange(bodyLoc, $0)
                || NSIntersectionRange($0, NSRange(location: bodyLoc, length: 1)).length > 0
        }
        XCTAssertTrue(covered, "rail must cover the body characters, not only the name line; rails=\(rails)")
    }

    func testRealReturnInsideBody_staysInside() {
        editor.testing_insertText("\n")
        editor.testing_insertText("um")
        editor.testing_insertText("\n")
        editor.testing_insertText("dois")

        let doc = editor.currentDocument()
        XCTAssertEqual(doc.body.blocks.count, 1, "got \(doc.body.blocks.map(\.type))")
        XCTAssertEqual(doc.body.blocks[0].type, "speakerSection")
        XCTAssertEqual(doc.body.blocks[0].blocks?.count, 2)
        let texts = (doc.body.blocks[0].blocks ?? []).map { block in
            (block.spans ?? []).map { $0.text ?? "" }.joined()
        }
        XCTAssertEqual(texts, ["um", "dois"])
    }

    func testRealDoubleReturnExitsSection() {
        editor.testing_insertText("\n")
        editor.testing_insertText("dentro")
        editor.testing_insertText("\n") // new empty body line
        editor.testing_insertText("\n") // exit
        editor.testing_insertText("fora")

        let doc = editor.currentDocument()
        XCTAssertEqual(doc.body.blocks.count, 2, "got \(doc.body.blocks.map(\.type))")
        XCTAssertEqual(doc.body.blocks[0].type, "speakerSection")
        XCTAssertEqual(doc.body.blocks[0].blocks?.first?.spans?.first?.text, "dentro")
        XCTAssertEqual(doc.body.blocks[1].type, "paragraph")
        XCTAssertEqual(doc.body.blocks[1].spans?.first?.text, "fora")
    }

    func testHardwareCarriageReturnAlsoInsertsBody() {
        editor.testing_insertText("\r")
        let loc = max(0, editor.testing_selectedRange().location - 1)
        let attrs = editor.testing_textStorage().attributes(at: loc, effectiveRange: nil)
        XCTAssertTrue(NoteDocumentCodec.isSpeakerBody(attrs), "\\r must take the same Enter path as \\n")
        editor.testing_insertText("via CR")
        let doc = editor.currentDocument()
        XCTAssertEqual(doc.body.blocks.count, 1, "got \(doc.body.blocks.map(\.type))")
        XCTAssertEqual(doc.body.blocks[0].type, "speakerSection")
        XCTAssertEqual(doc.body.blocks[0].blocks?.count, 1)
    }

    func testRoundTripNoteDocumentV1AfterRealTyping() {
        editor.testing_insertText("\n")
        editor.testing_insertText("mensagem")
        let first = editor.currentDocument()
        XCTAssertEqual(first.body.blocks[0].type, "speakerSection")
        editor.pushNote(first, speakers: speakers)
        let second = editor.currentDocument()
        XCTAssertEqual(second.body.blocks.count, 1)
        XCTAssertEqual(second.body.blocks[0].type, "speakerSection")
        XCTAssertEqual(second.body.blocks[0].blocks?.first?.spans?.first?.text, "mensagem")
    }
}
