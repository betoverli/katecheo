import XCTest
@testable import Katecheo

/// Regression: after typing pauses (~0.5s), `persist()` posts `.nativeNoteDidChange`,
/// which used to re-enter `refreshFromAPI` → `pushNote` and reset the caret to location 0.
@MainActor
final class NoteDetailCaretPreservationTests: XCTestCase {
    private var hostWindow: UIWindow?
    private var detail: NoteDetailViewController!
    private let noteId = "note-caret-preserve"

    override func setUp() async throws {
        try await super.setUp()
        NativeSWR.resetAllForTests()
        NativeSWR.networkProbeEnabled = true
        LocalNoteCache.clearAll()
        NativeOutbox.clearAll()
        MockNativeURLProtocol.reset()
        MockNativeURLProtocol.register()
        NativeAPIClient.session = MockNativeURLProtocol.makeSession()
        NativeAPIClient.testAuthToken = "test-bearer-caret"
        seedServerNote(title: "Base", bodyText: "body seed")

        var initial = NativeAPIClient.emptyNote(id: noteId)
        initial.title = "Base"
        initial.happenedAt = "2026-01-01"
        initial.updatedAt = "2026-01-01T00:00:00Z"
        initial.body = .init(blocks: [
            .init(
                id: "b1",
                type: "paragraph",
                spans: [.init(type: "text", text: "body seed")],
                speakerId: nil,
                title: nil,
                collapsed: nil,
                checked: nil,
                blocks: nil
            ),
        ])
        LocalNoteCache.upsertNote(initial)

        detail = NoteDetailViewController(noteId: noteId, initial: initial)
        let nav = UINavigationController(rootViewController: detail)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = nav
        window.isHidden = false
        hostWindow = window
        detail.loadViewIfNeeded()
        detail.view.layoutIfNeeded()
        detail.testing_editor.testing_prepare(size: CGSize(width: 390, height: 720))
        // Drain the viewDidLoad refresh so later asserts aren't racing it.
        await detail.testing_refreshFromAPI()
        XCTAssertTrue(detail.testing_screenBufferIsSourceOfTruth)
    }

    override func tearDown() async throws {
        detail.testing_cancelPendingSave()
        hostWindow?.isHidden = true
        hostWindow = nil
        detail = nil
        NativeAPIClient.testAuthToken = nil
        NativeSWR.resetAllForTests()
        NativeAPIClient.session = .shared
        LocalNoteCache.clearAll()
        NativeOutbox.clearAll()
        MockNativeURLProtocol.unregister()
        MockNativeURLProtocol.reset()
        try await super.tearDown()
    }

    private func seedServerNote(title: String, bodyText: String) {
        let note = """
        {"schemaVersion":1,"id":"\(noteId)","title":"\(title)","happenedAt":"2026-01-01","tags":[],"visibility":"private","updatedAt":"2026-01-01T00:00:00Z","body":{"blocks":[{"id":"b1","type":"paragraph","spans":[{"type":"text","text":"\(bodyText)"}]}]}}
        """
        .trimmingCharacters(in: .whitespacesAndNewlines)
        MockNativeURLProtocol.notesJSON = "{\"ok\":true,\"notes\":[\(note)]}"
        MockNativeURLProtocol.noteByIdJSON = "{\"ok\":true,\"note\":\(note),\"speakers\":[],\"via\":\"owned\"}"
        MockNativeURLProtocol.upsertNoteJSON = "{\"ok\":true,\"note\":\(note),\"speakers\":[],\"via\":\"owned\"}"
        MockNativeURLProtocol.speakersJSON = "{\"ok\":true,\"speakers\":[]}"
    }

    private func titleEndRange(in editor: NativeNoteEditorView) -> NSRange {
        let storage = editor.testing_textStorage()
        let titlePara = (storage.string as NSString).paragraphRange(for: NSRange(location: 0, length: 0))
        // Caret at end of title text (before the title paragraph newline when present).
        var end = NSMaxRange(titlePara)
        if end > titlePara.location {
            let last = (storage.string as NSString).character(at: end - 1)
            if last == 10 /* \\n */ || last == 0x200B /* ZWSP */ {
                end -= 1
            }
        }
        return NSRange(location: end, length: 0)
    }

    private func bodyEndRange(in editor: NativeNoteEditorView) -> NSRange {
        let storage = editor.testing_textStorage()
        return NSRange(location: storage.length, length: 0)
    }

