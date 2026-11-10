import XCTest
@testable import App

/// Root tabs must share one Profile-matched fill (nav + content) in light and dark.
@MainActor
final class TabBackgroundConsistencyTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        // Prior suite tests (e.g. Build238 tags) may leave notes in LocalNoteCache;
        // insetGrouped white cells would then skew header/body luma samples.
        LocalNoteCache.saveNotes([])
    }

    override func tearDown() async throws {
        AppAppearance.setTheme("system")
        LocalNoteCache.saveNotes([])
        try await super.tearDown()
    }

    func testScreenBackground_matchesGroupedAndDiffersFromSurface() {
        let light = UITraitCollection(userInterfaceStyle: .light)
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        XCTAssertEqual(
            KCDesign.screenBackground.resolvedColor(with: light),
            KCDesign.groupedBackground.resolvedColor(with: light)
        )
        XCTAssertEqual(
            KCDesign.screenBackground.resolvedColor(with: dark),
            KCDesign.groupedBackground.resolvedColor(with: dark)
        )
        XCTAssertNotEqual(
            KCDesign.screenBackground.resolvedColor(with: light),
            KCDesign.surface.resolvedColor(with: light),
            "nav must not use the lighter surface token"
        )
    }

    func testNavigationBarAppearance_usesScreenBackgroundInEveryState() {
        let appearance = KCChrome.makeNavigationBarAppearance()
        XCTAssertEqual(appearance.backgroundColor, KCDesign.screenBackground)
        XCTAssertNil(appearance.backgroundEffect)
        // UIKit may normalize `.clear` to nil — either means no hairline shadow.
        if let shadow = appearance.shadowColor {
            var alpha: CGFloat = 1
            XCTAssertTrue(shadow.getWhite(nil, alpha: &alpha) || shadow.cgColor.alpha < 0.01)
            XCTAssertLessThan(shadow.cgColor.alpha, 0.01)
        }

        let bar = UINavigationBar()
        KCChrome.applyNavigationBarAppearance(to: bar)
        XCTAssertEqual(bar.standardAppearance.backgroundColor, KCDesign.screenBackground)
        XCTAssertEqual(bar.scrollEdgeAppearance?.backgroundColor, KCDesign.screenBackground)
        XCTAssertEqual(bar.compactAppearance?.backgroundColor, KCDesign.screenBackground)
        XCTAssertFalse(bar.isTranslucent)
    }

    func testRootTabs_lightAndDark_shareScreenBackground_andWriteArtifacts() throws {
        for (theme, fileTag) in [("light", "light"), ("dark", "dark")] {
            AppAppearance.setTheme(theme)
            let style: UIUserInterfaceStyle = theme == "dark" ? .dark : .light
            let expected = KCDesign.screenBackground.resolvedColor(
                with: UITraitCollection(userInterfaceStyle: style)
            )

            let tabs: [(String, UIViewController)] = [
                ("notebook", NotebookListViewController()),
                ("groups", GroupsListViewController()),
                ("tools", VersesHomeViewController()),
                ("profile", ProfileViewController()),
            ]

            for (name, root) in tabs {
                let nav = UINavigationController(rootViewController: root)
                KCChrome.style(navigationController: nav)
                let host = UIViewController()
                host.view.backgroundColor = KCDesign.screenBackground

                let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
                window.overrideUserInterfaceStyle = style
                AppAppearance.apply(to: window)
                window.rootViewController = nav
                window.makeKeyAndVisible()
                nav.overrideUserInterfaceStyle = style
                root.overrideUserInterfaceStyle = style
                root.loadViewIfNeeded()
                root.view.setNeedsLayout()
                root.view.layoutIfNeeded()
                nav.view.layoutIfNeeded()

                assertColor(
                    KCDesign.screenBackground.resolvedColor(with: root.traitCollection),
                    equals: expected,
                    label: "\(name) \(theme): screen token"
                )
                assertColor(
                    root.view.backgroundColor?.resolvedColor(with: root.traitCollection),
                    equals: expected,
                    label: "\(name) \(theme) view"
                )
                assertColor(
                    nav.view.backgroundColor?.resolvedColor(with: nav.traitCollection),
                    equals: expected,
                    label: "\(name) \(theme) nav.view"
                )
                assertColor(
                    nav.navigationBar.standardAppearance.backgroundColor?.resolvedColor(with: nav.traitCollection),
                    equals: expected,
                    label: "\(name) \(theme) nav.standard"
                )
                assertColor(
                    nav.navigationBar.scrollEdgeAppearance?.backgroundColor?.resolvedColor(with: nav.traitCollection),
                    equals: expected,
                    label: "\(name) \(theme) nav.scrollEdge"
                )

                if let table = root.view.subviews.compactMap({ $0 as? UITableView }).first {
                    assertColor(
                        table.backgroundColor?.resolvedColor(with: table.traitCollection),
                        equals: expected,
                        label: "\(name) \(theme) table"
                    )
                }

                let snap = try XCTUnwrap(Self.renderSnapshot(of: nav.view, size: CGSize(width: 390, height: 844)))
                Self.writeArtifact(snap, name: "tab-bg-\(fileTag)-\(name).png", into: self)

                // Sample the extreme trailing margin (outside insetGrouped cards / glyphs)
                // so we compare page fill, not cell surface or large-title ink.
                if let header = Self.sampleLuma(in: snap, normalizedX: 0.985, normalizedY: 0.07),
                   let body = Self.sampleLuma(in: snap, normalizedX: 0.985, normalizedY: 0.42)
                {
                    XCTAssertLessThan(
                        abs(header - body),
                        0.08,
                        "\(name) \(theme): header luma \(header) vs body \(body) — backgrounds must match"
                    )
                }

                window.isHidden = true
            }
        }
    }

    private func assertColor(_ actual: UIColor?, equals expected: UIColor, label: String) {
        guard let actual else {
            return XCTFail("\(label): missing color")
        }
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var er: CGFloat = 0, eg: CGFloat = 0, eb: CGFloat = 0, ea: CGFloat = 0
        XCTAssertTrue(actual.getRed(&ar, green: &ag, blue: &ab, alpha: &aa), "\(label): actual channels")
        XCTAssertTrue(expected.getRed(&er, green: &eg, blue: &eb, alpha: &ea), "\(label): expected channels")
        XCTAssertEqual(ar, er, accuracy: 0.03, "\(label) R")
        XCTAssertEqual(ag, eg, accuracy: 0.03, "\(label) G")
        XCTAssertEqual(ab, eb, accuracy: 0.03, "\(label) B")
    }

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

    private static func writeArtifact(_ image: UIImage, name: String, into test: XCTestCase) {
        let xct = XCTAttachment(image: image)
        xct.name = name
        xct.lifetime = .keepAlways
        test.add(xct)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("katecheo-tab-bg", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try? image.pngData()?.write(to: url, options: .atomic)
        NSLog("tab-bg artifact written: %@", url.path)
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
