import XCTest
@testable import Katecheo

/// Captures iPad landscape + portrait screenshots of Caderno (note open with text),
/// Grupos 2-column, and the main-menu sidebar — plain PNGs (no burn-in).
/// Plus iPhone Caderno/Grupos shots on phone destinations.
@MainActor
final class IPadScreenshotTests: XCTestCase {
    private var hostWindow: UIWindow?

    override func tearDown() async throws {
        hostWindow?.rootViewController?.dismiss(animated: false)
        hostWindow?.isHidden = true
        hostWindow = nil
        LocalNoteCache.saveNotes([])
        LocalSessionCache.clearGroups()
        LocalGroupNotesCache.clearAll()
        UserDefaults.standard.removeObject(forKey: "katecheo.ferramentas.lastTool")
        try await super.tearDown()
    }

    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    func testCapture_iPadChrome_landscapeAndPortrait() throws {
        try XCTSkipUnless(isPad, "Screenshot suite runs on iPad Simulator in CI")

        let titled = Self.sampleNote(
            title: "Nota iPad",
            body: "Texto do corpo da nota aberto no detalhe."
        )
        LocalNoteCache.saveNotes([titled])

        let group = Self.sampleGroup()
        LocalSessionCache.saveGroups([group])
        let groupNote = Self.sampleNote(
            title: "Nota do grupo",
            body: "Conteúdo publicado no grupo de estudo."
        )
        let card = NativeAPIClient.GroupNoteCardDTO(
            note: .init(
                id: groupNote.id,
                title: groupNote.title,
                happenedAt: groupNote.happenedAt,
                updatedAt: groupNote.updatedAt
            ),
            author: .init(userId: "u1", handle: "ana", firstName: "Ana", lastName: ""),
            owned: true,
            document: groupNote
        )

        let sizes: [(String, CGSize)] = [
            ("landscape", CGSize(width: 1180, height: 820)),
            ("portrait", CGSize(width: 820, height: 1180)),
        ]

        for (orientation, size) in sizes {
            let tabs = NativeRootTabBarController()
            let window = attachWindow(root: tabs, size: size)
            tabs.loadViewIfNeeded()
            tabs.view.layoutIfNeeded()

            // 1) Caderno — paint list from cache, open via real row selection (wiring under test).
            let split = try XCTUnwrap(tabs.viewControllers?.first as? NotebookSplitViewController)
            let list = split.listViewController
            list.loadViewIfNeeded()
            list.viewWillAppear(false)
            list.view.layoutIfNeeded()
            XCTAssertGreaterThan(list.testing_filteredRowCount, 0, "Caderno list must show cached note")
            list.testing_selectRow(at: 0)
            RunLoop.current.run(until: Date().addingTimeInterval(0.35))
            tabs.view.layoutIfNeeded()

            let detail = try XCTUnwrap(
                (split.viewController(for: .secondary) as? UINavigationController)?
                    .topViewController as? NoteDetailViewController,
                "Selecting a Caderno row must open NoteDetail in the secondary column"
            )
            detail.ensureEditorContentVisible()
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            tabs.view.layoutIfNeeded()

            let editorText = detail.testing_editor.testing_plainText
            XCTAssertTrue(
                editorText.contains("Nota iPad"),
                "Caderno detail must show note title; got: \(editorText.prefix(80))"
            )
            XCTAssertTrue(
                editorText.contains("Texto do corpo"),
                "Caderno detail must show note body; got: \(editorText.prefix(120))"
            )
            XCTAssertGreaterThan(
                detail.testing_editor.testing_textContainerWidth,
                100,
                "Caderno TextKit container must have real width (was 0 → empty detail)"
            )
            XCTAssertGreaterThan(
                detail.testing_editor.testing_glyphCount,
                10,
                "Caderno editor must lay out glyphs for title/body (not string-only)"
            )
            XCTAssertGreaterThan(
                detail.testing_editor.testing_usedTextHeight,
                40,
                "Caderno editor usedRect must include title+body height"
            )
            XCTAssertGreaterThan(
                detail.testing_editor.testing_tagsStripFrame().minY,
                40,
                "Tags strip must sit below the title line (not cover title ink)"
            )
            XCTAssertEqual(
                detail.testing_editor.testing_contentOffsetY,
                0,
                accuracy: 1,
                "Open note must not be scrolled — title/body would leave the viewport"
            )
            XCTAssertNil(detail.navigationItem.leftBarButtonItem, "No ghost displayMode button")
            XCTAssertEqual(list.testing_highlightedNoteId, titled.id, "Open note row must stay highlighted")
            XCTAssertTrue(list.testing_hasSelectedRow, "UITableView selection must survive reload")

            // Tile chrome (frame geometry is asserted in XCUITest against live a11y frames).
            XCTAssertEqual(split.preferredDisplayMode, .oneBesideSecondary)
            if #available(iOS 16.0, *) {
                XCTAssertEqual(split.preferredSplitBehavior, .tile)
            }

            // Plain screenshot only — no glyph burn-in.
            let cadernoShot = render(tabs.view, size: size, priming: detail)
            write(cadernoShot, name: "ipad-\(orientation)-caderno-note")

            // 2a) Grupos list (sidebar + empty detail)
            tabs.selectedIndex = 1
            let groupsSplit = try XCTUnwrap(tabs.viewControllers?[1] as? GroupsSplitViewController)
            XCTAssertEqual(groupsSplit.style, .doubleColumn)
            groupsSplit.groupsListViewController.loadViewIfNeeded()
            groupsSplit.groupsListViewController.testing_replaceGroups([group])
            groupsSplit.popToGroupsList(animated: false)
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
            tabs.view.layoutIfNeeded()
            write(render(tabs.view, size: size), name: "ipad-\(orientation)-grupos-list")

            // 2b) After tapping a group: notes list in the same sidebar + a note open in detail.
            groupsSplit.showGroup(group, animated: false)
            let groupList = try XCTUnwrap(groupsSplit.openGroupNotesList)
            groupList.loadViewIfNeeded()
            groupList.testing_replaceGroupCards([card])
            groupList.testing_selectRow(at: 0)
            RunLoop.current.run(until: Date().addingTimeInterval(0.35))
            tabs.view.layoutIfNeeded()

            let groupDetail = try XCTUnwrap(
                (groupsSplit.viewController(for: .secondary) as? UINavigationController)?
                    .topViewController as? NoteDetailViewController,
                "Selecting a group note must open NoteDetail in the secondary column"
            )
            groupDetail.ensureEditorContentVisible()
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            tabs.view.layoutIfNeeded()

            let groupEditorText = groupDetail.testing_editor.testing_plainText
            XCTAssertTrue(
                groupEditorText.contains("Nota do grupo"),
                "Group detail must show note title; got: \(groupEditorText.prefix(80))"
            )
            XCTAssertGreaterThan(groupDetail.testing_editor.testing_glyphCount, 10)
            XCTAssertNil(groupDetail.navigationItem.leftBarButtonItem, "No ghost displayMode button")
            XCTAssertEqual(groupList.testing_highlightedNoteId, groupNote.id)

            let groupShot = render(tabs.view, size: size, priming: groupDetail)
            write(groupShot, name: "ipad-\(orientation)-grupos-group-notes")

            // 3) Main-menu destinations (4 tabs). Under XCTest we avoid `.tabSidebar`
            // (hangs drawHierarchy); capture the tab shell with Tools selected.
            tabs.selectedIndex = 2
            tabs.view.layoutIfNeeded()
            write(render(tabs.view, size: size), name: "ipad-\(orientation)-sidebar-menu")

            window.isHidden = true
            hostWindow = nil

            // Legacy always-on menu (iOS 15–17 shell) — separate window to avoid
            // unbalanced appearance transitions from swapping mid-test.
            let legacy = PadLegacySidebarShell()
            let legacyWindow = attachWindow(root: legacy, size: size)
            legacy.loadViewIfNeeded()
            legacy.view.layoutIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            write(render(legacy.view, size: size), name: "ipad-\(orientation)-sidebar-legacy")
            legacyWindow.isHidden = true
            hostWindow = nil
        }
    }

    func testCapture_iPhone_cadernoAndGrupos() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "iPhone screenshot")

        let titled = Self.sampleNote(title: "Nota iPhone", body: "Corpo no Caderno.")
        LocalNoteCache.saveNotes([titled])
        let group = Self.sampleGroup()
        LocalSessionCache.saveGroups([group])

        let size = CGSize(width: 390, height: 844)
        let tabs = NativeRootTabBarController()
        let window = attachWindow(root: tabs, size: size)
        tabs.loadViewIfNeeded()
        tabs.view.layoutIfNeeded()
        write(render(tabs.view, size: size), name: "iphone-caderno")

        tabs.selectedIndex = 1
        if let nav = tabs.viewControllers?[1] as? UINavigationController,
           let groups = nav.viewControllers.first as? GroupsListViewController
        {
            groups.loadViewIfNeeded()
            groups.testing_replaceGroups([group])
        }
        tabs.view.layoutIfNeeded()
        write(render(tabs.view, size: size), name: "iphone-grupos")
        window.isHidden = true
        hostWindow = nil
    }

    // MARK: - Helpers

    private func attachWindow(root: UIViewController, size: CGSize) -> UIWindow {
        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window = UIWindow(windowScene: scene)
            window.frame = CGRect(origin: .zero, size: size)
        } else {
            window = UIWindow(frame: CGRect(origin: .zero, size: size))
        }
        window.rootViewController = root
        window.makeKeyAndVisible()
        hostWindow = window
        return window
    }

    private func render(_ view: UIView, size: CGSize, priming: NoteDetailViewController? = nil) -> UIImage {
        view.bounds = CGRect(origin: .zero, size: size)
        view.layoutIfNeeded()
        if let priming {
            priming.ensureEditorContentVisible()
            CATransaction.flush()
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
            view.layoutIfNeeded()
        }
        return snapshot(view, size: size)
    }

    private func snapshot(_ view: UIView, size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
        }
    }

    private func write(_ image: UIImage, name: String) {
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        guard let data = image.pngData() else { return }
        let filename = "\(name).png"
        var dirs = [
            URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("katecheo-ipad", isDirectory: true),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("artifacts", isDirectory: true),
        ]
        let cursorArtifacts = URL(fileURLWithPath: "/opt/cursor/artifacts", isDirectory: true)
        if FileManager.default.isWritableFile(atPath: "/opt/cursor")
            || FileManager.default.fileExists(atPath: "/opt/cursor/artifacts")
        {
            dirs.append(cursorArtifacts)
        }
        for dir in dirs {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(filename)
            try? data.write(to: url)
        }
    }

    private static func sampleGroup() -> NativeAPIClient.GroupDTO {
        NativeAPIClient.GroupDTO(
            id: "g-shot",
            name: "Grupo de estudo",
            description: "Captura de tela",
            visibility: "private",
            postPolicy: "members",
            createdBy: "u1",
            memberCount: 3,
            myRole: "admin",
            myStatus: "accepted",
            updatedAt: "2026-11-10T00:00:00Z",
            published: nil
        )
    }

    private static func sampleNote(title: String, body: String) -> NativeAPIClient.NoteDocument {
        var note = NativeAPIClient.emptyNote()
        note.title = title
        note.body = NativeAPIClient.NoteBody(blocks: [
            NativeAPIClient.LineBlock(
                id: UUID().uuidString.replacingOccurrences(of: "-", with: ""),
                type: "paragraph",
                spans: [
                    .init(
                        type: "text",
                        text: body,
                        marks: nil,
                        bookId: nil,
                        chapter: nil,
                        verseStart: nil,
                        verseEnd: nil,
                        href: nil
                    ),
                ],
                speakerId: nil,
                title: nil,
                collapsed: nil,
                checked: nil,
                blocks: nil
            ),
        ])
        return note
    }
}