    private func assertCaretPreserved(
        editor: NativeNoteEditorView,
        expectedPlainContains: String,
        expectedLocation: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        // Simulate successful persist (dirty cleared) — the bug path.
        detail.testing_cancelPendingSave()
        detail.testing_simulateSuccessfulPersist()
        XCTAssertFalse(detail.testing_hasLocalEdits, file: file, line: line)

        // External notification (no sender) + refresh + outbox flush — all must keep caret.
        detail.testing_postExternalNoteDidChange()
        // Give the notification observer a turn (it Task{}s refreshFromAPI).
        await Task.yield()
        await detail.testing_refreshFromAPI()
        detail.testing_outboxDidFlush()
        await Task.yield()
        await detail.testing_refreshFromAPI(force: true)

        let plain = editor.testing_textStorage().string
        XCTAssertTrue(
            plain.contains(expectedPlainContains),
            "typed text must survive refresh; plain=\(plain.debugDescription)",
            file: file,
            line: line
        )
        let sel = editor.testing_selectedRange()
        XCTAssertEqual(sel.length, 0, "selection must stay collapsed", file: file, line: line)
        XCTAssertEqual(
            sel.location,
            expectedLocation,
            "caret must stay at end of typed text, not jump to 0; plain=\(plain.debugDescription)",
            file: file,
            line: line
        )
        XCTAssertNotEqual(sel.location, 0, "caret must not reset to title start", file: file, line: line)
    }

    func testTypingInTitle_persistAndRefresh_keepsCaretAtEnd() async {
        let editor = detail.testing_editor
        editor.testing_setSelectedRange(titleEndRange(in: editor))
        editor.testing_insertText("ABC")

        let afterType = editor.testing_selectedRange()
        XCTAssertGreaterThan(afterType.location, 0)
        XCTAssertTrue(editor.testing_textStorage().string.contains("ABC"))
        // Delegate marks local edits + schedules save — cancel so we control the persist sim.
        detail.testing_cancelPendingSave()
        XCTAssertTrue(detail.testing_hasLocalEdits)

        await assertCaretPreserved(
            editor: editor,
            expectedPlainContains: "ABC",
            expectedLocation: afterType.location
        )
    }

    func testTypingInBody_persistAndRefresh_keepsCaretAtEnd() async {
        let editor = detail.testing_editor
        // Move into body (after title paragraph) then type.
        editor.testing_setSelectedRange(titleEndRange(in: editor))
        editor.testing_insertText("\n")
        editor.testing_setSelectedRange(bodyEndRange(in: editor))
        editor.testing_insertText("XYZ")

        let afterType = editor.testing_selectedRange()
        XCTAssertGreaterThan(afterType.location, 0)
        XCTAssertTrue(editor.testing_textStorage().string.contains("XYZ"))
        detail.testing_cancelPendingSave()
        XCTAssertTrue(detail.testing_hasLocalEdits)

        await assertCaretPreserved(
            editor: editor,
            expectedPlainContains: "XYZ",
            expectedLocation: afterType.location
        )
    }

    func testPushNote_sameId_preservesSelectedRange() {
        let editor = NativeNoteEditorView(frame: CGRect(x: 0, y: 0, width: 390, height: 720))
        editor.testing_prepare(size: CGSize(width: 390, height: 720))
        var note = NativeAPIClient.emptyNote(id: "same-id")
        note.title = "Hello"
        note.body = .init(blocks: [
            .init(
                id: "b1",
                type: "paragraph",
                spans: [.init(type: "text", text: "world")],
                speakerId: nil,
                title: nil,
                collapsed: nil,
                checked: nil,
                blocks: nil
            ),
        ])
        editor.pushNote(note, speakers: [])
        XCTAssertEqual(editor.testing_selectedRange().location, 0)

        let end = editor.testing_textStorage().length
        let caret = max(1, end / 2)
        editor.testing_setSelectedRange(NSRange(location: caret, length: 0))
        editor.pushNote(note, speakers: [])
        XCTAssertEqual(
            editor.testing_selectedRange().location,
            caret,
            "same-id refresh must clamp-preserve caret"
        )

        var other = note
        other.id = "other-id"
        editor.pushNote(other, speakers: [])
        XCTAssertEqual(
            editor.testing_selectedRange().location,
            0,
            "different note id is an initial load → caret at 0"
        )
    }
}
