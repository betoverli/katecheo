import XCTest
@testable import Katecheo

/// iPad navigation contracts: note opens in detail, group pushes notes in sidebar,
/// 4-tab / tabSidebar shell, tile split chrome. iPhone keeps 4 tabs.
@MainActor
final class IPadNavigationTests: XCTestCase {
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

    private func makePadWindow(root: UIViewController, size: CGSize = CGSize(width: 1180, height: 820)) -> UIWindow {
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

    func testPad_rootTabs_hasFourDestinations() throws {
        try XCTSkipUnless(isPad, "iPad-only tab chrome")
        let tabs = NativeRootTabBarController()
        tabs.loadViewIfNeeded()
        XCTAssertEqual(tabs.viewControllers?.count, 4)
        XCTAssertTrue(tabs.viewControllers?[0] is NotebookSplitViewController)
        XCTAssertTrue(tabs.viewControllers?[1] is GroupsSplitViewController)
        XCTAssertTrue(tabs.viewControllers?[2] is UINavigationController)
        XCTAssertTrue(tabs.viewControllers?[3] is UINavigationController)
        if #available(iOS 18.0, *) {
            XCTAssertEqual(tabs.mode, .tabSidebar)
            XCTAssertEqual(tabs.view.accessibilityIdentifier, "pad.shell.tabsidebar")
        }
    }

    func testPad_selectingNote_opensInSecondaryColumn() throws {
        try XCTSkipUnless(isPad, "iPad-only split detail routing")

        let note = NativeAPIClient.emptyNote()
        var titled = note
        titled.title = "Nota iPad"
        LocalNoteCache.saveNotes([titled])

        let tabs = NativeRootTabBarController()
        _ = makePadWindow(root: tabs)
        tabs.loadViewIfNeeded()
        tabs.view.layoutIfNeeded()

        let split = try XCTUnwrap(tabs.viewControllers?.first as? NotebookSplitViewController)
        _ = split.view
        split.view.layoutIfNeeded()
        let list = split.listViewController
        list.loadViewIfNeeded()
        list.viewWillAppear(false)
        list.view.layoutIfNeeded()
        XCTAssertGreaterThan(list.testing_filteredRowCount, 0)

        if list.splitViewController is NotebookSplitViewController {
            list.testing_selectRow(at: 0)
        } else {
            split.showNote(NoteDetailViewController(noteId: titled.id, initial: titled), animated: false)
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))

        XCTAssertEqual(split.selectedNoteId, titled.id)
        XCTAssertEqual(split.openDetailNoteId, titled.id)
        XCTAssertEqual(list.testing_highlightedNoteId, titled.id)
        XCTAssertTrue(list.testing_hasSelectedRow, "Selected Caderno row must stay highlighted")

