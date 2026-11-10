import XCTest
@testable import Katecheo

/// Real `NativeNoteEditorView` coverage for TestFlight 210 feedback.
@MainActor
final class NativeNoteEditorTF210Tests: XCTestCase {
    private var editor: NativeNoteEditorView!
    private let speakers = [
        NativeAPIClient.SpeakerDTO(
            id: "sp1",
            name: "Hélio Azevedo",
            color: "#C4A574",
            updatedAt: "2026-01-01T00:00:00Z"
        ),
    ]

    override func setUp() async throws {
        try await super.setUp()
        editor = NativeNoteEditorView(frame: .zero)
        editor.testing_prepare()
        var note = NativeAPIClient.emptyNote(id: "note-tf210")
        note.title = "Culto"
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

    private func indentPair(at location: Int) -> (first: CGFloat, head: CGFloat) {
        let storage = editor.testing_textStorage()
        let loc = min(max(0, location), max(0, storage.length - 1))
        let style = storage.attributes(at: loc, effectiveRange: nil)[.paragraphStyle] as? NSParagraphStyle
        return (style?.firstLineHeadIndent ?? -1, style?.headIndent ?? -1)
    }

    // Bug 1: list wraps hang by measured marker width (outside + inside speaker).
    func testListHangIndent_outsideAndInsideSpeaker() {
        let storage = editor.testing_textStorage()
        let ns = storage.string as NSString
        let lastPara = ns.paragraphRange(for: NSRange(location: max(0, ns.length - 1), length: 0))
        editor.testing_setSelectedRange(NSRange(location: lastPara.location, length: 0))
        editor.testing_insertText("item longo")
        editor.testing_applyBlockTypeHook("bullet")

        let loc = editor.testing_selectedRange().location - 1
        let (first, head) = indentPair(at: loc)
        let expected = NoteDocumentCodec.listMarkerWidth(
            type: "bullet",
            checked: nil,
            number: 1,
            font: UIFont.preferredFont(forTextStyle: .body)
        )
        XCTAssertEqual(first, 0, accuracy: 0.5)
        XCTAssertEqual(head, expected, accuracy: 0.5, "wrap hang = marker width")

        editor.insertSpeakerSection(speakerId: "sp1", name: "Hélio Azevedo")
        editor.testing_insertText("dentro")
        editor.testing_applyBlockTypeHook("bullet")
        let insideLoc = editor.testing_selectedRange().location - 1
        let (inFirst, inHead) = indentPair(at: insideLoc)
        let inset = NoteDocumentCodec.speakerSectionContentInset
        XCTAssertEqual(inFirst, inset, accuracy: 0.5)
        XCTAssertEqual(inHead, inset + expected, accuracy: 0.5, "speaker list keeps hang under inset")
    }

    // Bug 5: body placeholder hides for reference pills / speaker attachments.
    func testBodyPlaceholder_hidesForBibleRefAndSpeaker() {
        var blank = NativeAPIClient.emptyNote(id: "note-blank-tf210")
        blank.title = ""
        blank.body.blocks = [
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
        editor.pushNote(blank, speakers: speakers)
        XCTAssertTrue(editor.testing_bodyPlaceholderVisible())

        let storage = editor.testing_textStorage()
        editor.testing_setSelectedRange(NSRange(location: storage.length, length: 0))
        editor.insertBibleRef(
            NoteDocumentCodec.BibleRefPayload(
                bookId: "LUK",
                chapter: 14,
                verseStart: 26,
                verseEnd: nil,
                text: nil
            )
        )
        XCTAssertFalse(
            editor.testing_bodyPlaceholderVisible(),
            "reference pill alone must hide the body placeholder"
        )

        editor.pushNote(blank, speakers: speakers)
        XCTAssertTrue(editor.testing_bodyPlaceholderVisible())
        editor.insertSpeakerSection(speakerId: "sp1", name: "Hélio Azevedo")
        XCTAssertFalse(
            editor.testing_bodyPlaceholderVisible(),
            "speaker header alone must hide the body placeholder"
        )
    }

    // Bug 7: @ / are ordinary characters.
    func testAtAndSlash_insertLiterally() {
        let before = editor.testing_textStorage().length
        editor.testing_insertText("@hello")
        XCTAssertTrue(editor.testing_textStorage().string.contains("@hello"))
        editor.testing_insertText("/")
        XCTAssertTrue(editor.testing_textStorage().string.contains("/"))
        XCTAssertGreaterThan(editor.testing_textStorage().length, before)
    }

    // Bug 3: tags strip under title.
    func testTagsStrip_roundTripsOnDocument() {
        editor.testing_setTags(["culto", "oração"])
        XCTAssertEqual(Set(editor.testing_tags()), Set(["culto", "oração"]))
        XCTAssertEqual(Set(editor.currentDocument().tags), Set(["culto", "oração"]))
    }

    // Bug 6: toolbar order — speaker/ref first, no undo/redo.
    func testAccessoryBar_orderAndNoUndoRedo() {
        let labels = NoteEditorAccessoryBar.testing_actionLabels()
        XCTAssertEqual(labels.first, String(localized: "Speaker"))
        XCTAssertEqual(labels.dropFirst().first, String(localized: "Referência bíblica"))
        XCTAssertFalse(labels.contains(String(localized: "Desfazer")))
        XCTAssertFalse(labels.contains(String(localized: "Refazer")))
    }
}
