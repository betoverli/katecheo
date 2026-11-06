import XCTest
@testable import App

/// Real `NativeNoteEditorView` coverage for TestFlight 200 feedback.
@MainActor
final class NativeNoteEditorTF200Tests: XCTestCase {
    private var editor: NativeNoteEditorView!
    private let speakers = [
        NativeAPIClient.SpeakerDTO(
            id: "sp1",
            name: "Hélio Azevedo",
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
        var note = NativeAPIClient.emptyNote(id: "note-tf200")
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

    private func parkCaretAtEndOfCurrentParagraph() {
        let storage = editor.testing_textStorage()
        let loc = min(editor.testing_selectedRange().location, max(0, storage.length - 1))
        let para = (storage.string as NSString).paragraphRange(for: NSRange(location: loc, length: 0))
        let end = NSMaxRange(para)
        let lastIsNL = end > para.location
            && (storage.string as NSString).substring(with: NSRange(location: end - 1, length: 1)) == "\n"
        editor.testing_setSelectedRange(NSRange(location: end - (lastIsNL ? 1 : 0), length: 0))
    }

    private func speakerChildTypes() -> [String] {
        let doc = editor.currentDocument()
        guard let section = doc.body.blocks.first(where: { $0.type == "speakerSection" }) else {
            return []
        }
        return (section.blocks ?? []).map(\.type)
    }

    private func runListEnterInsideSpeaker(listType: String) {
        // Seed the section in the model so caret/body membership is unambiguous.
        var note = NativeAPIClient.emptyNote(id: "note-tf200-\(listType)")
        note.title = "Culto"
        let bodyId = "body1"
        note.body.blocks = [
            NativeAPIClient.LineBlock(
                id: "sec1",
                type: "speakerSection",
                spans: nil,
                speakerId: "sp1",
                title: "Hélio Azevedo",
                collapsed: nil,
                checked: nil,
                blocks: [
                    NativeAPIClient.LineBlock(
                        id: bodyId,
                        type: "paragraph",
                        spans: [.init(type: "text", text: "item", marks: nil, bookId: nil, chapter: nil, verseStart: nil, verseEnd: nil, href: nil)],
                        speakerId: nil,
                        title: nil,
                        collapsed: nil,
                        checked: nil,
                        blocks: nil
                    ),
                ]
            ),
            NativeAPIClient.LineBlock(
                id: "trail",
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

        // Place caret at end of the seeded body line.
        let storage = editor.testing_textStorage()
        let range = (storage.string as NSString).range(of: "item")
        XCTAssertNotEqual(range.location, NSNotFound, "seeded body missing")
        editor.testing_setSelectedRange(NSRange(location: NSMaxRange(range), length: 0))
        let startAttrs = storage.attributes(at: range.location, effectiveRange: nil)
        NSLog(
            "TF200 \(listType) start type=%@ bodyKey=%@ children=%@",
            (startAttrs[NoteDocumentCodec.blockTypeKey] as? String) ?? "?",
            String(describing: startAttrs[NoteDocumentCodec.speakerBodyKey]),
            speakerChildTypes().description
        )
        XCTAssertTrue(NoteDocumentCodec.isSpeakerBody(startAttrs), "seeded body must have speakerBodyKey")

        editor.testing_applyBlockTypeHook(listType)
        let afterPromoteType = editor.testing_paragraphBlockType()
        let afterPromoteChildren = speakerChildTypes()
        NSLog("TF200 \(listType) after promote type=%@ children=%@", afterPromoteType, afterPromoteChildren.description)
        XCTAssertEqual(afterPromoteType, listType, "promote \(listType); children=\(afterPromoteChildren)")
        XCTAssertTrue(afterPromoteChildren.contains(listType), "children after promote: \(afterPromoteChildren)")

        parkCaretAtEndOfCurrentParagraph()
        editor.testing_insertText("\n")
        let afterContinueType = editor.testing_paragraphBlockType()
        let afterContinueChildren = speakerChildTypes()
        NSLog("TF200 \(listType) after continue type=%@ children=%@", afterContinueType, afterContinueChildren.description)
        XCTAssertEqual(afterContinueType, listType, "Enter continues \(listType); children=\(afterContinueChildren)")
        XCTAssertGreaterThanOrEqual(
            afterContinueChildren.filter { $0 == listType }.count,
            2,
            "two \(listType) children; children=\(afterContinueChildren)"
        )

        editor.testing_insertText("\n")
        let afterDemoteType = editor.testing_paragraphBlockType()
        let afterDemoteChildren = speakerChildTypes()
        let loc = min(editor.testing_selectedRange().location, max(0, editor.testing_textStorage().length - 1))
        let attrs = editor.testing_textStorage().attributes(at: loc, effectiveRange: nil)
        NSLog(
            "TF200 \(listType) after demote type=%@ bodyKey=%@ children=%@",
            afterDemoteType,
            String(describing: attrs[NoteDocumentCodec.speakerBodyKey]),
            afterDemoteChildren.description
        )
        XCTAssertEqual(afterDemoteType, "paragraph", "empty demotes; children=\(afterDemoteChildren)")
        XCTAssertEqual(afterDemoteChildren.last, "paragraph", "demoted last child; children=\(afterDemoteChildren)")
        XCTAssertTrue(
            NoteDocumentCodec.isSpeakerBody(attrs),
            "must stay inside section; children=\(afterDemoteChildren)"
        )
    }

    // Bug 1: lists inside a speaker section continue / empty-exit like outside.
    func testListEnter_insideSpeaker_continuesThenEmptyStaysInside() {
        runListEnterInsideSpeaker(listType: "bullet")
    }

    func testNumberedListEnter_insideSpeaker_continuesThenEmptyStaysInside() {
        runListEnterInsideSpeaker(listType: "numbered")
    }

    // Bug 2: @ and / must not insert the trigger character (full screens open via delegate).
    func testAtAndSlash_doNotInsertTriggerCharacter() {
        let before = editor.testing_textStorage().string
        editor.testing_insertText("@")
        XCTAssertEqual(
            editor.testing_textStorage().string,
            before,
            "@ must open the speaker screen without inserting @"
        )
        editor.testing_insertText("/")
        XCTAssertEqual(
            editor.testing_textStorage().string,
            before,
            "/ must open the reference screen without inserting /"
        )
    }

    // Bug 4: title + body placeholders.
    func testPlaceholders_hideWhenTyping() {
        var blank = NativeAPIClient.emptyNote(id: "note-blank")
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
        XCTAssertTrue(editor.testing_titlePlaceholderVisible())
        XCTAssertTrue(editor.testing_bodyPlaceholderVisible())
        XCTAssertEqual(editor.testing_titlePlaceholderText(), String(localized: "Título"))
        XCTAssertEqual(editor.testing_bodyPlaceholderText(), String(localized: "Comece a escrever…"))

        // Type into the title (first heading paragraph).
        editor.testing_setSelectedRange(NSRange(location: 0, length: 0))
        editor.testing_insertText("Culto")
        XCTAssertFalse(editor.testing_titlePlaceholderVisible())
        XCTAssertTrue(editor.testing_bodyPlaceholderVisible())

        // Move to body and type.
        let storage = editor.testing_textStorage()
        editor.testing_setSelectedRange(NSRange(location: storage.length, length: 0))
        editor.testing_insertText("olá")
        XCTAssertFalse(editor.testing_bodyPlaceholderVisible())
    }
}

final class LocalNoteCacheSpeakerMergeTests: XCTestCase {
    // Bug 3: note-scoped speaker lists must not wipe the catalog.
    func testMergeSpeakers_doesNotWipeCatalog() {
        let previous = LocalNoteCache.loadSpeakers()
        defer { LocalNoteCache.saveSpeakers(previous) }

        let full = [
            NativeAPIClient.SpeakerDTO(id: "a", name: "Ana", color: "#111111", updatedAt: "2026-01-01T00:00:00Z"),
            NativeAPIClient.SpeakerDTO(id: "b", name: "Beto", color: "#222222", updatedAt: "2026-01-01T00:00:00Z"),
            NativeAPIClient.SpeakerDTO(id: "c", name: "Carla", color: "#333333", updatedAt: "2026-01-01T00:00:00Z"),
        ]
        LocalNoteCache.saveSpeakers(full)
        let noteScoped = [full[1]]
        let merged = LocalNoteCache.mergeSpeakers(noteScoped)
        XCTAssertEqual(Set(merged.map(\.id)), Set(["a", "b", "c"]))
        XCTAssertEqual(Set(LocalNoteCache.loadSpeakers().map(\.id)), Set(["a", "b", "c"]))
    }
}
