import XCTest
@testable import Katecheo

/// Regression: after background snapshots / Bible-app return, title + speaker header colors
/// must re-resolve for the live `userInterfaceStyle` (never keep a once-resolved CGColor).
@MainActor
final class NativeNoteEditorTitleAppearanceTests: XCTestCase {
    private var editor: NativeNoteEditorView!
    private var hostWindow: UIWindow?
    private let speakers = [
        NativeAPIClient.SpeakerDTO(
            id: "sp1",
            name: "João Bium",
            color: "#C4A574",
            updatedAt: "2026-01-01T00:00:00Z"
        ),
    ]

    override func setUp() async throws {
        try await super.setUp()
        editor = NativeNoteEditorView(frame: CGRect(x: 0, y: 0, width: 390, height: 720))
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
        AppAppearance.setTheme("system")
        hostWindow?.isHidden = true
        hostWindow = nil
        editor = nil
        try await super.tearDown()
    }

    private func noteWithTitleAndSpeaker() -> NativeAPIClient.NoteDocument {
        var note = NativeAPIClient.emptyNote(id: "note-title-appearance")
        note.title = "Encontro Inglaterra"
        note.body.blocks = [
            NativeAPIClient.LineBlock(
                id: "sec1",
                type: "speakerSection",
                spans: nil,
                speakerId: "sp1",
                title: "João Bium",
                collapsed: nil,
                checked: nil,
                blocks: [
                    NativeAPIClient.LineBlock(
                        id: "body1",
                        type: "paragraph",
                        spans: [.init(type: "text", text: "nota", marks: nil, bookId: nil, chapter: nil, verseStart: nil, verseEnd: nil, href: nil)],
                        speakerId: nil,
                        title: nil,
                        collapsed: nil,
                        checked: nil,
                        blocks: nil
                    ),
                ]
            ),
        ]
        return note
    }

    private func luma(_ color: UIColor) -> CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        XCTAssertTrue(color.getRed(&r, green: &g, blue: &b, alpha: &a))
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    func testTitleColor_resolvesCorrectlyWhenUserInterfaceStyleToggles() {
        let note = noteWithTitleAndSpeaker()
        hostWindow?.overrideUserInterfaceStyle = .light
        editor.overrideUserInterfaceStyle = .light
        editor.pushNote(note, speakers: speakers)
        editor.testing_refreshAppearanceForCurrentTraits()

        let lightTraits = UITraitCollection(userInterfaceStyle: .light)
        guard let lightTitle = editor.testing_titleForegroundColor(traits: lightTraits) else {
            return XCTFail("missing title foreground in light")
        }
        let lightLuma = luma(lightTitle)
        XCTAssertLessThan(lightLuma, 0.45, "light mode title must resolve dark (luma=\(lightLuma))")

        // Simulate the background snapshot flip to dark, then return.
        hostWindow?.overrideUserInterfaceStyle = .dark
        editor.overrideUserInterfaceStyle = .dark
        editor.testing_refreshAppearanceForCurrentTraits()

        let darkTraits = UITraitCollection(userInterfaceStyle: .dark)
        guard let darkTitle = editor.testing_titleForegroundColor(traits: darkTraits) else {
            return XCTFail("missing title foreground in dark")
        }
        let darkLuma = luma(darkTitle)
        XCTAssertGreaterThan(darkLuma, 0.55, "dark mode title must resolve light (luma=\(darkLuma))")
        XCTAssertGreaterThan(darkLuma - lightLuma, 0.2, "title contrast must flip with style")

        // Return to light (Bible-app round-trip) — must not keep the dark-resolved color.
        hostWindow?.overrideUserInterfaceStyle = .light
        editor.overrideUserInterfaceStyle = .light
        editor.testing_refreshAppearanceForCurrentTraits()

        guard let restored = editor.testing_titleForegroundColor(traits: lightTraits) else {
            return XCTFail("missing title foreground after restore")
        }
        let restoredLuma = luma(restored)
        XCTAssertLessThan(restoredLuma, 0.45, "after returning to light, title must be dark again (luma=\(restoredLuma))")

        // Speaker header bake must also follow the final light style.
        guard let headerRange = SpeakerSectionEditing.findSpeakerHeaderRange(in: editor.testing_textStorage()),
              let header = editor.testing_headerAttachment(at: headerRange.location),
              let headerLuma = header.testing_namePixelLuminance()
        else {
            return XCTFail("missing speaker header after style restore")
        }
        XCTAssertEqual(header.renderedInterfaceStyle, .light)
        XCTAssertLessThan(headerLuma, 0.45, "speaker header name must be readable on light canvas (luma=\(headerLuma))")
    }

