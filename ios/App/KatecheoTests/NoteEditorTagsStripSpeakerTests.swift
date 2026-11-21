import XCTest
@testable import Katecheo

/// Whole-note speaker chip lives at the start of the tags strip (scrolls with content).
@MainActor
final class NoteEditorTagsStripSpeakerTests: XCTestCase {
    private var editor: NativeNoteEditorView!
    private let speakers = [
        NativeAPIClient.SpeakerDTO(
            id: "spk-ana",
            name: "Ana",
            color: "#C4A574",
            updatedAt: "2026-01-01T00:00:00Z"
        ),
    ]

    override func setUp() async throws {
        try await super.setUp()
        editor = NativeNoteEditorView(frame: .zero)
        editor.testing_prepare()
        var note = NativeAPIClient.emptyNote(id: "note-tags-speaker")
        note.title = "Culto"
        note.noteSpeakerId = nil
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
    }

    override func tearDown() async throws {
        editor = nil
        try await super.tearDown()
    }

    func testEmptySpeakerChip_showsLocalizedSpeakerLabel_andLeadsStrip() {
        XCTAssertFalse(editor.testing_tagsStripHasAssignedSpeaker())
        XCTAssertEqual(editor.testing_tagsStripSpeakerTitle(), String(localized: "Speaker"))
        XCTAssertTrue(editor.testing_tagsStripSpeakerIsFirst())
    }

    func testSetNoteSpeakerId_updatesChipTitle_andPersistsOnDocument() {
        editor.testing_setNoteSpeakerId("spk-ana")
        XCTAssertTrue(editor.testing_tagsStripHasAssignedSpeaker())
        XCTAssertEqual(editor.testing_tagsStripSpeakerTitle(), "Ana")
        XCTAssertEqual(editor.testing_noteSpeakerId(), "spk-ana")
        XCTAssertEqual(editor.currentDocument().noteSpeakerId, "spk-ana")
        XCTAssertTrue(editor.testing_tagsStripSpeakerIsFirst())
    }

    func testClearNoteSpeaker_restoresEmptyChip() {
        editor.testing_setNoteSpeakerId("spk-ana")
        editor.testing_setNoteSpeakerId(nil)
        XCTAssertFalse(editor.testing_tagsStripHasAssignedSpeaker())
        XCTAssertEqual(editor.testing_tagsStripSpeakerTitle(), String(localized: "Speaker"))
        XCTAssertNil(editor.testing_noteSpeakerId())
    }

    func testSpeakerChip_staysFirstWhenTagsPresent() {
        editor.testing_setTags(["culto", "oração"])
        editor.testing_setNoteSpeakerId("spk-ana")
        XCTAssertTrue(editor.testing_tagsStripSpeakerIsFirst())
        XCTAssertEqual(Set(editor.testing_tags()), Set(["culto", "oração"]))
    }

    func testPushNote_withSpeaker_paintsChip() {
        var note = NativeAPIClient.emptyNote(id: "note-tags-speaker-2")
        note.title = "Estudo"
        note.noteSpeakerId = "spk-ana"
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
        XCTAssertEqual(editor.testing_tagsStripSpeakerTitle(), "Ana")
        XCTAssertTrue(editor.testing_tagsStripHasAssignedSpeaker())
    }

    func testNoteDetail_hasNoPinnedTopChrome_andChipInEditor() throws {
        var note = NativeAPIClient.emptyNote(id: "note-detail-speaker-chrome")
        note.title = "Culto"
        note.noteSpeakerId = "spk-ana"
        LocalNoteCache.mergeSpeakers(speakers)
        LocalNoteCache.upsertNote(note)

        let detail = NoteDetailViewController(noteId: note.id, initial: note)
        let nav = UINavigationController(rootViewController: detail)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = nav
        window.makeKeyAndVisible()
        detail.loadViewIfNeeded()
        detail.view.layoutIfNeeded()

        // Pinned speaker chrome removed — editor is a direct subview under the safe area.
        let editorSubviews = detail.view.subviews.compactMap { $0 as? NativeNoteEditorView }
        XCTAssertEqual(editorSubviews.count, 1)
        let editorView = try XCTUnwrap(editorSubviews.first)
        XCTAssertEqual(
            editorView.frame.minY,
            detail.view.safeAreaInsets.top,
            accuracy: 0.5
        )
        XCTAssertEqual(editorView.testing_tagsStripSpeakerTitle(), "Ana")
        XCTAssertTrue(editorView.testing_tagsStripSpeakerIsFirst())
        window.isHidden = true
    }

    func testFormattingToolbar_staysHiddenWhileTagsEditing() {
        // Speaker chip lives in the tags strip; format toolbar stays off until body focus.
        XCTAssertFalse(editor.testing_isFormattingToolbarVisible())
        editor.testing_setTags(["a"])
        XCTAssertFalse(editor.testing_isFormattingToolbarVisible())
    }

    func testTagsEdgeFade_maskIsStaticOnContainer_notScrollDrivenReveal() {
        let strip = NoteEditorTagsStrip(frame: CGRect(x: 0, y: 0, width: 200, height: 32))
        strip.setSpeakerName("Ana")
        strip.setTags(["culto", "manhã", "estudo", "noite", "oração", "louvor"])
        strip.layoutIfNeeded()
        strip.testing_updateEdgeFadeMask()

        XCTAssertTrue(strip.testing_maskIsOnContainer, "fade must clip the strip, not animate chips")
        XCTAssertGreaterThanOrEqual(strip.testing_edgeFadeWidth, 24)
        XCTAssertLessThanOrEqual(strip.testing_edgeFadeWidth, 32)

        let scroll = strip.testing_scrollView
        let overflows = scroll.contentSize.width > scroll.bounds.width + 0.5
        XCTAssertTrue(overflows, "fixture must overflow so trailing fade can appear")
        XCTAssertTrue(strip.testing_trailingFadeActive)
        XCTAssertFalse(strip.testing_leadingFadeActive)

        scroll.contentOffset = CGPoint(x: min(40, scroll.contentSize.width - scroll.bounds.width), y: 0)
        strip.testing_updateEdgeFadeMask()
        XCTAssertTrue(strip.testing_leadingFadeActive)
        XCTAssertTrue(strip.testing_maskIsOnContainer)
    }
}
