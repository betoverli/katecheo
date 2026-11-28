import UIKit
import XCTest

/// iPad XCUITest: editor not covered by list sidebar (tile geometry), large titles on
/// list roots, Caderno/Grupos detail editor content. Skips on iPhone destinations.
final class IPadChromeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        let idiom = UIDevice.current.userInterfaceIdiom
        try XCTSkipUnless(idiom == .pad, "iPad Simulator only")
    }

    /// Portrait + landscape: note editor text starts to the right of the list sidebar.
    func testIPad_editorNotCoveredBySidebar_portraitAndLandscape() throws {
        let app = launchApp(seedNotes: true, openGrupos: false)

        let caderno = app.otherElements["caderno.list"]
        XCTAssertTrue(caderno.waitForExistence(timeout: 15), "Caderno list should appear")

        let cadernoRow = app.cells.matching(
            NSPredicate(format: "label CONTAINS %@", "Nota UITest Caderno")
        ).firstMatch
        XCTAssertTrue(cadernoRow.waitForExistence(timeout: 8), "Seeded Caderno note row should exist")
        cadernoRow.tap()

        let editor = app.textViews["note.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "Caderno editor should open")

        let sidebar = app.otherElements["caderno.split.primary"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5), "Caderno primary (list) column should exist")

        assertEditorRightOfSidebar(editor: editor, sidebar: sidebar, context: "portrait")

        XCUIDevice.shared.orientation = .landscapeLeft
        // Allow rotation + layout.
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        assertEditorRightOfSidebar(editor: editor, sidebar: sidebar, context: "landscape")

        XCUIDevice.shared.orientation = .portrait
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    }

    /// List roots show a large / navigation title (Caderno, Grupos, Ferramentas, Perfil).
    func testIPad_listRoots_showLargeTitles() throws {
        let app = launchApp(seedNotes: false)

        XCTAssertTrue(
            app.otherElements["caderno.list"].waitForExistence(timeout: 15)
                || app.navigationBars.element.waitForExistence(timeout: 5),
            "Main shell should appear"
        )

        assertNavTitle(
            in: app,
            names: ["Caderno", "Notebook", "Cuaderno"],
            context: "Caderno"
        )

        // Prefer tab / sidebar menu over flaky floating tab bar queries.
        if app.otherElements["pad.main.menu"].waitForExistence(timeout: 2) {
            app.otherElements["pad.main.menu.1"].tap()
        } else {
            tapDestination(
                in: app,
                labels: ["Grupos", "Groups", "Grupos"],
                identifier: "tab.grupos"
            )
        }
        XCTAssertTrue(
            app.otherElements["grupos.list"].waitForExistence(timeout: 8),
            "Grupos list should appear"
        )
        assertNavTitle(in: app, names: ["Grupos", "Groups"], context: "Grupos")

        if app.otherElements["pad.main.menu"].exists {
            app.otherElements["pad.main.menu.2"].tap()
        } else {
            tapDestination(
                in: app,
                labels: ["Ferramentas", "Tools", "Herramientas"],
                identifier: "tab.ferramentas"
            )
        }
        assertNavTitle(
            in: app,
            names: ["Ferramentas", "Tools", "Herramientas"],
            context: "Ferramentas"
        )

        if app.otherElements["pad.main.menu"].exists {
            app.otherElements["pad.main.menu.3"].tap()
        } else {
            tapDestination(
                in: app,
                labels: ["Perfil", "Profile", "Perfil"],
                identifier: "tab.perfil"
            )
        }
        assertNavTitle(in: app, names: ["Perfil", "Profile"], context: "Perfil")
    }

    /// Caderno detail: seeded note title/body via accessibility.
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

    /// Grupos detail: launch on Grupos, open group → note, assert title/body a11y.
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

    private func assertEditorRightOfSidebar(
        editor: XCUIElement,
        sidebar: XCUIElement,
        context: String
    ) {
        let editorFrame = editor.frame
        let sidebarFrame = sidebar.frame
        XCTAssertFalse(editorFrame.isEmpty, "\(context): editor frame must be non-empty")
        XCTAssertFalse(sidebarFrame.isEmpty, "\(context): sidebar frame must be non-empty")
        XCTAssertGreaterThanOrEqual(
            editorFrame.minX,
            sidebarFrame.maxX - 1,
            "\(context): editor.minX (\(editorFrame.minX)) must be >= sidebar.maxX (\(sidebarFrame.maxX)) — detail must not sit under the list"
        )
    }

    private func assertNavTitle(in app: XCUIApplication, names: [String], context: String) {
        let predicate = NSPredicate(
            format: names.map { _ in "label CONTAINS[c] %@" }.joined(separator: " OR "),
            argumentArray: names
        )
        let bar = app.navigationBars.matching(predicate).firstMatch
        let staticTitle = app.staticTexts.matching(predicate).firstMatch
        XCTAssertTrue(
            bar.waitForExistence(timeout: 6) || staticTitle.waitForExistence(timeout: 2),
            "\(context): large/navigation title should exist (\(names.joined(separator: "/")))"
        )
    }

    private func tapDestination(in app: XCUIApplication, labels: [String], identifier: String) {
        let byId = app.buttons[identifier]
        if byId.waitForExistence(timeout: 2) {
            byId.tap()
            return
        }
        let predicate = NSPredicate(
            format: labels.map { _ in "label CONTAINS[c] %@" }.joined(separator: " OR "),
            argumentArray: labels
        )
        let tab = app.tabBars.buttons.matching(predicate).firstMatch
        if tab.waitForExistence(timeout: 3) {
            tab.tap()
            return
        }
        let any = app.buttons.matching(predicate).firstMatch
        if any.waitForExistence(timeout: 3) {
            any.tap()
        }
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
