import UIKit
import XCTest

/// iPhone XCUITest: Caderno (and Grupos) note detail must show a back control that
/// returns to the list — regression for TF 496 / #134 hidesBackButton leak.
final class IPhoneNotebookBackUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        let idiom = UIDevice.current.userInterfaceIdiom
        try XCTSkipUnless(idiom == .phone, "iPhone Simulator only")
    }

    func testIPhone_cadernoNote_backButtonReturnsToList() throws {
        let app = launchApp(seedNotes: true, openGrupos: false)

        let caderno = app.otherElements["caderno.list"]
        XCTAssertTrue(caderno.waitForExistence(timeout: 15), "Caderno list should appear")

        let row = app.cells.matching(
            NSPredicate(format: "label CONTAINS %@", "Nota UITest Caderno")
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8), "Seeded Caderno note row should exist")
        row.tap()

        let editor = app.textViews["note.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "Caderno note editor should open")

        let back = cadernoBackButton(in: app)
        XCTAssertTrue(back.waitForExistence(timeout: 5), "Caderno back button must exist on iPhone note detail")
        back.tap()

        XCTAssertTrue(
            caderno.waitForExistence(timeout: 8),
            "Tapping Caderno back must return to the note list"
        )
        XCTAssertFalse(
            editor.exists,
            "Editor should leave the hierarchy after popping back to Caderno"
        )
    }

    func testIPhone_groupNote_backButtonReturnsToGroupList() throws {
        let app = launchApp(seedNotes: true, openGrupos: true)

        let gruposList = app.otherElements["grupos.list"]
        XCTAssertTrue(gruposList.waitForExistence(timeout: 15), "Grupos list should appear")

        let groupRow = app.cells.matching(
            NSPredicate(format: "label CONTAINS %@", "Grupo UITest")
        ).firstMatch
        XCTAssertTrue(groupRow.waitForExistence(timeout: 8), "Seeded group row should exist")
        groupRow.tap()

        let groupNotes = app.otherElements["caderno.group.list"]
        XCTAssertTrue(groupNotes.waitForExistence(timeout: 8), "Group notes list should push")

        let noteRow = app.cells.matching(
            NSPredicate(format: "label CONTAINS %@", "Nota UITest Grupo")
        ).firstMatch
        XCTAssertTrue(noteRow.waitForExistence(timeout: 8), "Seeded group note row should exist")
        noteRow.tap()

        let editor = app.textViews["note.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "Group note editor should open")

        // Back title is the group name (list title / backButtonTitle).
        let back = app.navigationBars.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Grupo UITest")
        ).firstMatch
        XCTAssertTrue(
            back.waitForExistence(timeout: 5) || app.navigationBars.buttons.element(boundBy: 0).waitForExistence(timeout: 2),
            "Group note detail must show a back control on iPhone"
        )
        if back.exists {
            back.tap()
        } else {
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }

        XCTAssertTrue(
            groupNotes.waitForExistence(timeout: 8),
            "Tapping back must return to the group notes list"
        )
    }

    // MARK: - Helpers

    private func launchApp(seedNotes: Bool, openGrupos: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-katecheoSkipOnboarding",
            "-katecheoSkipSettingsGuide",
            "-katecheoSkipAutoSignIn",
        ]
        if seedNotes {
            app.launchArguments += ["-katecheoUITestSeedNotes"]
        }
        if openGrupos {
            app.launchArguments += ["-katecheoUITestOpenGrupos"]
        }
        app.launch()
        return app
    }

    private func cadernoBackButton(in app: XCUIApplication) -> XCUIElement {
        // Prefer localized Caderno back title; fall back to first nav-bar button.
        let byTitle = app.navigationBars.buttons.matching(
            NSPredicate(
                format: "label ==[c] %@ OR label ==[c] %@ OR label ==[c] %@",
                "Caderno",
                "Notebook",
                "Cuaderno"
            )
        ).firstMatch
        if byTitle.waitForExistence(timeout: 2) {
            return byTitle
        }
        return app.navigationBars.buttons.element(boundBy: 0)
    }
}
