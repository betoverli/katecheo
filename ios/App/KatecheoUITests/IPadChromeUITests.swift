import UIKit
import XCTest

/// iPad XCUITest: Tools/Profile sheets via toolbar (not tabs).
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
            // Full-screen auto sign-in hides tab/toolbar chrome from XCUITest.
            "-katecheoSkipAutoSignIn",
        ]
        app.launch()

        // Prefer content identifiers over tabBars — iOS 18+ floating tab bar is flaky in queries.
        let caderno = app.otherElements["caderno.list"]
        let toolsButton = app.buttons["pad.toolbar.tools"]
        let profileButton = app.buttons["pad.toolbar.profile"]

        let shellVisible =
            caderno.waitForExistence(timeout: 15)
            || toolsButton.waitForExistence(timeout: 2)
            || app.otherElements["grupos.list"].waitForExistence(timeout: 2)
        XCTAssertTrue(shellVisible, "iPad main shell should appear after skipping onboarding/sign-in")

        // iPad must NOT show Tools/Profile as tabs (when tab bar is queryable).
        let toolsTab = app.tabBars.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@ OR label CONTAINS[c] %@",
                        "Ferramentas", "Tools", "Herramientas")
        ).firstMatch
        XCTAssertFalse(toolsTab.exists, "Tools must not be a tab on iPad")

        XCTAssertTrue(toolsButton.waitForExistence(timeout: 8), "Tools toolbar button should exist on Caderno/Grupos")
        XCTAssertTrue(profileButton.exists, "Profile toolbar button should exist")

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
}
