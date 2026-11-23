import UIKit
import XCTest

/// iPad XCUITest: Tools/Profile sheets via toolbar (not tabs), plus Caderno/Grupos
/// detail editor title/body via accessibility value (real TextKit content — not screenshots).
/// Skips automatically on iPhone destinations.
final class IPadChromeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        let idiom = UIDevice.current.userInterfaceIdiom
        try XCTSkipUnless(idiom == .pad, "iPad Simulator only")
    }

    func testIPad_toolsAndProfileButtons_presentSheets() throws {
        let app = launchApp(seedNotes: false)

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

    /// Caderno detail: seeded note title/body via accessibility (separate launch — no tab switch).
    func testIPad_cadernoNote_detailEditorShowsTitleAndBody() throws {
        let app = launchApp(seedNotes: true, openGrupos: false)

        let caderno = app.otherElements["caderno.list"]
        XCTAssertTrue(caderno.waitForExistence(timeout: 15), "Caderno list should appear")

        let cadernoRow = app.cells.matching(
            NSPredicate(format: "label CONTAINS %@", "Nota UITest Caderno")
        ).firstMatch
        XCTAssertTrue(cadernoRow.waitForExistence(timeout: 8), "Seeded Caderno note row should exist")
        cadernoRow.tap()

        assertEditor(
            in: app,
            title: "Nota UITest Caderno",
            body: "Corpo da nota no Caderno.",
            context: "Caderno"
        )
    }

    /// Grupos detail: launch directly on Grupos tab, open group → note, assert title/body a11y.
    func testIPad_groupNote_detailEditorShowsTitleAndBody() throws {
        let app = launchApp(seedNotes: true, openGrupos: true)

        let gruposList = app.otherElements["grupos.list"]
        XCTAssertTrue(gruposList.waitForExistence(timeout: 15), "Grupos list should appear")

        let groupRow = app.cells.matching(
            NSPredicate(format: "label CONTAINS %@", "Grupo UITest")
        ).firstMatch
        XCTAssertTrue(groupRow.waitForExistence(timeout: 8), "Seeded group row should exist")
        groupRow.tap()

        let groupNotes = app.otherElements["caderno.group.list"]
        XCTAssertTrue(groupNotes.waitForExistence(timeout: 8), "Group notes list should push in sidebar")

        let groupNoteRow = app.cells.matching(
            NSPredicate(format: "label CONTAINS %@", "Nota UITest Grupo")
        ).firstMatch
        XCTAssertTrue(groupNoteRow.waitForExistence(timeout: 8), "Seeded group note row should exist")
        groupNoteRow.tap()

        assertEditor(
            in: app,
            title: "Nota UITest Grupo",
            body: "Corpo publicado no grupo.",
            context: "Grupos"
        )
    }

    // MARK: - Helpers

    private func launchApp(seedNotes: Bool, openGrupos: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-katecheoSkipOnboarding",
            "-katecheoSkipSettingsGuide",
            // Full-screen auto sign-in hides tab/toolbar chrome from XCUITest.
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

    private func assertEditor(
        in app: XCUIApplication,
        title: String,
        body: String,
        context: String
    ) {
        let titleField = app.otherElements["note.editor.title"]
        let bodyField = app.otherElements["note.editor.body"]
        let editor = app.textViews["note.editor"]

        // Prefer the live UITextView — probes are best-effort extras for title vs body.
        XCTAssertTrue(
            editor.waitForExistence(timeout: 10)
                || titleField.waitForExistence(timeout: 2),
            "\(context): detail editor should appear after selecting a note"
        )

        if titleField.exists {
            let titleValue = (titleField.value as? String) ?? titleField.label
            XCTAssertTrue(
                titleValue.contains(title),
                "\(context): title accessibility value must include “\(title)”; got: \(titleValue)"
            )
        }

        if bodyField.exists {
            let bodyValue = (bodyField.value as? String) ?? bodyField.label
            XCTAssertTrue(
                bodyValue.contains(body),
                "\(context): body accessibility value must include “\(body)”; got: \(bodyValue)"
            )
        }

        if editor.exists {
            let editorValue = (editor.value as? String) ?? ""
            XCTAssertTrue(
                editorValue.contains(title),
                "\(context): editor value must include title “\(title)”; got: \(editorValue.prefix(120))"
            )
            XCTAssertTrue(
                editorValue.contains(body),
                "\(context): editor value must include body “\(body)”; got: \(editorValue.prefix(160))"
            )
            XCTAssertFalse(editor.label.isEmpty, "\(context): editor accessibility label should be set")
        } else {
            XCTAssertTrue(
                titleField.exists && bodyField.exists,
                "\(context): expected note.editor or title+body probes"
            )
        }
    }
}
