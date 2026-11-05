import XCTest
@testable import App

/// Drives real `NativeNoteEditorView` against web-parity speaker behavior
/// (`docs/editor-behavior-spec.md`). Covers Beto's build-189 bugs.
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
        NativeAPIClient.SpeakerDTO(
            id: "sp2",
            name: "Ana",
            color: "#8B7355",
            updatedAt: "2026-01-01T00:00:00Z"
        ),
    ]

    override func setUp() async throws {
        try await super.setUp()
        editor = NativeNoteEditorView(frame: .zero)
        editor.testing_prepare()
        var note = NativeAPIClient.emptyNote(id: "note-parity")
        note.title = "Reunião"
        note.body.blocks = [
            NativeAPIClient.LineBlock(
                id: "p1",
                type: "paragraph",
                spans: [],
                speakerId: nil,
                title: nil,
                collapsed: nil,
                checked: nil,
                blocks: nil
            ),
        ]
        editor.pushNote(note, speakers: speakers)
        let storage = editor.testing_textStorage()
        editor.testing_setSelectedRange(NSRange(location: storage.length, length: 0))
    }

    override func tearDown() async throws {
        editor = nil
        try await super.tearDown()
    }

    private func speakerBlock(in doc: NativeAPIClient.NoteDocument) -> NativeAPIClient.LineBlock? {
        doc.body.blocks.first(where: { $0.type == "speakerSection" })
    }

    private func headerAttachmentCount() -> Int {
        let storage = editor.testing_textStorage()
        var count = 0
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            if value is SpeakerHeaderAttachment { count += 1 }
        }
        return count
    }

    // Bug 1: header is a non-editable block (attachment), not typed text.
    func testSpeakerHeaderIsNonEditableAttachment() {
        editor.insertSpeakerSection(speakerId: "sp1", name: "Beto")
        XCTAssertEqual(headerAttachmentCount(), 1)
        XCTAssertEqual(editor.testing_paragraphBlockType(), "paragraph", "caret must land in body, not header")
        XCTAssertTrue(NoteDocumentCodec.isSpeakerBody(
            editor.testing_textStorage().attributes(
                at: min(editor.testing_selectedRange().location, max(0, editor.testing_textStorage().length - 1)),
                effectiveRange: nil
            )
        ))

        // Typing near/on the header must not change the speaker name in the model.
        if let headerLoc = SpeakerSectionEditing.findSpeakerHeaderRange(in: editor.testing_textStorage())?.location {
            editor.testing_setSelectedRange(NSRange(location: headerLoc, length: 0))
            editor.testing_insertText("HACK")
        }
        let doc = editor.currentDocument()
        XCTAssertEqual(speakerBlock(in: doc)?.title, "Beto")
        XCTAssertEqual(speakerBlock(in: doc)?.speakerId, "sp1")
        let storage = editor.testing_textStorage()
        let plain = storage.string.replacingOccurrences(of: "\u{FFFC}", with: "")
        XCTAssertFalse(plain.contains("HACK"), "typed text must not land in the header name")
    }

    // Bug 2: insert after a normal line must not create a blank speaker section.
    func testInsertAfterNormalLine_noPhantomBlankSpeaker() {
        editor.testing_insertText("linha normal")
        editor.insertSpeakerSection(speakerId: "sp1", name: "Beto")
        let doc = editor.currentDocument()
        let speakers = doc.body.blocks.filter { $0.type == "speakerSection" }
        XCTAssertEqual(speakers.count, 1, "exactly one speaker section; got \(doc.body.blocks.map(\.type))")
        XCTAssertEqual(headerAttachmentCount(), 1)
        // No empty speakerSection siblings.
        XCTAssertFalse(speakers.contains { ($0.blocks ?? []).isEmpty && ($0.title == "Speaker" || $0.title?.isEmpty == true) })
    }

    // Bug 3: one Enter = one new body paragraph.
    func testEnterInsideSection_createsExactlyOneParagraph() {
        editor.insertSpeakerSection(speakerId: "sp1", name: "Beto")
        editor.testing_insertText("primeiro")
        let before = paragraphCount(editor.testing_textStorage())
        editor.testing_insertText("\n")
        let after = paragraphCount(editor.testing_textStorage())
        XCTAssertEqual(after, before + 1, "Enter must create exactly one paragraph")
        editor.testing_insertText("segundo")
        let doc = editor.currentDocument()
        let texts = (speakerBlock(in: doc)?.blocks ?? []).map { block in
            (block.spans ?? []).compactMap(\.text).joined()
        }.filter { !$0.isEmpty }
        XCTAssertEqual(texts, ["primeiro", "segundo"])
    }

    // Bug 4: collapse toggle persists and hides body.
    func testCollapseToggle_hidesBodyAndPersists() {
        editor.insertSpeakerSection(speakerId: "sp1", name: "Beto")
        editor.testing_insertText("corpo")
        let doc = editor.currentDocument()
        guard let id = speakerBlock(in: doc)?.id else { return XCTFail("missing section") }

        editor.testing_toggleCollapse(sectionId: id)
        let collapsedDoc = editor.currentDocument()
        XCTAssertEqual(speakerBlock(in: collapsedDoc)?.collapsed, true)
        let storage = editor.testing_textStorage()
        XCTAssertFalse(storage.string.contains("corpo"), "collapsed body must be hidden in the text view")
        XCTAssertEqual(speakerBlock(in: collapsedDoc)?.blocks?.first?.spans?.first?.text, "corpo")

        editor.testing_toggleCollapse(sectionId: id)
        let expanded = editor.currentDocument()
        XCTAssertNil(speakerBlock(in: expanded)?.collapsed)
        XCTAssertTrue(editor.testing_textStorage().string.contains("corpo"))
    }

    func testRemoveSection_discardsBody() {
        editor.insertSpeakerSection(speakerId: "sp1", name: "Beto")
        editor.testing_insertText("descartar")
        let doc = editor.currentDocument()
        guard let id = speakerBlock(in: doc)?.id else { return XCTFail("missing section") }
        editor.testing_removeSection(sectionId: id)
        let after = editor.currentDocument()
        XCTAssertNil(speakerBlock(in: after))
        XCTAssertFalse(after.body.blocks.contains { ($0.spans ?? []).contains { $0.text == "descartar" } })
        XCTAssertEqual(headerAttachmentCount(), 0)
    }

    func testEmptyLastBodyEnter_exitsSection() {
        editor.insertSpeakerSection(speakerId: "sp1", name: "Beto")
        editor.testing_insertText("dentro")
        editor.testing_insertText("\n")
        editor.testing_insertText("\n")
        editor.testing_insertText("fora")
        let doc = editor.currentDocument()
        XCTAssertEqual(speakerBlock(in: doc)?.blocks?.first?.spans?.first?.text, "dentro")
        XCTAssertTrue(doc.body.blocks.contains {
            $0.type == "paragraph" && ($0.spans ?? []).contains { ($0.text ?? "").contains("fora") }
        }, "got \(doc.body.blocks.map(\.type))")
    }

    func testRoundTripNoteDocumentV1_preservesAttachmentHeader() {
        editor.insertSpeakerSection(speakerId: "sp1", name: "Beto")
        editor.testing_insertText("mensagem")
        let first = editor.currentDocument()
        editor.pushNote(first, speakers: speakers)
        let second = editor.currentDocument()
        XCTAssertEqual(speakerBlock(in: second)?.title, "Beto")
        XCTAssertEqual(speakerBlock(in: second)?.blocks?.first?.spans?.first?.text, "mensagem")
        XCTAssertEqual(headerAttachmentCount(), 1)
    }

    func testRenameViaAPI_updatesHeaderNotBodyText() {
        editor.insertSpeakerSection(speakerId: "sp1", name: "Beto")
        editor.testing_insertText("corpo")
        guard let id = speakerBlock(in: editor.currentDocument())?.id else { return XCTFail("missing") }
        editor.renameSpeakerSection(sectionId: id, speakerId: "sp2", name: "Ana")
        let doc = editor.currentDocument()
        XCTAssertEqual(speakerBlock(in: doc)?.speakerId, "sp2")
        XCTAssertEqual(speakerBlock(in: doc)?.title, "Ana")
        XCTAssertEqual(speakerBlock(in: doc)?.blocks?.first?.spans?.first?.text, "corpo")
    }

    private func paragraphCount(_ storage: NSAttributedString) -> Int {
        let ns = storage.string as NSString
        var count = 0
        var cursor = 0
        while cursor < ns.length {
            let para = ns.paragraphRange(for: NSRange(location: cursor, length: 0))
            count += 1
            let next = NSMaxRange(para)
            if next <= cursor { break }
            cursor = next
        }
        return max(count, storage.length == 0 ? 0 : 1)
    }
}
