import XCTest
@testable import Katecheo

/// Captures iPad landscape + portrait screenshots of Caderno (note open), Grupos triple column,
/// Tools sheet, and Profile sheet. PNGs land in CI artifacts and `/opt/cursor/artifacts`.
@MainActor
final class IPadScreenshotTests: XCTestCase {
    private var hostWindow: UIWindow?

    override func tearDown() async throws {
        hostWindow?.rootViewController?.dismiss(animated: false)
        hostWindow?.isHidden = true
        hostWindow = nil
        LocalNoteCache.saveNotes([])
        LocalSessionCache.clearGroups()
        try await super.tearDown()
    }

    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    func testCapture_iPadChrome_landscapeAndPortrait() throws {
        try XCTSkipUnless(isPad, "Screenshot suite runs on iPad Simulator in CI")

        let note = NativeAPIClient.emptyNote()
        var titled = note
        titled.title = "Estudo no iPad"
        titled.preview = "Margens Notes-like e coluna secundária preenchida."
        LocalNoteCache.saveNotes([titled])

        let group = NativeAPIClient.GroupDTO(
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
        LocalSessionCache.saveGroups([group])

        let sizes: [(String, CGSize)] = [
            ("landscape", CGSize(width: 1180, height: 820)),
            ("portrait", CGSize(width: 820, height: 1180)),
        ]

        for (orientation, size) in sizes {
            let tabs = NativeRootTabBarController()
            let window = UIWindow(frame: CGRect(origin: .zero, size: size))
            window.rootViewController = tabs
            window.makeKeyAndVisible()
            hostWindow = window
            tabs.loadViewIfNeeded()
            tabs.view.layoutIfNeeded()

            // 1) Caderno with a note open
            let split = try XCTUnwrap(tabs.viewControllers?.first as? NotebookSplitViewController)
            let list = split.listViewController
            list.loadViewIfNeeded()
            list.viewWillAppear(false)
            list.view.layoutIfNeeded()
            if list.testing_filteredRowCount > 0 {
                list.testing_selectRow(at: 0)
            } else {
                split.showNote(NoteDetailViewController(noteId: titled.id, initial: titled), animated: false)
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            tabs.view.layoutIfNeeded()
            write(render(tabs.view, size: size), name: "ipad-\(orientation)-caderno-note")

            // 2) Grupos triple column with a group selected
            tabs.selectedIndex = 1
            let groupsSplit = try XCTUnwrap(tabs.viewControllers?[1] as? GroupsSplitViewController)
            groupsSplit.groupsListViewController.loadViewIfNeeded()
            groupsSplit.groupsListViewController.testing_replaceGroups([group])
            groupsSplit.showGroup(group, animated: false)
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            tabs.view.layoutIfNeeded()
            write(render(tabs.view, size: size), name: "ipad-\(orientation)-grupos-triple")

            // 3) Tools sheet
            tabs.selectedIndex = 0
            tabs.presentToolsSheet(animated: false)
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
            if let sheet = tabs.presentedViewController?.view {
                write(render(sheet, size: PadChrome.utilitySheetSize), name: "ipad-\(orientation)-tools-sheet")
            } else {
                write(render(tabs.view, size: size), name: "ipad-\(orientation)-tools-sheet")
            }
            tabs.dismiss(animated: false)
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))

            // 4) Profile sheet
            tabs.presentProfileSheet(animated: false)
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
            if let sheet = tabs.presentedViewController?.view {
                write(render(sheet, size: PadChrome.utilitySheetSize), name: "ipad-\(orientation)-profile-sheet")
            } else {
                write(render(tabs.view, size: size), name: "ipad-\(orientation)-profile-sheet")
            }
            tabs.dismiss(animated: false)

            hostWindow?.isHidden = true
            hostWindow = nil
        }
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
        let dirs = [
            URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("katecheo-ipad", isDirectory: true),
            URL(fileURLWithPath: "/opt/cursor/artifacts", isDirectory: true),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("artifacts", isDirectory: true),
        ]
        for dir in dirs {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(filename)
            try? data.write(to: url)
        }
    }
}
