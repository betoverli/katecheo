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

    /// Portrait + landscape: note detail column starts to the right of the list sidebar.
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

        // Sidebar = real list view (not a synthetic column a11y element).
        let primary = app.otherElements["caderno.list"]
        XCTAssertTrue(primary.waitForExistence(timeout: 5), "Caderno list sidebar should exist")

        // Real XCUIElement frames only (no computed accessibilityFrame).
        waitForEditorRightOfPrimary(editor: editor, primary: primary, timeout: 4)
        assertEditorTextViewRightOfPrimary(editor: editor, primary: primary, context: "portrait")

        XCUIDevice.shared.orientation = .landscapeLeft
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue(primary.waitForExistence(timeout: 5))
        waitForEditorRightOfPrimary(editor: editor, primary: primary, timeout: 4)
        assertEditorTextViewRightOfPrimary(editor: editor, primary: primary, context: "landscape")

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

        tapDestination(in: app, index: 1, labels: ["Grupos", "Groups"], identifier: "tab.grupos")
        XCTAssertTrue(
            app.otherElements["grupos.list"].waitForExistence(timeout: 8),
            "Grupos list should appear"
        )
        assertNavTitle(in: app, names: ["Grupos", "Groups"], context: "Grupos")

        tapDestination(
            in: app,
            index: 2,
            labels: ["Ferramentas", "Tools", "Herramientas"],
            identifier: "tab.ferramentas"
        )
        assertNavTitle(
            in: app,
            names: ["Ferramentas", "Tools", "Herramientas"],
            context: "Ferramentas"
        )

        tapDestination(
            in: app,
            index: 3,
            labels: ["Perfil", "Profile"],
            identifier: "tab.perfil"
        )
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

    private func waitForEditorRightOfPrimary(
        editor: XCUIElement,
        primary: XCUIElement,
        timeout: TimeInterval
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let p = primary.frame
            let e = editor.frame
            if !p.isEmpty, !e.isEmpty, e.minX >= p.maxX - 2 { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        }
    }

    /// Assert real text view frame sits to the right of the real primary column frame.
    private func assertEditorTextViewRightOfPrimary(
        editor: XCUIElement,
        primary: XCUIElement,
        context: String
    ) {
        let primaryFrame = primary.frame
        let editorFrame = editor.frame
        XCTAssertFalse(primaryFrame.isEmpty, "\(context): primary column frame must be non-empty")
        XCTAssertFalse(editorFrame.isEmpty, "\(context): note.editor UITextView frame must be non-empty")
        XCTAssertGreaterThan(
            editorFrame.width,
            40,
            "\(context): note.editor frame should be a real text view, not a degenerate a11y box"
        )
        XCTAssertGreaterThanOrEqual(
            editorFrame.minX,
            primaryFrame.maxX - 2,
            "\(context): textView.minX (\(editorFrame.minX)) must be >= primary.maxX (\(primaryFrame.maxX)) — detail must not sit under the list"
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

    /// Prefer legacy menu cells, then a single tab identifier match, then label.
    private func tapDestination(
        in app: XCUIApplication,
        index: Int,
        labels: [String],
        identifier: String
    ) {
        let menuCell = app.otherElements["pad.main.menu.\(index)"]
        if menuCell.waitForExistence(timeout: 1) {
            menuCell.tap()
            return
        }
        // tabSidebar duplicates identifiers — always take the first match.
        let byId = app.descendants(matching: .any).matching(identifier: identifier).element(boundBy: 0)
        if byId.waitForExistence(timeout: 2), byId.isHittable {
            byId.tap()
            return
        }
        let predicate = NSPredicate(
            format: labels.map { _ in "label CONTAINS[c] %@" }.joined(separator: " OR "),
            argumentArray: labels
        )
        let tab = app.tabBars.buttons.matching(predicate).element(boundBy: 0)
        if tab.waitForExistence(timeout: 3) {
            tab.tap()
            return
        }
        let any = app.buttons.matching(predicate).element(boundBy: 0)
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
