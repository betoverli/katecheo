import XCTest
@testable import Katecheo

/// Real UITextView coverage for TestFlight 214 (tab-bar scroll + speaker header appearance).
@MainActor
final class NativeNoteEditorTF214Tests: XCTestCase {
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
        editor = NativeNoteEditorView(frame: .zero)
        editor.testing_prepare()
    }

    override func tearDown() async throws {
        editor = nil
        try await super.tearDown()
    }

    func testSpeakerHeader_resolvesDynamicColorsForLightAndDark() {
        let attachment = SpeakerHeaderAttachment(
            blockId: "hdr",
            speakerId: "sp1",
            speakerName: "João Bium",
            colorHex: "#C4A574",
            collapsed: false
        )

        let light = UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: .light),
            UITraitCollection(displayScale: 2),
        ])
        attachment.refreshImage(width: 320, traits: light)
        guard let lightLuma = attachment.testing_namePixelLuminance() else {
            return XCTFail("missing light pixels")
        }
        XCTAssertLessThan(lightLuma, 0.45, "light mode name must be dark (got \(lightLuma))")
        XCTAssertEqual(attachment.renderedInterfaceStyle, .light)

        let dark = UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: .dark),
            UITraitCollection(displayScale: 2),
        ])
        attachment.refreshImage(width: 320, traits: dark)
        guard let darkLuma = attachment.testing_namePixelLuminance() else {
            return XCTFail("missing dark pixels")
        }
        XCTAssertGreaterThan(darkLuma, 0.55, "dark mode name must be light (got \(darkLuma))")
        XCTAssertEqual(attachment.renderedInterfaceStyle, .dark)
        XCTAssertGreaterThan(darkLuma - lightLuma, 0.2, "light/dark name contrast must flip")
    }

    func testSpeakerHeader_reopenInLightModeKeepsReadableName() {
        // Simulate bake under dark traits, then reopen path refreshing for light (TF214 screenshot).
        var note = NativeAPIClient.emptyNote(id: "note-tf214-speaker")
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

        editor.overrideUserInterfaceStyle = .dark
        editor.pushNote(note, speakers: speakers)
        guard let headerRange = SpeakerSectionEditing.findSpeakerHeaderRange(in: editor.testing_textStorage()),
              let header = editor.testing_headerAttachment(at: headerRange.location)
        else {
            return XCTFail("missing speaker header on load")
        }
        header.refreshImage(width: max(header.image?.size.width ?? 320, 320), traits: UITraitCollection(userInterfaceStyle: .dark))
        XCTAssertEqual(header.renderedInterfaceStyle, .dark)

        // Leave + reopen in light: pushNote + trait refresh must re-bake readable name.
        editor.overrideUserInterfaceStyle = .light
        editor.pushNote(note, speakers: speakers)
        editor.testing_refreshSpeakerHeaderAppearances()

        guard let refreshed = editor.testing_headerAttachment(at: headerRange.location),
              let luma = refreshed.testing_namePixelLuminance()
        else {
            return XCTFail("header missing after light reopen")
        }
        XCTAssertEqual(refreshed.renderedInterfaceStyle, .light)
        XCTAssertLessThan(luma, 0.45, "after light reopen, name must not stay white (luma=\(luma))")
    }
}
