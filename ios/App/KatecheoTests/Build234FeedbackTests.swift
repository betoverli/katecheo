import XCTest
@testable import Katecheo

/// Build 234: note canvas nav, bible-pill ambient-Dark rebake, Profile sub-page theming.
@MainActor
final class Build234FeedbackTests: XCTestCase {
    override func tearDown() async throws {
        AppAppearance.setTheme("system")
        try await super.tearDown()
    }

    // MARK: - 1) Note editor nav = canvas

    func testNoteDetail_navMatchesEditorCanvas_lightAndDark() throws {
        for (theme, tag) in [("light", "light"), ("dark", "dark")] {
            AppAppearance.setTheme(theme)
            let style: UIUserInterfaceStyle = theme == "dark" ? .dark : .light
            let note = NativeAPIClient.emptyNote(id: "note-b234-nav-\(tag)")
            let detail = NoteDetailViewController(noteId: note.id, initial: note)
            let nav = UINavigationController(rootViewController: detail)
            KCChrome.style(navigationController: nav)

            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
            window.overrideUserInterfaceStyle = style
            AppAppearance.apply(to: window)
            window.rootViewController = nav
            window.makeKeyAndVisible()
            nav.overrideUserInterfaceStyle = style
            detail.overrideUserInterfaceStyle = style
            detail.loadViewIfNeeded()
            detail.viewWillAppear(false)
            detail.view.setNeedsLayout()
            detail.view.layoutIfNeeded()
            nav.view.layoutIfNeeded()

            let traits = UITraitCollection(userInterfaceStyle: style)
            let expected = KCDesign.canvas.resolvedColor(with: traits)
            assertColor(
                detail.view.backgroundColor?.resolvedColor(with: traits),
                equals: expected,
                label: "note view \(theme)"
            )
            assertColor(
                nav.navigationBar.standardAppearance.backgroundColor?.resolvedColor(with: traits),
                equals: expected,
                label: "note nav standard \(theme)"
            )
            assertColor(
                nav.navigationBar.scrollEdgeAppearance?.backgroundColor?.resolvedColor(with: traits),
                equals: expected,
                label: "note nav scrollEdge \(theme)"
            )
            assertColor(
                nav.navigationBar.compactAppearance?.backgroundColor?.resolvedColor(with: traits),
                equals: expected,
                label: "note nav compact \(theme)"
            )
            if let shadow = nav.navigationBar.standardAppearance.shadowColor {
                var a: CGFloat = 0
                shadow.getRed(nil, green: nil, blue: nil, alpha: &a)
                XCTAssertEqual(a, 0, accuracy: 0.01, "note nav shadow must be clear")
            }
            XCTAssertNotEqual(
                KCDesign.canvas.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)),
                KCDesign.screenBackground.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)),
                "canvas must differ from tab screenBackground (the bug being fixed)"
            )

            let snap = try XCTUnwrap(Self.render(nav.view, size: CGSize(width: 390, height: 844)))
            Self.writeArtifact(snap, name: "b234-\(tag)-note-editor.png", into: self)
            window.isHidden = true
        }
    }

    // MARK: - 2) Bible pills — no ambient-Dark rebake

    func testBiblePill_ambientDarkBoundsDoesNotFlipLightPalette() {
        AppAppearance.setTheme("light")
        let payload = NoteDocumentCodec.BibleRefPayload(
            bookId: "jhn",
            chapter: 3,
            verseStart: 16,
            verseEnd: nil,
            text: nil
        )
        let pill = BibleRefPillAttachment(
            payload: payload,
            label: "João 3:16",
            kind: .gospel
        )
        pill.refreshImage(traits: SpeakerHeaderAttachment.bakeTraits(style: .light))
        guard let before = pill.testing_averageLuminance() else {
            return XCTFail("missing light pill pixels")
        }
        XCTAssertEqual(pill.renderedInterfaceStyle, .light)

        UITraitCollection(userInterfaceStyle: .dark).performAsCurrent {
            _ = pill.attachmentBounds(
                for: nil,
                proposedLineFragment: CGRect(x: 0, y: 0, width: 200, height: 22),
                glyphPosition: .zero,
                characterIndex: 0
            )
            _ = pill.image(
                forBounds: CGRect(x: 0, y: 0, width: 80, height: 22),
                textContainer: nil,
                characterIndex: 0
            )
        }
        guard let after = pill.testing_averageLuminance() else {
            return XCTFail("missing pixels after ambient dark")
        }
        XCTAssertEqual(pill.renderedInterfaceStyle, .light)
        XCTAssertEqual(before, after, accuracy: 0.05, "ambient Dark must not rebake pill (before=\(before) after=\(after))")
    }

    func testBiblePill_uiTextView_survivesDelayedRefreshUnderAmbientDark() throws {
        AppAppearance.setTheme("light")
        var note = NativeAPIClient.emptyNote(id: "note-b234-pill")
        note.title = "Pills"
        note.body.blocks = [
            NativeAPIClient.LineBlock(
                id: "p1",
                type: "paragraph",
                spans: [
                    .init(type: "text", text: "ver ", marks: nil, bookId: nil, chapter: nil, verseStart: nil, verseEnd: nil, href: nil),
                    .init(type: "bibleRef", text: nil, marks: nil, bookId: "jhn", chapter: 3, verseStart: 16, verseEnd: nil, href: nil),
                ],
                speakerId: nil,
                title: nil,
                collapsed: nil,
                checked: nil,
                blocks: nil
            ),
        ]

        let editor = NativeNoteEditorView(frame: CGRect(x: 0, y: 0, width: 390, height: 720))
        editor.testing_prepare()
        let host = UIViewController()
        host.view.backgroundColor = KCDesign.canvas
        host.view.addSubview(editor)
        editor.frame = host.view.bounds
        editor.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.overrideUserInterfaceStyle = .light
        host.overrideUserInterfaceStyle = .light
        editor.overrideUserInterfaceStyle = .light
        AppAppearance.apply(to: window)
        window.rootViewController = host
        window.makeKeyAndVisible()

        editor.pushNote(note)
        editor.layoutIfNeeded()
        editor.testing_refreshAttachmentAppearances()

        // Simulate late API refresh / layout under ambient system Dark (build-234).
        UITraitCollection(userInterfaceStyle: .dark).performAsCurrent {
            editor.pushNote(note)
            editor.layoutIfNeeded()
        }
        editor.testing_refreshAttachmentAppearances()

        var pill: BibleRefPillAttachment?
        let storage = editor.testing_textStorage()
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, _, stop in
            if let p = value as? BibleRefPillAttachment {
                pill = p
                stop.pointee = true
            }
        }
        guard let pill else { return XCTFail("missing bible pill on UITextView path") }
        XCTAssertEqual(pill.renderedInterfaceStyle, .light)
        guard let luma = pill.testing_averageLuminance() else {
            return XCTFail("missing pill luma")
        }
        // Light gospel pill is accent bronze — mid luma, not near-white wash.
        XCTAssertLessThan(luma, 0.85, "pill must not wash out to near-white (luma=\(luma))")
        XCTAssertGreaterThan(luma, 0.15, "pill must remain visible (luma=\(luma))")

        // ~5s delayed snapshot (user-reported timing).
        let exp = expectation(description: "delay")
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { exp.fulfill() }
        wait(for: [exp], timeout: 6.5)
        UITraitCollection(userInterfaceStyle: .dark).performAsCurrent {
            editor.testing_refreshAttachmentAppearances()
            editor.layoutIfNeeded()
        }
        editor.testing_refreshAttachmentAppearances()
        XCTAssertEqual(pill.renderedInterfaceStyle, .light)

        let snap = try XCTUnwrap(Self.render(host.view, size: CGSize(width: 390, height: 844)))
        Self.writeArtifact(snap, name: "b234-systemDark-appLight-pills-after-delay.png", into: self)
        if let pillImg = pill.image {
            Self.writeArtifact(pillImg, name: "b234-bible-pill-light.png", into: self)
        }
        window.isHidden = true
    }

    func testAllNSTextAttachmentSubclasses_surviveAmbientDarkBounds() {
        // Audit: only SpeakerHeaderAttachment + BibleRefPillAttachment exist in App.
        AppAppearance.setTheme("light")
        let header = SpeakerHeaderAttachment(
            blockId: "hdr",
            speakerId: "sp1",
            speakerName: "João",
            colorHex: "#C4A574",
            collapsed: false
        )
        header.refreshImage(width: 320, traits: SpeakerHeaderAttachment.bakeTraits(style: .light))
        let lightHeader = header.renderedInterfaceStyle

        let payload = NoteDocumentCodec.BibleRefPayload(
            bookId: "jhn", chapter: 3, verseStart: 16, verseEnd: nil, text: nil
        )
        let pill = BibleRefPillAttachment(payload: payload, label: "João 3:16", kind: .gospel)
        pill.refreshImage(traits: SpeakerHeaderAttachment.bakeTraits(style: .light))
        let lightPill = pill.renderedInterfaceStyle

        UITraitCollection(userInterfaceStyle: .dark).performAsCurrent {
            _ = header.attachmentBounds(
                for: nil,
                proposedLineFragment: CGRect(x: 0, y: 0, width: 320, height: 44),
                glyphPosition: .zero,
                characterIndex: 0
            )
            _ = pill.attachmentBounds(
                for: nil,
                proposedLineFragment: CGRect(x: 0, y: 0, width: 200, height: 22),
                glyphPosition: .zero,
                characterIndex: 0
            )
            _ = header.image(forBounds: CGRect(x: 0, y: 0, width: 320, height: 36), textContainer: nil, characterIndex: 0)
            _ = pill.image(forBounds: CGRect(x: 0, y: 0, width: 80, height: 22), textContainer: nil, characterIndex: 0)
        }
        XCTAssertEqual(header.renderedInterfaceStyle, lightHeader)
        XCTAssertEqual(pill.renderedInterfaceStyle, lightPill)
        XCTAssertEqual(lightHeader, .light)
        XCTAssertEqual(lightPill, .light)
    }

    // MARK: - 3) Profile sub-pages

    func testProfileSubpages_useScreenBackground_lightAndDark() throws {
        let me = NativeAPIClient.MeDTO(
            id: "u1",
            email: "a@b.c",
            displayName: "Test",
            prefs: NativeAPIClient.PrefsDTO(
                locale: "pt",
                copyLocale: "pt",
                appId: "youversion",
                translationId: "nvi-pt",
                preferNative: true,
                copyFormat: "default",
                citeBook: "abbr",
                citeSep: ":",
                booksCompact: false,
                theme: "system",
                activePlans: nil,
                planProgress: nil,
                avatarId: "",
                avatarUrl: "",
                handle: "test",
                firstName: "Test",
                lastName: "User",
                profileEmail: "a@b.c"
            ),
            notify: NativeAPIClient.NotifyPrefsDTO(
                reading: true,
                friends: true,
                shares: true,
                groups: true,
                apnsDevices: 0
            )
        )

        for (theme, tag) in [("light", "light"), ("dark", "dark")] {
            AppAppearance.setTheme(theme)
            let style: UIUserInterfaceStyle = theme == "dark" ? .dark : .light
            let expected = KCDesign.screenBackground.resolvedColor(
                with: UITraitCollection(userInterfaceStyle: style)
            )

            let pages: [(String, UIViewController)] = [
                ("root", ProfileViewController()),
                ("edit", ProfileEditViewController(me: me, onSaved: {})),
                ("appearance", ProfileThemeViewController(theme: "light", onSaved: {})),
                ("language", ProfileLanguageViewController(prefs: me.prefs, onSaved: {})),
                ("bible", ProfileBibleViewController(prefs: me.prefs, onSaved: {})),
                ("notify", ProfileNotifyViewController(notify: me.notify, onSaved: {})),
                ("signin", NativeSignInViewController()),
                ("speakers", SpeakerPickerViewController(mode: .manage, onManaged: {})),
            ]

            for (name, root) in pages {
                let nav = UINavigationController(rootViewController: root)
                KCChrome.style(navigationController: nav)
                let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
                window.overrideUserInterfaceStyle = style
                AppAppearance.apply(to: window)
                window.rootViewController = nav
                window.makeKeyAndVisible()
                nav.overrideUserInterfaceStyle = style
                root.overrideUserInterfaceStyle = style
                root.loadViewIfNeeded()
                if let tableVC = root as? UITableViewController {
                    tableVC.kcApplyGroupedChrome()
                } else {
                    KCChrome.applyNavigationBarAppearance(to: nav.navigationBar)
                    nav.view.backgroundColor = KCDesign.screenBackground
                    KCChrome.styleScreen(root.view)
                }
                root.viewWillAppear(false)
                root.view.setNeedsLayout()
                root.view.layoutIfNeeded()
                nav.view.layoutIfNeeded()

                let traits = UITraitCollection(userInterfaceStyle: style)
                assertColor(
                    root.view.backgroundColor?.resolvedColor(with: traits),
                    equals: expected,
                    label: "\(name) \(theme) view"
                )
                assertColor(
                    nav.navigationBar.standardAppearance.backgroundColor?.resolvedColor(with: traits),
                    equals: expected,
                    label: "\(name) \(theme) nav"
                )

                let snap = try XCTUnwrap(Self.render(nav.view, size: CGSize(width: 390, height: 844)))
                Self.writeArtifact(snap, name: "b234-\(tag)-profile-\(name).png", into: self)
                window.isHidden = true
            }
        }
    }

    // MARK: - Helpers

    private func assertColor(_ actual: UIColor?, equals expected: UIColor, label: String) {
        guard let actual else { return XCTFail("\(label): missing color") }
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var er: CGFloat = 0, eg: CGFloat = 0, eb: CGFloat = 0, ea: CGFloat = 0
        XCTAssertTrue(actual.getRed(&ar, green: &ag, blue: &ab, alpha: &aa), "\(label) actual")
        XCTAssertTrue(expected.getRed(&er, green: &eg, blue: &eb, alpha: &ea), "\(label) expected")
        XCTAssertEqual(ar, er, accuracy: 0.04, "\(label) R")
        XCTAssertEqual(ag, eg, accuracy: 0.04, "\(label) G")
        XCTAssertEqual(ab, eb, accuracy: 0.04, "\(label) B")
    }

    private static func render(_ view: UIView, size: CGSize) -> UIImage? {
        view.bounds = CGRect(origin: .zero, size: size)
        view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
        }
    }

    private static func writeArtifact(_ image: UIImage, name: String, into test: XCTestCase) {
        let xct = XCTAttachment(image: image)
        xct.name = name
        xct.lifetime = .keepAlways
        test.add(xct)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("katecheo-b234", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? image.pngData()?.write(to: dir.appendingPathComponent(name), options: .atomic)
        // Also drop into CWD /tmp for CI harvest (matches tf222 / tab-bg pattern).
        let tmp = URL(fileURLWithPath: "/tmp").appendingPathComponent(name)
        try? image.pngData()?.write(to: tmp, options: .atomic)
        NSLog("b234 artifact written: %@", dir.appendingPathComponent(name).path)
    }

}
