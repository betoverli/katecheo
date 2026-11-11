import XCTest

/// Real device-path coverage for TF 325: Get started must be hittable above the
/// home indicator, and tapping it must reach the sign-in / create-account screen.
final class OnboardingGetStartedUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testGetStarted_isHittableAndOpensSignIn() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-katecheoResetOnboarding",
        ]
        app.launch()

        let root = app.otherElements["onboarding.root"]
        XCTAssertTrue(root.waitForExistence(timeout: 10), "onboarding root should appear on cold launch")

        let scroll = app.scrollViews["onboarding.scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))

        let start = app.buttons["onboarding.start"]
        // Swipe through to the last page (4 pages → 3 swipes). Retry if animation lags.
        for _ in 0 ..< 5 {
            if start.exists, start.isHittable { break }
            scroll.swipeLeft()
            RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        }
        XCTAssertTrue(start.waitForExistence(timeout: 5), "Get started should appear on the last page")
        XCTAssertTrue(start.isHittable, "Get started must be hittable (not under the home indicator)")

        // Frame must sit fully inside the app frame (not clipped below the screen).
        let startFrame = start.frame
        let appFrame = app.frame
        XCTAssertFalse(startFrame.isEmpty)
        XCTAssertGreaterThanOrEqual(startFrame.minX, appFrame.minX - 1)
        XCTAssertLessThanOrEqual(startFrame.maxX, appFrame.maxX + 1)
        XCTAssertGreaterThanOrEqual(startFrame.minY, appFrame.minY - 1)
        XCTAssertLessThanOrEqual(
            startFrame.maxY,
            appFrame.maxY - 8,
            "Get started maxY must clear the physical bottom edge (home indicator band)"
        )

        start.tap()

        // After onboarding, Caderno auto-presents sign-in when signed out + empty.
        let signInRoot = app.otherElements["signin.root"]
        let emailPredicates = [
            "Entrar com email",
            "Sign in with email",
            "Entrar con correo",
        ]
        let emailButton = app.buttons.matching(
            NSPredicate(format: "label IN %@", emailPredicates)
        ).firstMatch
        let navPredicates = [
            "Entrar ou criar conta",
            "Sign in or create account",
            "Iniciar sesión o crear cuenta",
        ]
        let navBar = app.navigationBars.matching(
            NSPredicate(format: "identifier IN %@ OR label IN %@", navPredicates, navPredicates)
        ).firstMatch

        let appeared =
            signInRoot.waitForExistence(timeout: 10)
            || emailButton.waitForExistence(timeout: 2)
            || navBar.waitForExistence(timeout: 2)
        XCTAssertTrue(appeared, "login / create-account screen must appear after Get started")
    }
}
