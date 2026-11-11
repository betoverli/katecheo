import XCTest
@testable import Katecheo

/// Regression for the note-editor Enter/Backspace scroll jump: with a keyboard+accessory
/// bottom inset, `UITextView.scrollRangeToVisible` pinned the caret line to the top of
/// the viewport and left a blank gap above the toolbar.
@MainActor
final class NativeNoteEditorCaretScrollTests: XCTestCase {
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

    // MARK: - Pure offset math

    func testCaretAlreadyVisible_preservesOffset() {
        let caret = CGRect(x: 20, y: 200, width: 2, height: 22)
        let y = NoteEditorCaretScroll.contentOffsetY(
            caretRectInBounds: caret,
            boundsHeight: 720,
            contentInset: UIEdgeInsets(top: 0, left: 0, bottom: 360, right: 0),
            contentSizeHeight: 1400,
            currentOffsetY: 400
        )
        XCTAssertEqual(y, 400, accuracy: 0.5, "already-visible caret must not move offset")
    }

    func testCaretBelowVisibleBand_scrollsMinimumDown() {
        // Visible band with 360pt bottom inset on 720pt bounds: y 0…360.
        let caret = CGRect(x: 20, y: 380, width: 2, height: 22)
        let y = NoteEditorCaretScroll.contentOffsetY(
            caretRectInBounds: caret,
            boundsHeight: 720,
            contentInset: UIEdgeInsets(top: 0, left: 0, bottom: 360, right: 0),
            contentSizeHeight: 2000,
            currentOffsetY: 500
        )
        // caretBottom 402, visibleBottom 720-360-4=356 → delta +46 → 546
        XCTAssertEqual(y, 546, accuracy: 1.0)
    }

    func testCaretAboveVisibleBand_scrollsMinimumUp() {
        let caret = CGRect(x: 20, y: -40, width: 2, height: 22)
        let y = NoteEditorCaretScroll.contentOffsetY(
            caretRectInBounds: caret,
            boundsHeight: 720,
            contentInset: UIEdgeInsets(top: 0, left: 0, bottom: 360, right: 0),
            contentSizeHeight: 2000,
            currentOffsetY: 800
        )
        // caretTop -40, visibleTop 4 → delta -44 → 756
        XCTAssertEqual(y, 756, accuracy: 1.0)
    }

    func testNeverPinsToTopWhenContentFitsAboveKeyboard() {
        // Short note + large keyboard inset: maxOffset is near 0. A "pin to top"
        // jump would set a large positive offset and leave a blank gap — clamp forbids it.
        let caret = CGRect(x: 20, y: 280, width: 2, height: 22)
        let y = NoteEditorCaretScroll.contentOffsetY(
            caretRectInBounds: caret,
            boundsHeight: 720,
            contentInset: UIEdgeInsets(top: 0, left: 0, bottom: 360, right: 0),
            contentSizeHeight: 420,
            currentOffsetY: 0
        )
        XCTAssertEqual(y, 0, accuracy: 0.5)
        XCTAssertLessThanOrEqual(y, 60, "must not jump contentOffset into a blank gap")
    }

    func testClampAfterContentShrink_dropsOversizedOffset() {
        // After Backspace shrinks content, an oversized offset must clamp down —
        // not stay huge (blank gap under the last line).
        let caret = CGRect(x: 20, y: 40, width: 2, height: 22)
        let y = NoteEditorCaretScroll.contentOffsetY(
            caretRectInBounds: caret,
            boundsHeight: 720,
            contentInset: UIEdgeInsets(top: 0, left: 0, bottom: 360, right: 0),
            contentSizeHeight: 500,
            currentOffsetY: 480
        )
        let maxOffset = max(CGFloat(0), CGFloat(500 - 720 + 360)) // 140
        XCTAssertEqual(y, maxOffset, accuracy: 0.5)
        XCTAssertLessThan(y, 200)
    }

    // MARK: - Real UITextView Enter / Backspace path

