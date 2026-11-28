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

        let primary = app.otherElements["caderno.split.primary"]
        let secondary = app.otherElements["caderno.split.secondary"]
        let sidebar = app.otherElements["caderno.list"]
        let titleProbe = app.otherElements["note.editor.title"]
        XCTAssertTrue(primary.waitForExistence(timeout: 5), "Caderno primary (list) column should exist")
        XCTAssertTrue(secondary.waitForExistence(timeout: 5), "Caderno secondary (detail) column should exist")
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5), "Caderno list sidebar should exist")

        // Allow split layout to settle into .tile after opening the note.
        waitForTile(
            primary: primary,
            secondary: secondary,
            sidebar: sidebar,
            titleProbe: titleProbe,
            timeout: 3
        )
        assertEditorNotCoveredBySidebar(
            primary: primary,
            secondary: secondary,
            sidebar: sidebar,
            editor: editor,
            titleProbe: titleProbe,
            context: "portrait"
        )

        XCUIDevice.shared.orientation = .landscapeLeft
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue(primary.waitForExistence(timeout: 5))
        XCTAssertTrue(secondary.waitForExistence(timeout: 5))
        waitForTile(
            primary: primary,
            secondary: secondary,
            sidebar: sidebar,
            titleProbe: titleProbe,
            timeout: 3
        )
        assertEditorNotCoveredBySidebar(
            primary: primary,
            secondary: secondary,
            sidebar: sidebar,
            editor: editor,
            titleProbe: titleProbe,
            context: "landscape"
        )

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

    private func waitForTile(
        primary: XCUIElement,
        secondary: XCUIElement,
        sidebar: XCUIElement,
        titleProbe: XCUIElement,
        timeout: TimeInterval
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let sidebarMax = sidebarFrameMaxX(primary: primary, sidebar: sidebar)
            let s = secondary.frame
            if sidebarMax > 0, !s.isEmpty, s.minX >= sidebarMax - 2 { return }
            if titleProbe.exists, sidebarMax > 0, titleProbe.frame.minX >= sidebarMax - 2 { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        }
    }

    private func sidebarFrameMaxX(primary: XCUIElement, sidebar: XCUIElement) -> CGFloat {
        let list = sidebar.frame
        if !list.isEmpty { return list.maxX }
        let column = primary.frame
        return column.isEmpty ? 0 : column.maxX
    }

    private func assertEditorNotCoveredBySidebar(
        primary: XCUIElement,
        secondary: XCUIElement,
        sidebar: XCUIElement,
        editor: XCUIElement,
        titleProbe: XCUIElement,
        context: String
    ) {
        let sidebarMax = sidebarFrameMaxX(primary: primary, sidebar: sidebar)
        XCTAssertGreaterThan(sidebarMax, 0, "\(context): sidebar/primary frame must be non-empty")

        let secondaryFrame = secondary.frame
        let columnsTile = !secondaryFrame.isEmpty && secondaryFrame.minX >= sidebarMax - 2
        if columnsTile {
            XCTAssertGreaterThanOrEqual(
                secondaryFrame.minX,
                sidebarMax - 2,
                "\(context): secondary.minX (\(secondaryFrame.minX)) must be >= sidebar.maxX (\(sidebarMax))"
            )
        }

        // User contract: editor text leading edge is to the right of the list sidebar.
        let editorLeading: CGFloat
        if titleProbe.waitForExistence(timeout: 3), titleProbe.frame.minX > 1 {
            editorLeading = titleProbe.frame.minX
        } else if editor.frame.width > 40, editor.frame.minX > 1 {
            editorLeading = editor.frame.minX
        } else if columnsTile {
            editorLeading = secondaryFrame.minX
        } else {
            XCTFail("\(context): could not resolve editor leading edge for tile assert")
            return
        }
        XCTAssertGreaterThanOrEqual(
            editorLeading,
            sidebarMax - 2,
            "\(context): editor leading edge (\(editorLeading)) must be >= sidebar.maxX (\(sidebarMax)) — detail must not sit under the list"
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