    /// Inserting a speaker while already in dark mode must bake a light name immediately
    /// (not wait for leave/reopen → pushNote refresh).
    func testInsertSpeaker_inDarkMode_bakesLightNameImmediately() {
        // Real device path: system Appearance + Dark override on the window/view hierarchy
        // (not AppAppearance.setTheme("dark") — that would hide trait-propagation bugs).
        AppAppearance.setTheme("system")
        let host = hostWindow?.rootViewController
        hostWindow?.overrideUserInterfaceStyle = .dark
        host?.overrideUserInterfaceStyle = .dark
        editor.overrideUserInterfaceStyle = .dark
        hostWindow?.layoutIfNeeded()
        editor.layoutIfNeeded()

        XCTAssertEqual(
            editor.testing_effectiveUserInterfaceStyle(),
            .dark,
            "precondition: editor must resolve Dark from the window/view hierarchy"
        )

        var blank = NativeAPIClient.emptyNote(id: "note-insert-dark-speaker")
        blank.title = "Culto"
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
        editor.testing_refreshAppearanceForCurrentTraits()

        let storage = editor.testing_textStorage()
        editor.testing_setSelectedRange(NSRange(location: storage.length, length: 0))
        editor.insertSpeakerSection(speakerId: "sp1", name: "João Bium")

        guard let headerRange = SpeakerSectionEditing.findSpeakerHeaderRange(in: editor.testing_textStorage()),
              let header = editor.testing_headerAttachment(at: headerRange.location),
              let luma = header.testing_namePixelLuminance()
        else {
            return XCTFail("missing speaker header right after insert")
        }
        XCTAssertEqual(header.renderedInterfaceStyle, .dark)
        XCTAssertGreaterThan(luma, 0.55, "inserted speaker name must be light in dark mode (luma=\(luma))")
    }

    /// Format toolbar must stay hidden for the title field even after deleting all title text.
    func testFormattingToolbar_hiddenForTitleEvenAfterClearing() {
        var note = NativeAPIClient.emptyNote(id: "note-title-toolbar")
        note.title = ""
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
        XCTAssertTrue(editor.testing_becomeFirstResponder())

        editor.testing_setSelectedRange(NSRange(location: 0, length: 0))
        // Selection change refreshes chrome — title must never show the format bar.
        XCTAssertFalse(
            editor.testing_isFormattingToolbarVisible(),
            "empty title on focus must hide the formatting toolbar"
        )

        editor.testing_insertText("Culto")
        XCTAssertFalse(
            editor.testing_isFormattingToolbarVisible(),
            "typed title must keep the formatting toolbar hidden"
        )

        // Delete every title character (including any ZWSP seed).
        for _ in 0..<12 {
            let storage = editor.testing_textStorage()
            let titlePara = (storage.string as NSString).paragraphRange(for: NSRange(location: 0, length: 0))
            let terminator: Int = {
                guard titlePara.length > 0 else { return 0 }
                let last = (storage.string as NSString).substring(
                    with: NSRange(location: NSMaxRange(titlePara) - 1, length: 1)
                )
                return (last == "\n" || last == "\r") ? 1 : 0
            }()
            let contentLen = titlePara.length - terminator
            guard contentLen > 0 else { break }
            editor.testing_setSelectedRange(NSRange(location: contentLen, length: 0))
            editor.testing_deleteBackward()
        }

        XCTAssertTrue(editor.testing_titlePlaceholderVisible())
        XCTAssertFalse(
            editor.testing_isFormattingToolbarVisible(),
            "cleared title must still hide the formatting toolbar"
        )

        // Body still shows the toolbar.
        let storage = editor.testing_textStorage()
        editor.testing_setSelectedRange(NSRange(location: storage.length, length: 0))
        XCTAssertTrue(
            editor.testing_isFormattingToolbarVisible(),
            "body caret must still show the formatting toolbar"
        )
    }
}
