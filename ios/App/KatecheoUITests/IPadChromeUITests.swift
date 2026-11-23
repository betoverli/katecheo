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

    /// Prove Caderno + Grupos detail editors load title/body (accessibility), not PNG burn-in.
    func testIPad_cadernoAndGroupNote_detailEditorShowsTitleAndBody() throws {
        let app = launchApp(seedNotes: true)

        let caderno = app.otherElements["caderno.list"]
        XCTAssertTrue(caderno.waitForExistence(timeout: 15), "Caderno list should appear")

        // Open seeded Caderno note by its row accessibility label (title).
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

        // Switch to Grupos → open group → open group note.
        let gruposTab = app.tabBars.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@ OR label CONTAINS[c] %@",
                        "Grupos", "Groups", "Grupos")
        ).firstMatch
        if gruposTab.waitForExistence(timeout: 3) {
            gruposTab.tap()
        } else {
            // Floating tab bar fallback: match by label anywhere.
            let fallback = app.buttons.matching(
                NSPredicate(format: "label ==[c] %@", "Grupos")
            ).firstMatch
            XCTAssertTrue(fallback.waitForExistence(timeout: 5), "Grupos tab should exist")
            fallback.tap()
        }

        let gruposList = app.otherElements["grupos.list"]
        XCTAssertTrue(gruposList.waitForExistence(timeout: 8), "Grupos list should appear")

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

    private func launchApp(seedNotes: Bool) -> XCUIApplication {
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

        XCTAssertTrue(
            titleField.waitForExistence(timeout: 8) || editor.waitForExistence(timeout: 8),
            "\(context): detail editor should appear after selecting a note"
        )

        // Prefer dedicated title/body probes; fall back to the UITextView value.
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

        if editor.waitForExistence(timeout: 2) {
            let editorValue = (editor.value as? String) ?? ""
            XCTAssertTrue(
                editorValue.contains(title),
                "\(context): editor value must include title “\(title)”; got: \(editorValue.prefix(120))"
            )
            XCTAssertTrue(
                editorValue.contains(body),
                "\(context): editor value must include body “\(body)”; got: \(editorValue.prefix(160))"
            )
            let editorLabel = editor.label
            XCTAssertFalse(editorLabel.isEmpty, "\(context): editor accessibility label should be set")
        } else if !titleField.exists || !bodyField.exists {
            XCTFail("\(context): neither note.editor nor title/body probes were found")
        }
    }
}
