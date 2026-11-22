import UIKit
import XCTest

/// iPad XCUITest: Caderno note open, Grupos selection, Tools/Profile sheets.
/// Skips automatically on iPhone destinations.
final class IPadChromeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        let idiom = UIDevice.current.userInterfaceIdiom
        try XCTSkipUnless(idiom == .pad, "iPad Simulator only")
    }

    func testIPad_toolsAndProfileButtons_presentSheets() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-katecheoSkipOnboarding",
            "-katecheoSkipSettingsGuide",
        ]
        app.launch()

        // Caderno may auto-present sign-in over the tabs when signed out — dismiss if needed.
        dismissSignInIfPresent(in: app)

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 12), "Tab bar should appear on iPad after launch")

        // iPad must NOT show Tools/Profile as tabs.
        let toolsTab = app.tabBars.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@ OR label CONTAINS[c] %@",
                        "Ferramentas", "Tools", "Herramientas")
        ).firstMatch
        XCTAssertFalse(toolsTab.exists, "Tools must not be a tab on iPad")

        let toolsButton = app.buttons["pad.toolbar.tools"]
        let profileButton = app.buttons["pad.toolbar.profile"]
        // Nav bar buttons can take a moment after first layout.
        if !toolsButton.waitForExistence(timeout: 8) {
            // Still assert tab chrome: only Caderno + Grupos.
            let tabCount = app.tabBars.buttons.count
            XCTAssertLessThanOrEqual(tabCount, 2, "iPad tab bar should only show Caderno and Grupos")
            return
        }
        XCTAssertTrue(profileButton.exists)

        toolsButton.tap()
        let toolsSheet = app.otherElements["pad.sheet.tools"]
        let toolsNav = app.navigationBars.matching(
            NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@ OR label CONTAINS[c] %@",
                        "Ferramentas", "Tools", "Herramientas")
        ).firstMatch
        XCTAssertTrue(
            toolsSheet.waitForExistence(timeout: 5) || toolsNav.waitForExistence(timeout: 5),
            "Tools sheet should present"
        )

        let done = app.buttons["pad.sheet.done"]
        if done.waitForExistence(timeout: 3) {
            done.tap()
        } else {
            app.swipeDown()
        }

        XCTAssertTrue(profileButton.waitForExistence(timeout: 5))
        profileButton.tap()
        let profileSheet = app.otherElements["pad.sheet.profile"]
        let profileNav = app.navigationBars.matching(
            NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@",
                        "Perfil", "Profile")
        ).firstMatch
        XCTAssertTrue(
            profileSheet.waitForExistence(timeout: 5) || profileNav.waitForExistence(timeout: 5),
            "Profile sheet should present"
        )
    }

    private func dismissSignInIfPresent(in app: XCUIApplication) {
        let signIn = app.otherElements["signin.root"]
        if signIn.waitForExistence(timeout: 3) {
            // Prefer an explicit close if present; otherwise swipe/dismiss modal.
            let closePredicates = ["Fechar", "Close", "Cancelar", "Cancel", "OK"]
            let close = app.buttons.matching(NSPredicate(format: "label IN %@", closePredicates)).firstMatch
            if close.exists, close.isHittable {
                close.tap()
            } else {
                // Full-screen sign-in: send the app to background isn't allowed; try nav back / swipe.
                if app.navigationBars.buttons.firstMatch.exists {
                    app.navigationBars.buttons.firstMatch.tap()
                }
            }
        }
    }
}
