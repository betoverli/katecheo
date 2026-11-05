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
        // Title-only body so the inserted speaker is the sole body block (matches a fresh note
        // where the user replaced the first empty paragraph / typed at the end after clearing).
        var note = NativeAPIClient.emptyNote(id: "note-speaker-path")
        note.title = "Reunião"
        note.body.blocks = []
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

    private func speakerBlock(in doc: NativeAPIClient.NoteDocument) -> NativeAPIClient.LineBlock? {
        doc.body.blocks.first(where: { $0.type == "speakerSection" })
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
        XCTAssertNotNil(speakerBlock(in: editor.currentDocument()))
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
        guard let speaker = speakerBlock(in: doc) else {
            return XCTFail("missing speakerSection in \(doc.body.blocks.map(\.type))")
        }
        XCTAssertEqual(speaker.blocks?.count, 1, "body must be a child of the speaker section")
        let bodyText = speaker.blocks?.first?.spans?.map { $0.text ?? "" }.joined() ?? ""
        XCTAssertTrue(bodyText.contains("corpo dentro"), "got \(bodyText)")

        // Sibling paragraphs after the section must not steal the typed body.
        let escaped = doc.body.blocks.contains { block in
            block.type != "speakerSection"
                && (block.spans ?? []).contains { ($0.text ?? "").contains("corpo dentro") }
        }
        XCTAssertFalse(escaped, "typed body escaped the speaker container: \(doc.body.blocks.map(\.type))")

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
        guard let speaker = speakerBlock(in: doc) else {
            return XCTFail("missing speakerSection in \(doc.body.blocks.map(\.type))")
        }
        XCTAssertEqual(speaker.blocks?.count, 2)
        let texts = (speaker.blocks ?? []).map { block in
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
        guard let speaker = speakerBlock(in: doc) else {
            return XCTFail("missing speakerSection in \(doc.body.blocks.map(\.type))")
        }
        XCTAssertEqual(speaker.blocks?.first?.spans?.first?.text, "dentro")
        let outside = doc.body.blocks.first(where: { $0.type == "paragraph" && ($0.spans?.first?.text == "fora") })
        XCTAssertNotNil(outside, "exit must place a normal paragraph after the section; got \(doc.body.blocks.map(\.type))")
    }

    func testHardwareCarriageReturnAlsoInsertsBody() {
        editor.testing_insertText("\r")
        let loc = max(0, editor.testing_selectedRange().location - 1)
        let attrs = editor.testing_textStorage().attributes(at: loc, effectiveRange: nil)
        XCTAssertTrue(NoteDocumentCodec.isSpeakerBody(attrs), "\\r must take the same Enter path as \\n")
        editor.testing_insertText("via CR")
        let doc = editor.currentDocument()
        guard let speaker = speakerBlock(in: doc) else {
            return XCTFail("missing speakerSection in \(doc.body.blocks.map(\.type))")
        }
        XCTAssertEqual(speaker.blocks?.count, 1)
        let text = speaker.blocks?.first?.spans?.map { $0.text ?? "" }.joined() ?? ""
        XCTAssertTrue(text.contains("via CR"), "got \(text)")
    }

    func testRoundTripNoteDocumentV1AfterRealTyping() {
        editor.testing_insertText("\n")
        editor.testing_insertText("mensagem")
        let first = editor.currentDocument()
        guard let speaker = speakerBlock(in: first) else {
            return XCTFail("missing speakerSection in \(first.body.blocks.map(\.type))")
        }
        XCTAssertEqual(speaker.blocks?.first?.spans?.first?.text, "mensagem")
        editor.pushNote(first, speakers: speakers)
        let second = editor.currentDocument()
        guard let again = speakerBlock(in: second) else {
            return XCTFail("speaker lost on reload")
        }
        XCTAssertEqual(again.blocks?.first?.spans?.first?.text, "mensagem")
    }
}