        let detail = try XCTUnwrap(
            (split.viewController(for: .secondary) as? UINavigationController)?
                .topViewController as? NoteDetailViewController
        )
        detail.ensureEditorContentVisible()
        XCTAssertTrue(
            detail.testing_editor.testing_plainText.contains("Nota iPad"),
            "Detail editor must show the selected note title"
        )
        XCTAssertNil(
            detail.navigationItem.leftBarButtonItem,
            "Secondary must not show the empty displayMode circle"
        )
    }

    func testPad_selectingGroup_pushesNotesInSidebar() throws {
        try XCTSkipUnless(isPad, "iPad-only groups double column")

        let group = Self.sampleGroup()
        LocalSessionCache.saveGroups([group])

        let tabs = NativeRootTabBarController()
        _ = makePadWindow(root: tabs)
        tabs.loadViewIfNeeded()
        tabs.view.layoutIfNeeded()
        tabs.selectedIndex = 1

        let split = try XCTUnwrap(tabs.viewControllers?[1] as? GroupsSplitViewController)
        XCTAssertEqual(split.style, .doubleColumn)
        _ = split.view
        split.view.layoutIfNeeded()
        let groups = split.groupsListViewController
        groups.loadViewIfNeeded()
        groups.testing_replaceGroups([group])
        XCTAssertEqual(groups.testing_filteredCount, 1)

        if groups.splitViewController is GroupsSplitViewController {
            groups.testing_selectRow(at: 0)
        } else {
            split.showGroup(group, animated: false)
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))

        XCTAssertEqual(split.selectedGroupId, group.id)
        XCTAssertNotNil(split.openGroupNotesList)
        XCTAssertEqual(split.openGroupNotesList?.testing_groupId, group.id)
    }

    func testPad_toolsAndProfile_areTabsNotSheets() throws {
        try XCTSkipUnless(isPad, "iPad-only Tools/Profile tabs")

        let tabs = NativeRootTabBarController()
        _ = makePadWindow(root: tabs)
        tabs.loadViewIfNeeded()

        tabs.presentToolsSheet(animated: false)
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(tabs.selectedIndex, 2)
        XCTAssertNil(tabs.presentedViewController, "Tools is a tab, not a modal sheet")
        XCTAssertTrue(
            (tabs.selectedViewController as? UINavigationController)?.viewControllers.first is VersesHomeViewController
        )

        tabs.presentProfileSheet(animated: false)
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(tabs.selectedIndex, 3)
        XCTAssertNil(tabs.presentedViewController, "Profile is a tab, not a modal sheet")
        XCTAssertTrue(
            (tabs.selectedViewController as? UINavigationController)?.viewControllers.first is ProfileViewController
        )
    }

    func testPad_notebookSplit_tilesBesideNeverOverlay() throws {
        try XCTSkipUnless(isPad, "iPad-only column metrics")
        let split = NotebookSplitViewController()
        _ = makePadWindow(root: split)
        _ = split.view
        split.view.layoutIfNeeded()
        XCTAssertEqual(split.preferredPrimaryColumnWidthFraction, PadChrome.notebookPrimaryFraction, accuracy: 0.001)
        XCTAssertEqual(split.minimumPrimaryColumnWidth, PadChrome.notebookPrimaryMin)
        XCTAssertEqual(split.maximumPrimaryColumnWidth, PadChrome.notebookPrimaryMax)
        XCTAssertEqual(split.preferredDisplayMode, .oneBesideSecondary)
        if #available(iOS 16.0, *) {
            XCTAssertEqual(split.preferredSplitBehavior, .tile)
        }
        XCTAssertNotEqual(split.displayMode, .oneOverSecondary)
        XCTAssertNotEqual(split.displayMode, .primaryOverlay)
    }

    func testPad_groupsSplit_isDoubleColumn() throws {
        try XCTSkipUnless(isPad, "iPad-only double column")
        let split = GroupsSplitViewController()
        _ = split.view
        XCTAssertEqual(split.style, .doubleColumn)
        XCTAssertEqual(split.preferredPrimaryColumnWidthFraction, PadChrome.notebookPrimaryFraction, accuracy: 0.001)
        if #available(iOS 16.0, *) {
            XCTAssertEqual(split.preferredSplitBehavior, .tile)
        }
    }

    func testPad_listRoots_preferLargeTitles() throws {
        try XCTSkipUnless(isPad, "iPad list title chrome")
        let caderno = NotebookListViewController()
        let grupos = GroupsListViewController()
        let tools = VersesHomeViewController()
        let profile = ProfileViewController()
        for root in [caderno as UIViewController, grupos, tools, profile] {
            let nav = UINavigationController(rootViewController: root)
            KCChrome.style(navigationController: nav)
            _ = makePadWindow(root: nav)
            root.loadViewIfNeeded()
            root.viewWillAppear(false)
            XCTAssertTrue(nav.navigationBar.prefersLargeTitles, "\(type(of: root)) nav prefers large titles")
            XCTAssertEqual(
                root.navigationItem.largeTitleDisplayMode,
                .always,
                "\(type(of: root)) largeTitleDisplayMode must be .always"
            )
        }
    }

    func testPhone_stillHasFourTabs() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "iPhone tab contract")
        let tabs = NativeRootTabBarController()
        tabs.loadViewIfNeeded()
        XCTAssertEqual(tabs.viewControllers?.count, 4)
    }

    private static func sampleGroup() -> NativeAPIClient.GroupDTO {
        NativeAPIClient.GroupDTO(
            id: "g-ipad-1",
            name: "Grupo iPad",
            description: "",
            visibility: "private",
            postPolicy: "members",
            createdBy: "u1",
            memberCount: 1,
            myRole: "admin",
            myStatus: "accepted",
            updatedAt: "2026-11-10T00:00:00Z",
            published: nil
        )
    }
}