    func testEnterBackspaceOnLongList_doesNotJumpOffsetOrLeaveGap() {
        var note = NativeAPIClient.emptyNote(id: "note-caret-scroll")
        note.title = "Encontro Inglaterra"
        var blocks: [NativeAPIClient.LineBlock] = []
        for i in 1 ... 28 {
            blocks.append(
                NativeAPIClient.LineBlock(
                    id: "b\(i)",
                    type: "bullet",
                    spans: [
                        .init(
                            type: "text",
                            text: "Linha de lista \(i) — texto suficiente para ocupar o corpo e forçar scroll.",
                            marks: nil,
                            bookId: nil,
                            chapter: nil,
                            verseStart: nil,
                            verseEnd: nil,
                            href: nil
                        ),
                    ],
                    speakerId: nil,
                    title: nil,
                    collapsed: nil,
                    checked: nil,
                    blocks: nil
                )
            )
        }
        note.body.blocks = blocks
        editor.pushNote(note, speakers: [])
        editor.layoutIfNeeded()

        // Keyboard + formatting toolbar overlap (~336 + accessory pad).
        editor.testing_setKeyboardBottomInset(336)
        editor.testing_forceCaretScroll = true

        let storage = editor.testing_textStorage()
        editor.testing_setSelectedRange(NSRange(location: storage.length, length: 0))

        let contentH = editor.testing_contentSize().height
        let boundsH = editor.testing_boundsHeight()
        let bottomInset = editor.testing_contentInset().bottom
        let maxOffset = max(0, contentH - boundsH + bottomInset)
        // Park near the end so the last bullet sits above the keyboard (not pinned to top).
        let parked = max(0, maxOffset - 24)
        editor.testing_setContentOffset(CGPoint(x: 0, y: parked))
        editor.testing_scrollCaretVisible(animated: false)

        let before = editor.testing_contentOffset().y
        XCTAssertGreaterThan(before, 80, "list must be scrolled; offset=\(before) max=\(maxOffset)")

        // Enter → new bullet (same path as the recording).
        editor.testing_insertText("\n")
        editor.testing_scrollCaretVisible(animated: false)
        let afterEnter = editor.testing_contentOffset().y
        assertNoTopPinJump(from: before, to: afterEnter, boundsHeight: boundsH, label: "Enter")
        assertCaretVisibleAboveKeyboard(label: "after Enter")
        assertPrecedingLineStillVisible(label: "after Enter")

        // Backspace #1 → remove empty bullet / demote.
        editor.testing_deleteBackward()
        editor.testing_scrollCaretVisible(animated: false)
        let afterBS1 = editor.testing_contentOffset().y
        assertNoTopPinJump(from: afterEnter, to: afterBS1, boundsHeight: boundsH, label: "Backspace#1")
        assertCaretVisibleAboveKeyboard(label: "after Backspace#1")

        // Backspace #2 → join previous line (the jump in the recording).
        editor.testing_deleteBackward()
        editor.testing_scrollCaretVisible(animated: false)
        let afterBS2 = editor.testing_contentOffset().y
        assertNoTopPinJump(from: afterBS1, to: afterBS2, boundsHeight: boundsH, label: "Backspace#2")
        assertCaretVisibleAboveKeyboard(label: "after Backspace#2")
        assertPrecedingLineStillVisible(label: "after Backspace#2")
        assertNoLargeBlankGap(label: "after Backspace#2")

        // Enter again after settling — must not jump either.
        let settled = editor.testing_contentOffset().y
        editor.testing_insertText("\n")
        editor.testing_scrollCaretVisible(animated: false)
        let afterEnter2 = editor.testing_contentOffset().y
        assertNoTopPinJump(from: settled, to: afterEnter2, boundsHeight: boundsH, label: "Enter#2")
        assertCaretVisibleAboveKeyboard(label: "after Enter#2")
        assertNoLargeBlankGap(label: "after Enter#2")
    }

    // MARK: - Assertions

    private func assertNoTopPinJump(
        from previous: CGFloat,
        to next: CGFloat,
        boundsHeight: CGFloat,
        label: String
    ) {
        let delta = abs(next - previous)
        // A top-pin jump moves by roughly a full visible band (~half the bounds with keyboard).
        let jumpThreshold = boundsHeight * 0.35
        XCTAssertLessThan(
            delta,
            jumpThreshold,
            "\(label): contentOffset jumped \(delta) (from \(previous) to \(next)); caret must not pin to top"
        )
    }

    private func assertCaretVisibleAboveKeyboard(label: String) {
        let caret = editor.testing_caretRectInBounds()
        XCTAssertFalse(caret.isNull, "\(label): missing caret rect")
        let inset = editor.testing_contentInset()
        let boundsH = editor.testing_boundsHeight()
        let visibleTop = inset.top + 2
        let visibleBottom = boundsH - inset.bottom - 2
        XCTAssertGreaterThanOrEqual(
            caret.minY,
            visibleTop - 1,
            "\(label): caret above visible band (y=\(caret.minY))"
        )
        XCTAssertLessThanOrEqual(
            caret.maxY,
            visibleBottom + 1,
            "\(label): caret under keyboard/toolbar (maxY=\(caret.maxY) visibleBottom=\(visibleBottom))"
        )
    }

    private func assertPrecedingLineStillVisible(label: String) {
        // If the caret line were pinned to the top, the preceding line would sit
        // above the visible band (negative y). Require room for ~one line above.
        let caret = editor.testing_caretRectInBounds()
        let inset = editor.testing_contentInset()
        XCTAssertGreaterThan(
            caret.minY - inset.top,
            18,
            "\(label): preceding line scrolled off; caret pinned near top (y=\(caret.minY))"
        )
    }

    private func assertNoLargeBlankGap(label: String) {
        let caret = editor.testing_caretRectInBounds()
        let inset = editor.testing_contentInset()
        let boundsH = editor.testing_boundsHeight()
        let visibleBottom = boundsH - inset.bottom
        let gapBelowCaret = visibleBottom - caret.maxY
        // With the caret near the end of a long note, gap should be small.
        // The bug left a gap of hundreds of points (half the screen).
        XCTAssertLessThan(
            gapBelowCaret,
            160,
            "\(label): large blank gap \(gapBelowCaret) between caret and toolbar"
        )
    }
}
