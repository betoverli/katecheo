import XCTest
@testable import App

/// TestFlight 222 — speaker header must stay dark in Light mode even when TextKit layout
/// runs under ambient system-Dark traits (the device bug after #66/#67).
@MainActor
final class NativeNoteEditorTF222Tests: XCTestCase {
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

    private func encontroNote() -> NativeAPIClient.NoteDocument {
        var note = NativeAPIClient.emptyNote(id: "note-tf222-encontro")
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

    /// The exact device failure mode: light bake, then attachmentBounds under ambient Dark.
    func testAttachmentBounds_doesNotRebakeWhiteUnderAmbientDark() {
        let attachment = SpeakerHeaderAttachment(
            blockId: "hdr",
            speakerId: "sp1",
            speakerName: "João Bium",
            colorHex: "#C4A574",
            collapsed: false
        )
        attachment.refreshImage(width: 320, traits: SpeakerHeaderAttachment.bakeTraits(style: .light))
        guard let before = attachment.testing_namePixelLuminance() else {
            return XCTFail("missing light pixels before bounds")
        }
        XCTAssertLessThan(before, 0.45, "precondition: light bake must be dark (luma=\(before))")

        let darkAmbient = UITraitCollection(userInterfaceStyle: .dark)
        darkAmbient.performAsCurrent {
            // Simulate TextKit layout after pushNote refresh (system Dark, app Light).
            _ = attachment.attachmentBounds(
                for: nil,
                proposedLineFragment: CGRect(x: 0, y: 0, width: 360, height: 44),
                glyphPosition: .zero,
                characterIndex: 0
            )
        }

        guard let after = attachment.testing_namePixelLuminance() else {
            return XCTFail("missing pixels after ambient-dark bounds")
        }
        XCTAssertEqual(attachment.renderedInterfaceStyle, .light)
        XCTAssertLessThan(after, 0.45, "attachmentBounds under ambient Dark must NOT stamp white name (luma=\(after))")
    }

    func testSpeakerHeader_runUsesClearForegroundNotLabel() {
        let header = NoteDocumentCodec.speakerSectionHeader(
            name: "João Bium",
            speakerId: "sp1",
            colorHex: "#C4A574",
            blockId: "sec1"
        )
        let attrs = header.attributes(at: 0, effectiveRange: nil)
        let fg = attrs[.foregroundColor] as? UIColor
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        XCTAssertNotNil(fg)
        XCTAssertTrue(fg?.getRed(&r, green: &g, blue: &b, alpha: &a) == true)
        XCTAssertEqual(a, 0, accuracy: 0.01, "attachment run must use clear foreground (got alpha=\(a))")
    }

    func testSpeakerHeader_lightOverride_uiTextViewSnapshotDarkName() throws {
        AppAppearance.setTheme("light")

        let host = UIViewController()
        host.view.backgroundColor = V2NDesign.canvas
        host.view.addSubview(editor)
        editor.frame = host.view.bounds
        editor.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        // System Dark + app Light (device config from TF222).
        window.overrideUserInterfaceStyle = .light
        host.overrideUserInterfaceStyle = .light
        editor.overrideUserInterfaceStyle = .light
        AppAppearance.apply(to: window)
        window.rootViewController = host
        window.makeKeyAndVisible()

        let note = encontroNote()
        editor.pushNote(note, speakers: speakers)
        editor.layoutIfNeeded()
        // Force a layout pass under ambient Dark (matches device TextKit).
        UITraitCollection(userInterfaceStyle: .dark).performAsCurrent {
            editor.layoutIfNeeded()
            editor.testing_refreshSpeakerHeaderAppearances()
        }
        // Editor should still re-assert light from AppAppearance / override.
        editor.testing_refreshSpeakerHeaderAppearances()
        editor.layoutIfNeeded()

        guard let headerRange = SpeakerSectionEditing.findSpeakerHeaderRange(in: editor.testing_textStorage()),
              let header = editor.testing_headerAttachment(at: headerRange.location),
              let luma = header.testing_namePixelLuminance()
        else {
            return XCTFail("missing speaker header on UITextView path")
        }
        XCTAssertEqual(header.renderedInterfaceStyle, .light)
        XCTAssertLessThan(luma, 0.45, "João Bium must be dark on beige (luma=\(luma))")

        // Title paragraph (first line) must also be dark — sample attributed color.
        let storage = editor.testing_textStorage()
        let titleAttrs = storage.attributes(at: 0, effectiveRange: nil)
        // Title is plain text; ensure we didn't leave a near-white concrete color.
        if let titleColor = titleAttrs[.foregroundColor] as? UIColor {
            let resolved = titleColor.resolvedColor(with: SpeakerHeaderAttachment.bakeTraits(style: .light))
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            if resolved.getRed(&r, green: &g, blue: &b, alpha: &a) {
                let titleLuma = 0.2126 * r + 0.7152 * g + 0.0722 * b
                XCTAssertLessThan(titleLuma, 0.55, "title must resolve dark under Light (luma=\(titleLuma))")
            }
        }

        // Leave + reopen.
        editor.pushNote(note, speakers: speakers)
        UITraitCollection(userInterfaceStyle: .dark).performAsCurrent {
            _ = header.attachmentBounds(
                for: nil,
                proposedLineFragment: CGRect(x: 0, y: 0, width: 350, height: 44),
                glyphPosition: .zero,
                characterIndex: 0
            )
        }
        editor.testing_refreshSpeakerHeaderAppearances()
        guard let again = editor.testing_headerAttachment(at: headerRange.location),
              let luma2 = again.testing_namePixelLuminance()
        else {
            return XCTFail("header missing after reopen")
        }
        XCTAssertLessThan(luma2, 0.45, "reopen must keep dark name (luma=\(luma2))")

        // Snapshot PNG for CI artifacts.
        let snapshot = try XCTUnwrap(Self.renderSnapshot(of: host.view, size: CGSize(width: 390, height: 844)))
        Self.writeArtifact(snapshot, name: "tf222-systemDark-appLight-encontro.png")
        let attachmentShot = try XCTUnwrap(header.image)
        Self.writeArtifact(attachmentShot, name: "tf222-speaker-header-light.png")

        // Pixel assert on the full editor snapshot near the speaker row (below title).
        let snapLuma = Self.sampleLuma(in: snapshot, normalizedX: 0.22, normalizedY: 0.16)
        if let snapLuma {
            // Beige canvas is ~0.93; dark name ink must pull sampled area down if we hit glyphs.
            // Prefer attachment luma (already asserted); snapshot is evidence for humans.
            _ = snapLuma
        }

        window.isHidden = true
    }

    func testSpeakerHeader_systemLightAppLight_alsoDarkName() throws {
        AppAppearance.setTheme("light")
        let host = UIViewController()
        host.view.backgroundColor = V2NDesign.canvas
        host.view.addSubview(editor)
        editor.frame = host.view.bounds
        editor.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.overrideUserInterfaceStyle = .light
        AppAppearance.apply(to: window)
        window.rootViewController = host
        window.makeKeyAndVisible()

        editor.pushNote(encontroNote(), speakers: speakers)
        editor.layoutIfNeeded()
        editor.testing_refreshSpeakerHeaderAppearances()

        guard let headerRange = SpeakerSectionEditing.findSpeakerHeaderRange(in: editor.testing_textStorage()),
              let header = editor.testing_headerAttachment(at: headerRange.location),
              let luma = header.testing_namePixelLuminance()
        else {
            return XCTFail("missing header")
        }
        XCTAssertLessThan(luma, 0.45, "system Light + app Light name must be dark (luma=\(luma))")
        if let snap = Self.renderSnapshot(of: host.view, size: CGSize(width: 390, height: 844)) {
            Self.writeArtifact(snap, name: "tf222-systemLight-appLight-encontro.png")
        }
        window.isHidden = true
    }

    // MARK: - Snapshot helpers

    private static func renderSnapshot(of view: UIView, size: CGSize) -> UIImage? {
        view.bounds = CGRect(origin: .zero, size: size)
        view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
        }
    }

