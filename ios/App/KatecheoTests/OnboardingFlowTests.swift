import XCTest
@testable import Katecheo

/// First-launch onboarding: skip, swipe-through, Get started, safe-area chrome, snapshots.
@MainActor
final class OnboardingFlowTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        OnboardingStore.resetForTesting()
    }

    override func tearDown() async throws {
        OnboardingStore.markSeenForTesting()
        try await super.tearDown()
    }

    func testStore_launchArgumentSkipsOnboarding() {
        OnboardingStore.resetForTesting()
        XCTAssertTrue(OnboardingStore.shouldShowOnLaunch)

        OnboardingStore.resetForTesting()
        OnboardingStore.applyLaunchArgumentsIfNeeded(arguments: [OnboardingStore.skipLaunchArgument])
        XCTAssertTrue(OnboardingStore.hasSeenOnboarding)
        XCTAssertFalse(OnboardingStore.shouldShowOnLaunch)
    }

    func testStore_resetLaunchArgumentClearsSeenFlag() {
        OnboardingStore.resetForTesting()
        OnboardingStore.hasSeenOnboarding = true
        OnboardingStore.applyLaunchArgumentsIfNeeded(arguments: [
            OnboardingStore.resetLaunchArgument,
        ])
        XCTAssertFalse(OnboardingStore.hasSeenOnboarding)
        XCTAssertTrue(OnboardingStore.shouldShowOnLaunch)
    }

    func testAppRoot_showsOnboardingBeforeMainShell() {
        OnboardingStore.resetForTesting()
        let root = AppRoot.makeRootViewController()
        XCTAssertTrue(root is OnboardingViewController)

        OnboardingStore.markSeen()
        let shell = AppRoot.makeRootViewController()
        XCTAssertTrue(shell is NativeRootTabBarController)
    }

    func testEffectiveBottomSafeInset_usesHomeIndicatorFallbackWhenBottomZeroButTopInset() {
        // TF 325 failure mode: top inset present (Dynamic Island), bottom reports 0.
        let inset = OnboardingViewController.effectiveBottomSafeInset(
            viewInset: 0,
            windowInset: 0,
            topInset: 59
        )
        XCTAssertEqual(inset, OnboardingViewController.homeIndicatorFallback)

        let healthy = OnboardingViewController.effectiveBottomSafeInset(
            viewInset: 34,
            windowInset: 34,
            topInset: 59
        )
        XCTAssertEqual(healthy, 34)

        let seHomeButton = OnboardingViewController.effectiveBottomSafeInset(
            viewInset: 0,
            windowInset: 0,
            topInset: 20
        )
        XCTAssertEqual(seHomeButton, 0, "classic SE / home-button phones keep a zero bottom inset")
    }

    func testFlow_skipMarksSeenAndFinishes() {
        OnboardingStore.resetForTesting()
        var finished = false
        let (vc, window) = makeOnboarding(style: .light) {
            finished = true
        }
        XCTAssertEqual(vc.testing_pageCount, 4)
        XCTAssertTrue(vc.testing_isSkipVisible)
        XCTAssertFalse(vc.testing_isStartVisible)
        XCTAssertEqual(vc.testing_skipTitle, String(localized: "Pular"))
        XCTAssertEqual(vc.testing_pageTitle, String(localized: "Katecheo"))

        vc.testing_tapSkip()
        XCTAssertTrue(OnboardingStore.hasSeenOnboarding)
        XCTAssertTrue(finished)
        window.isHidden = true
    }

    func testFlow_swipeThroughShowsGetStartedThenFinishes() {
        OnboardingStore.resetForTesting()
        var finished = false
        let (vc, window) = makeOnboarding(style: .dark) {
            finished = true
        }

        for page in 0 ..< 3 {
            vc.testing_goToPage(page)
            vc.view.layoutIfNeeded()
            XCTAssertEqual(vc.testing_currentPage, page)
            XCTAssertTrue(vc.testing_isSkipVisible, "skip visible on page \(page)")
            XCTAssertFalse(vc.testing_isStartVisible, "start hidden on page \(page)")
        }

        vc.testing_goToPage(3)
        vc.view.layoutIfNeeded()
        XCTAssertEqual(vc.testing_currentPage, 3)
        XCTAssertFalse(vc.testing_isSkipVisible)
        XCTAssertTrue(vc.testing_isStartVisible)
        XCTAssertEqual(vc.testing_startTitle, String(localized: "Começar"))
        XCTAssertEqual(vc.testing_pageTitle, String(localized: "Grupos e amigos"))

        vc.testing_tapStart()
        XCTAssertTrue(OnboardingStore.hasSeenOnboarding)
        XCTAssertTrue(finished)
        window.isHidden = true
    }

    func testFlow_katecheoWordmarkIsSingleUniformTitle() throws {
        let (vc, window) = makeOnboarding(style: .light, size: CGSize(width: 320, height: 568))
        vc.testing_goToPage(0)
        vc.view.layoutIfNeeded()
        XCTAssertEqual(vc.testing_pageTitle, "Katecheo")
        let wordmark = try XCTUnwrap(vc.testing_wordmarkLabel)
        XCTAssertEqual(wordmark.numberOfLines, 1)
        XCTAssertTrue(wordmark.adjustsFontSizeToFitWidth)
        XCTAssertEqual(wordmark.minimumScaleFactor, 0.6, accuracy: 0.001)
        XCTAssertEqual(wordmark.lineBreakMode, .byClipping)
        let lineHeight = wordmark.font.lineHeight
        XCTAssertLessThanOrEqual(wordmark.bounds.height, lineHeight * 1.35 + 2)
        window.isHidden = true
    }

    func testFlow_titlesUseFullWidthNotNarrowColumn() throws {
        let (vc, window) = makeOnboarding(style: .dark, size: CGSize(width: 375, height: 667))
        for page in 0 ..< vc.testing_pageCount {
            vc.testing_goToPage(page)
            vc.view.layoutIfNeeded()
            let title = try XCTUnwrap(vc.testing_currentTitleLabel)
            let body = try XCTUnwrap(vc.testing_currentBodyLabel)
            let minTextWidth = vc.view.bounds.width - (KCDesign.Space.xl * 2) - 8
            XCTAssertGreaterThanOrEqual(title.bounds.width, minTextWidth * 0.92)
            XCTAssertGreaterThanOrEqual(body.bounds.width, minTextWidth * 0.92)
        }
        window.isHidden = true
    }

    /// Hit-test style assertion: Get started frame in window coords must sit inside
    /// the safe band. Insets are applied explicitly via the testing hook so the
    /// TEST_HOST simulator's real safe area cannot skew SE / Pro Max cases.
    func testFlow_getStartedFrameInsideWindowSafeArea_onSmallAndLargePhones() {
        let cases: [(String, CGSize, UIEdgeInsets)] = [
            ("se", CGSize(width: 375, height: 667), UIEdgeInsets(top: 20, left: 0, bottom: 0, right: 0)),
            ("phone15", CGSize(width: 393, height: 852), UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)),
            ("proMax", CGSize(width: 430, height: 932), UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)),
            // TF 325 regression: top inset present, bottom reports 0 until fallback.
            ("brokenBottomInset", CGSize(width: 393, height: 852), UIEdgeInsets(top: 59, left: 0, bottom: 0, right: 0)),
        ]
        for (name, size, insets) in cases {
            let (vc, window) = makeOnboarding(style: .dark, size: size, safeArea: .zero)
            vc.testing_goToPage(3)
            vc.view.layoutIfNeeded()
            // Drive the pin from the case insets — not the host simulator's live insets.
            vc.testing_applyBottomInsets(
                viewInset: insets.bottom,
                windowInset: insets.bottom,
                topInset: insets.top
            )

            XCTAssertTrue(vc.testing_isStartVisible, "\(name): start visible")

            let effective = OnboardingViewController.effectiveBottomSafeInset(
                viewInset: insets.bottom,
                windowInset: insets.bottom,
                topInset: insets.top
            )
            let expectedPad = effective + KCDesign.Space.md
            XCTAssertEqual(
                vc.testing_bottomBarBottomConstant,
                -expectedPad,
                accuracy: 0.5,
                "\(name): bottom constant must clear home indicator + 16pt"
            )

            let startInView = vc.testing_startButtonFrameInView
            let limitY = size.height - expectedPad
            XCTAssertLessThanOrEqual(
                startInView.maxY,
                limitY + 0.5,
                "\(name): start maxY \(startInView.maxY) must be ≤ \(limitY)"
            )
            XCTAssertGreaterThan(startInView.height, 40, "\(name): tappable height")
            XCTAssertGreaterThan(startInView.width, 40, "\(name): tappable width")

            // Window-coordinate containment (as requested).
            let startInWindow = vc.testing_startButton.convert(vc.testing_startButton.bounds, to: window)
            let safeMaxY = size.height - effective
            XCTAssertLessThanOrEqual(
                startInWindow.maxY,
                safeMaxY - KCDesign.Space.md + 0.5,
                "\(name): start in window coords must be inside safe area with 16pt margin"
            )
            XCTAssertTrue(
                window.bounds.insetBy(dx: -0.5, dy: -0.5).contains(startInWindow),
                "\(name): start must be inside window bounds (hit-testing)"
            )

            window.isHidden = true
        }
    }

    func testFlow_snapshotsLightDark_allPages_seAndProMax() throws {
        let sizes: [(String, CGSize, UIEdgeInsets)] = [
            ("se", CGSize(width: 375, height: 667), UIEdgeInsets(top: 20, left: 0, bottom: 0, right: 0)),
            ("proMax", CGSize(width: 430, height: 932), UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)),
        ]
        for (device, size, insets) in sizes {
            for style in [UIUserInterfaceStyle.light, .dark] {
                let tag = style == .light ? "light" : "dark"
                let (vc, window) = makeOnboarding(style: style, size: size, safeArea: insets)
                for page in 0 ..< vc.testing_pageCount {
                    vc.testing_goToPage(page)
                    vc.view.layoutIfNeeded()
                    let snap = try XCTUnwrap(Self.render(vc.view, size: size))
                    XCTAssertTrue(Self.hasVisiblePixels(snap), "onboarding-\(device)-\(tag)-page\(page) must not be blank")
                    Self.write(snap, name: "onboarding-\(device)-\(tag)-page\(page).png", into: self)
                }
                window.isHidden = true
            }
        }
    }

    private func makeOnboarding(
        style: UIUserInterfaceStyle,
        size: CGSize = CGSize(width: 390, height: 844),
        safeArea: UIEdgeInsets? = nil,
        onFinished: (() -> Void)? = nil
    ) -> (OnboardingViewController, UIWindow) {
        let vc = OnboardingViewController()
        vc.onFinished = onFinished
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.overrideUserInterfaceStyle = style
        AppAppearance.apply(to: window)
        window.rootViewController = vc
        window.makeKeyAndVisible()
        vc.overrideUserInterfaceStyle = style
        vc.loadViewIfNeeded()
        let insets = safeArea ?? (
            size.height <= 700
                ? UIEdgeInsets(top: 20, left: 0, bottom: 0, right: 0)
                : UIEdgeInsets(top: 47, left: 0, bottom: 34, right: 0)
        )
        vc.additionalSafeAreaInsets = insets
        vc.viewWillAppear(false)
        vc.view.layoutIfNeeded()
        vc.testing_updateBottomChromeInset()
        vc.view.layoutIfNeeded()
        return (vc, window)
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

    private static func hasVisiblePixels(_ image: UIImage) -> Bool {
        guard let cg = image.cgImage, let data = cg.dataProvider?.data, let ptr = CFDataGetBytePtr(data) else {
            return false
        }
        let bpp = max(cg.bitsPerPixel / 8, 1)
        let row = cg.bytesPerRow
        var samples = 0
        var nonZero = 0
        for y in stride(from: 0, to: cg.height, by: max(cg.height / 40, 1)) {
            for x in stride(from: 0, to: cg.width, by: max(cg.width / 40, 1)) {
                let idx = y * row + x * bpp
                samples += 1
                if ptr[idx] > 8 || (bpp > 1 && ptr[idx + 1] > 8) || (bpp > 2 && ptr[idx + 2] > 8) {
                    nonZero += 1
                }
            }
        }
        return samples > 0 && nonZero > samples / 20
    }

    private static func write(_ image: UIImage, name: String, into test: XCTestCase) {
        let xct = XCTAttachment(image: image)
        xct.name = name
        xct.lifetime = .keepAlways
        test.add(xct)
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("katecheo-onboarding", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try? image.pngData()?.write(to: url, options: .atomic)
        NSLog("onboarding artifact written: %@", url.path)
    }
}
