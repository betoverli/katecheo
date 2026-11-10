import XCTest
@testable import Katecheo

/// Real UITextView coverage for TestFlight 219 (Appearance at launch + speaker name light palette).
@MainActor
final class NativeNoteEditorTF219Tests: XCTestCase {
    private var editor: NativeNoteEditorView!
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
        editor.testing_prepare()
    }

    override func tearDown() async throws {
        AppAppearance.setTheme("system")
        editor = nil
        try await super.tearDown()
    }

    func testAppearance_lightOverrideSurvivesColdLaunchStyle() {
        AppAppearance.setTheme("light")
        XCTAssertEqual(AppAppearance.storedTheme, "light")
        XCTAssertEqual(AppAppearance.style(forTheme: AppAppearance.storedTheme), .light)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        // Simulate SceneDelegate before first frame.
        AppAppearance.apply(to: window)
        XCTAssertEqual(window.overrideUserInterfaceStyle, .light)

        // System may be dark; app override must still force light on every paint.
        window.overrideUserInterfaceStyle = .unspecified
        AppAppearance.apply(to: window)
        XCTAssertEqual(window.overrideUserInterfaceStyle, .light)
    }

    func testAppearance_darkOverrideAgainstSystemLight() {
        AppAppearance.setTheme("dark")
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        AppAppearance.apply(to: window)
        XCTAssertEqual(window.overrideUserInterfaceStyle, .dark)
        XCTAssertEqual(AppAppearance.style(forTheme: "dark"), .dark)
        XCTAssertEqual(AppAppearance.style(forTheme: "light"), .light)
        XCTAssertEqual(AppAppearance.style(forTheme: "system"), .unspecified)
    }

    func testSpeakerHeader_lightAppOverrideMatchesLightPaletteOnUITextView() {
        // Bug: system Dark + app Light left "João Bium" white on beige until Appearance back.
        AppAppearance.setTheme("light")

        let host = UIViewController()
        host.view.backgroundColor = .systemBackground
        host.view.addSubview(editor)
        editor.frame = host.view.bounds
        editor.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        AppAppearance.apply(to: window)
        window.rootViewController = host
        window.makeKeyAndVisible()
        AppAppearance.apply(to: window)

        // Force a second paint as if system were dark but app override is light.
        window.overrideUserInterfaceStyle = .light
        host.overrideUserInterfaceStyle = .light
        editor.overrideUserInterfaceStyle = .light

        var note = NativeAPIClient.emptyNote(id: "note-tf219-speaker")
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

        editor.pushNote(note, speakers: speakers)
        editor.layoutIfNeeded()
        editor.testing_refreshSpeakerHeaderAppearances()

        guard let headerRange = SpeakerSectionEditing.findSpeakerHeaderRange(in: editor.testing_textStorage()),
              let header = editor.testing_headerAttachment(at: headerRange.location),
              let luma = header.testing_namePixelLuminance()
        else {
            return XCTFail("missing speaker header on real UITextView path")
        }

        XCTAssertEqual(header.renderedInterfaceStyle, .light)
        // Light palette label is near-black; white-on-beige would be ~0.95+.
        XCTAssertLessThan(luma, 0.45, "app Light override must bake dark name (luma=\(luma))")

        // Leave + reopen without visiting Appearance — still light palette.
        editor.pushNote(note, speakers: speakers)
        editor.testing_refreshSpeakerHeaderAppearances()
        guard let again = editor.testing_headerAttachment(at: headerRange.location),
              let luma2 = again.testing_namePixelLuminance()
        else {
            return XCTFail("header missing after reopen")
        }
        XCTAssertEqual(again.renderedInterfaceStyle, .light)
        XCTAssertLessThan(luma2, 0.45, "reopen must keep dark name under Light override (luma=\(luma2))")

        window.isHidden = true
    }

    func testSpeakerHeader_hardPaletteSurvivesAmbientDarkTraits() {
        // Hard RGB palette + explicit light traits must ignore ambient Dark.
        let attachment = SpeakerHeaderAttachment(
            blockId: "hdr",
            speakerId: "sp1",
            speakerName: "João Bium",
            colorHex: "#C4A574",
            collapsed: false
        )
        let ambientDark = UITraitCollection(userInterfaceStyle: .dark)
        let light = SpeakerHeaderAttachment.bakeTraits(style: .light, scale: 3)
        ambientDark.performAsCurrent {
            attachment.refreshImage(width: 320, traits: light)
        }
        guard let luma = attachment.testing_namePixelLuminance() else {
            return XCTFail("missing pixels")
        }
        XCTAssertEqual(attachment.renderedInterfaceStyle, .light)
        XCTAssertLessThan(luma, 0.45, "hard palette bake must ignore ambient dark (luma=\(luma))")
    }
}
