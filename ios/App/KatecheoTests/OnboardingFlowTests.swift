import XCTest
@testable import Katecheo

/// First-launch onboarding: skip, swipe-through, Get started, launch-arg skip, light/dark snapshots.
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

    func testFlow_katecheoWordmarkIsSingleUniformTitle() {
        let (vc, window) = makeOnboarding(style: .light)
        vc.testing_goToPage(0)
        // Welcome title is the complete word "Katecheo" — never split.
        XCTAssertEqual(vc.testing_pageTitle, "Katecheo")
        XCTAssertFalse(vc.testing_pageTitle?.contains("Kate") == true && vc.testing_pageTitle != "Katecheo")
        window.isHidden = true
    }

    func testFlow_snapshotsLightDark_allPages() throws {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let tag = style == .light ? "light" : "dark"
            let (vc, window) = makeOnboarding(style: style)
            for page in 0 ..< vc.testing_pageCount {
                vc.testing_goToPage(page)
                vc.view.layoutIfNeeded()
                let snap = try XCTUnwrap(Self.render(vc.view, size: CGSize(width: 390, height: 844)))
                XCTAssertTrue(Self.hasVisiblePixels(snap), "onboarding-\(tag)-page\(page) must not be blank")
                Self.write(snap, name: "onboarding-\(tag)-page\(page).png", into: self)
            }
            window.isHidden = true
        }
    }

    private func makeOnboarding(
        style: UIUserInterfaceStyle,
        onFinished: (() -> Void)? = nil
    ) -> (OnboardingViewController, UIWindow) {
        let vc = OnboardingViewController()
        vc.onFinished = onFinished
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.overrideUserInterfaceStyle = style
        AppAppearance.apply(to: window)
        window.rootViewController = vc
        window.makeKeyAndVisible()
        vc.overrideUserInterfaceStyle = style
        vc.loadViewIfNeeded()
        vc.viewWillAppear(false)
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