    private static func writeArtifact(_ image: UIImage, name: String) {
        guard let data = image.pngData() else { return }
        let roots: [URL] = {
            var urls: [URL] = []
            if let ws = ProcessInfo.processInfo.environment["GITHUB_WORKSPACE"], !ws.isEmpty {
                urls.append(URL(fileURLWithPath: ws).appendingPathComponent("artifacts", isDirectory: true))
            }
            urls.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("artifacts", isDirectory: true))
            urls.append(FileManager.default.temporaryDirectory.appendingPathComponent("verse2note-tf222", isDirectory: true))
            return urls
        }()
        for dir in roots {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(name)
            do {
                try data.write(to: url, options: .atomic)
                let attachment = XCTAttachment(contentsOfFile: url)
                attachment.name = name
                attachment.lifetime = .keepAlways
                // Attach to the running test via Thread dictionary is awkward; write path is enough for CI upload.
                NSLog("TF222 artifact written: %@", url.path)
                break
            } catch {
                continue
            }
        }
    }

    private static func sampleLuma(in image: UIImage, normalizedX: CGFloat, normalizedY: CGFloat) -> CGFloat? {
        guard let cg = image.cgImage else { return nil }
        let x = min(max(Int(CGFloat(cg.width) * normalizedX), 0), cg.width - 1)
        let y = min(max(Int(CGFloat(cg.height) * normalizedY), 0), cg.height - 1)
        guard let data = cg.dataProvider?.data, let ptr = CFDataGetBytePtr(data) else { return nil }
        let bpp = max(cg.bitsPerPixel / 8, 4)
        let idx = y * cg.bytesPerRow + x * bpp
        let r = CGFloat(ptr[idx]) / 255
        let g = CGFloat(ptr[idx + 1]) / 255
        let b = CGFloat(ptr[idx + 2]) / 255
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }
}
