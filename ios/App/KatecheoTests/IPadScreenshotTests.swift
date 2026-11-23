import XCTest
@testable import Katecheo

/// Captures iPad landscape + portrait screenshots of Caderno (note open with text),
/// Grupos 2-column (list + after group push with note), Tools sheet, Profile sheet,
/// plus iPhone Caderno/Grupos shots on phone destinations.
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
            title: "Estudo no iPad",
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

            // 1) Caderno with a note open — title + body must be visible in the editor.
            let split = try XCTUnwrap(tabs.viewControllers?.first as? NotebookSplitViewController)
            let detail = NoteDetailViewController(noteId: titled.id, initial: titled)
            split.showNote(detail, animated: false)
            detail.loadViewIfNeeded()
            detail.view.layoutIfNeeded()
            detail.testing_editor.layoutIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
            tabs.view.layoutIfNeeded()
            let editorText = detail.testing_editor.testing_plainText
            XCTAssertTrue(
                editorText.contains("Estudo no iPad"),
                "Caderno detail must show note title; got: \(editorText.prefix(80))"
            )
            write(render(tabs.view, size: size), name: "ipad-\(orientation)-caderno-note")

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
            let groupDetail = NoteDetailViewController(noteId: groupNote.id, initial: groupNote)
            groupsSplit.showNote(groupDetail, animated: false)
            groupDetail.loadViewIfNeeded()
            groupDetail.view.layoutIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            tabs.view.layoutIfNeeded()
            write(render(tabs.view, size: size), name: "ipad-\(orientation)-grupos-group-notes")

            // 3) Tools sheet with visible content (Books empty-state or rows — not blank beige).
            tabs.selectedIndex = 0
            UserDefaults.standard.set("books", forKey: "katecheo.ferramentas.lastTool")
            tabs.presentToolsSheet(animated: false) { home in
                home.testing_selectToolAndLayout("books")
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            let toolsNav = try XCTUnwrap(tabs.presentedViewController as? UINavigationController)
            XCTAssertEqual(toolsNav.view.accessibilityIdentifier, "pad.sheet.tools")
            toolsNav.view.layoutIfNeeded()
            write(
                render(toolsNav.view, size: PadChrome.utilitySheetSize),
                name: "ipad-\(orientation)-tools-sheet"
            )

            // 4) Profile sheet — must be Perfil, not Caderno / leftover Tools.
            // presentProfileSheet dismisses Tools in its completion before presenting.
            tabs.presentProfileSheet(animated: false)
            var profileNav: UINavigationController?
            for _ in 0 ..< 20 {
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
                if let nav = tabs.presentedViewController as? UINavigationController,
                   nav.view.accessibilityIdentifier == "pad.sheet.profile"
                {
                    profileNav = nav
                    break
                }
            }
            let profile = try XCTUnwrap(profileNav, "Profile sheet must replace Tools sheet")
            XCTAssertEqual(profile.view.accessibilityIdentifier, "pad.sheet.profile")
            XCTAssertTrue(profile.viewControllers.first is ProfileViewController)
            profile.viewControllers.first?.loadViewIfNeeded()
            profile.view.layoutIfNeeded()
            write(
                render(profile.view, size: PadChrome.utilitySheetSize),
                name: "ipad-\(orientation)-profile-sheet"
            )
            tabs.dismiss(animated: false)
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))

            window.isHidden = true
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

    private func render(_ view: UIView, size: CGSize) -> UIImage {
        view.bounds = CGRect(origin: .zero, size: size)
        view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
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
