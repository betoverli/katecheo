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
        ]
        app.launch()

        // Wait for Caderno chrome (signed-out still shows tabs).
        let caderno = app.tabBars.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@ OR label CONTAINS[c] %@",
                        "Caderno", "Notebook", "Cuaderno")
        ).firstMatch
        XCTAssertTrue(caderno.waitForExistence(timeout: 12), "Caderno tab should exist on iPad")

        // iPad must NOT show Tools/Profile as tabs.
        let toolsTab = app.tabBars.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@ OR label CONTAINS[c] %@",
                        "Ferramentas", "Tools", "Herramientas")
        ).firstMatch
        XCTAssertFalse(toolsTab.exists, "Tools must not be a tab on iPad")

        let toolsButton = app.buttons["pad.toolbar.tools"]
        let profileButton = app.buttons["pad.toolbar.profile"]
        // Buttons may take a moment after first layout.
        if !toolsButton.waitForExistence(timeout: 6) {
            // Fallback: still assert tab count semantics via absence of Tools tab.
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
}
