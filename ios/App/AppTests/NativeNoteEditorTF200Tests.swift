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

    // Bug 1: lists inside a speaker section continue / empty-exit like outside.
    func testListEnter_insideSpeaker_continuesThenEmptyStaysInside() {
        editor.insertSpeakerSection(speakerId: "sp1", name: "Hélio Azevedo")
        editor.testing_insertText("item")
        editor.testing_applyBlockTypeHook("bullet")
        XCTAssertEqual(
            editor.testing_paragraphBlockType(),
            "bullet",
            "promote inside section; plain=\(editor.testing_textStorage().string.debugDescription)"
        )
        parkCaretAtEndOfCurrentParagraph()
        editor.testing_insertText("\n")
        XCTAssertEqual(
            editor.testing_paragraphBlockType(),
            "bullet",
            "Enter continues bullet inside section"
        )
        // Empty Enter demotes but stays inside the speaker (speakerBodyKey).
        editor.testing_insertText("\n")
        XCTAssertEqual(editor.testing_paragraphBlockType(), "paragraph")
        let loc = min(editor.testing_selectedRange().location, max(0, editor.testing_textStorage().length - 1))
        let attrs = editor.testing_textStorage().attributes(at: loc, effectiveRange: nil)
        XCTAssertTrue(
            NoteDocumentCodec.isSpeakerBody(attrs),
            "empty list exit must stay inside the section"
        )

        // Numbered path too.
        editor.testing_insertText("um")
        editor.testing_applyBlockTypeHook("numbered")
        XCTAssertEqual(editor.testing_paragraphBlockType(), "numbered")
        parkCaretAtEndOfCurrentParagraph()
        editor.testing_insertText("\n")
        XCTAssertEqual(editor.testing_paragraphBlockType(), "numbered")
        editor.testing_insertText("\n")
        XCTAssertEqual(editor.testing_paragraphBlockType(), "paragraph")
        let loc2 = min(editor.testing_selectedRange().location, max(0, editor.testing_textStorage().length - 1))
        let attrs2 = editor.testing_textStorage().attributes(at: loc2, effectiveRange: nil)
        XCTAssertTrue(NoteDocumentCodec.isSpeakerBody(attrs2))
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
