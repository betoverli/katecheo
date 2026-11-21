import XCTest
@testable import Katecheo

/// Apple Notes–style floating format toolbar: capsule chrome, scroll-inside, title hide.
@MainActor
final class NativeNoteEditorAccessoryBarTests: XCTestCase {
    private var editor: NativeNoteEditorView!
    private var hostWindow: UIWindow?
    private let speakers: [NativeAPIClient.SpeakerDTO] = [
        .init(id: "s1", name: "Ana", color: "#5B8DEF", updatedAt: "2024-01-01T00:00:00.000Z"),
    ]

    override func setUp() async throws {
        try await super.setUp()
        editor = NativeNoteEditorView(frame: CGRect(x: 0, y: 0, width: 390, height: 720))
        // Host in a window so `UITextView.becomeFirstResponder` works — the format
        // toolbar chrome is gated on first responder (same harness as title-toolbar tests).
        let host = UIViewController()
        host.view.backgroundColor = KCDesign.canvas
        host.view.addSubview(editor)
        editor.frame = host.view.bounds
        editor.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host
        window.makeKeyAndVisible()
        hostWindow = window
        editor.testing_prepare(size: CGSize(width: 390, height: 720))
    }

    override func tearDown() async throws {
        hostWindow?.isHidden = true
        hostWindow = nil
        editor = nil
        try await super.tearDown()
    }

    func testCapsule_hasContinuousPillCornersAndClips() {
        let bar = NoteEditorAccessoryBar()
        bar.bounds = CGRect(x: 0, y: 0, width: 390, height: bar.intrinsicContentSize.height)
        bar.layoutIfNeeded()

        XCTAssertTrue(bar.testing_capsuleClipsToBounds, "icons must clip inside the capsule ends")
        XCTAssertEqual(bar.testing_capsule.layer.cornerCurve, .continuous)

        let height = bar.testing_capsule.bounds.height
        XCTAssertGreaterThan(height, 40)
        // Pill: corner radius ≈ half the capsule height (large continuous ends).
        XCTAssertEqual(bar.testing_capsuleCornerRadius, height / 2, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(bar.testing_capsuleCornerRadius, 20)
    }

    func testCapsule_isInsetFromScreenEdges() {
        let bar = NoteEditorAccessoryBar()
        bar.bounds = CGRect(x: 0, y: 0, width: 390, height: bar.intrinsicContentSize.height)
        bar.layoutIfNeeded()

        let inset = bar.testing_capsuleHorizontalInset
        XCTAssertGreaterThanOrEqual(inset, 12)
        XCTAssertLessThanOrEqual(inset, 16)

        let capsuleFrame = bar.testing_shadowHost.frame
        XCTAssertEqual(capsuleFrame.minX, inset, accuracy: 0.5)
        XCTAssertEqual(capsuleFrame.maxX, 390 - inset, accuracy: 0.5)
        XCTAssertGreaterThan(capsuleFrame.minY, 0, "capsule sits above the accessory bottom / keyboard")
        XCTAssertLessThan(capsuleFrame.maxY, bar.bounds.maxY, "breathing room above the keyboard")
    }

    func testCapsule_hostBackgroundIsTransparent() {
        let bar = NoteEditorAccessoryBar()
        XCTAssertTrue(
            bar.testing_hostBackgroundIsClear,
            "no full-width bar strip behind the floating capsule"
        )
        XCTAssertFalse(bar.isOpaque)
    }

    func testCapsule_scrollViewContentWiderThanBounds() {
        let bar = NoteEditorAccessoryBar()
        // Narrow phone width so the many format buttons overflow the capsule.
        bar.bounds = CGRect(x: 0, y: 0, width: 320, height: bar.intrinsicContentSize.height)
        bar.layoutIfNeeded()

        let scroll = bar.testing_scrollView
        XCTAssertTrue(scroll.isDescendant(of: bar.testing_capsule))
        XCTAssertGreaterThan(
            scroll.contentSize.width,
            scroll.bounds.width,
            "icons must scroll horizontally inside the capsule (content=\(scroll.contentSize.width) bounds=\(scroll.bounds.width))"
        )
        XCTAssertFalse(scroll.showsHorizontalScrollIndicator)
    }

    func testCapsule_buttonsMeetMinimumTapTarget() {
        let bar = NoteEditorAccessoryBar()
        bar.bounds = CGRect(x: 0, y: 0, width: 390, height: bar.intrinsicContentSize.height)
        bar.layoutIfNeeded()

        let buttons = bar.testing_scrollView.subviews
            .flatMap { ($0 as? UIStackView)?.arrangedSubviews ?? [] }
            .compactMap { $0 as? UIButton }
        XCTAssertFalse(buttons.isEmpty)
        for button in buttons {
            XCTAssertGreaterThanOrEqual(button.bounds.width, 44, button.accessibilityLabel ?? "?")
            XCTAssertGreaterThanOrEqual(button.bounds.height, 44, button.accessibilityLabel ?? "?")
        }
    }

    func testFormattingToolbar_hiddenInTitle_shownInBody() {
        var note = NativeAPIClient.emptyNote(id: "note-capsule-title")
        note.title = "Culto"
        note.body.blocks = [
            NativeAPIClient.LineBlock(
                id: "p1",
                type: "paragraph",
                spans: [.init(type: "text", text: "corpo", marks: nil, bookId: nil, chapter: nil, verseStart: nil, verseEnd: nil, href: nil)],
                speakerId: nil,
                title: nil,
                collapsed: nil,
                checked: nil,
                blocks: nil
            ),
        ]
        editor.pushNote(note, speakers: speakers)
        XCTAssertTrue(
            editor.testing_becomeFirstResponder(),
            "editor must accept first responder so chrome can attach the capsule accessory"
        )

        editor.testing_setSelectedRange(NSRange(location: 0, length: 0))
        XCTAssertFalse(
            editor.testing_isFormattingToolbarVisible(),
            "toolbar must stay hidden while the caret is in the note title"
        )

        let storage = editor.testing_textStorage()
        editor.testing_setSelectedRange(NSRange(location: storage.length, length: 0))
        XCTAssertTrue(
            editor.testing_isFormattingToolbarVisible(),
            "toolbar appears once the caret is in the note body"
        )
    }
}
