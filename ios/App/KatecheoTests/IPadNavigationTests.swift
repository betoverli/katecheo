import XCTest
@testable import Katecheo

/// iPad navigation contracts: note opens in detail, group shows notes, Tools/Profile sheets.
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

    private func makePadWindow(root: UIViewController) -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1180, height: 820))
        window.rootViewController = root
        window.makeKeyAndVisible()
        hostWindow = window
        return window
    }

    func testPad_rootTabs_onlyCadernoAndGrupos() throws {
        try XCTSkipUnless(isPad, "iPad-only tab chrome")
        let tabs = NativeRootTabBarController()
        tabs.loadViewIfNeeded()
        XCTAssertEqual(tabs.viewControllers?.count, 2)
        XCTAssertTrue(tabs.viewControllers?[0] is NotebookSplitViewController)
        XCTAssertTrue(tabs.viewControllers?[1] is GroupsSplitViewController)
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

        let split = try XCTUnwrap(tabs.viewControllers?.first as? NotebookSplitViewController)
        let list = split.listViewController
        list.loadViewIfNeeded()
        list.viewWillAppear(false)
        list.view.layoutIfNeeded()
        XCTAssertGreaterThan(list.testing_filteredRowCount, 0)

        list.testing_selectRow(at: 0)
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))

        XCTAssertEqual(split.selectedNoteId, titled.id)
        XCTAssertEqual(split.openDetailNoteId, titled.id)
    }

    func testPad_selectingGroup_showsGroupNotesColumn() throws {
        try XCTSkipUnless(isPad, "iPad-only groups triple column")

        let group = Self.sampleGroup()
        LocalSessionCache.saveGroups([group])

        let tabs = NativeRootTabBarController()
        _ = makePadWindow(root: tabs)
        tabs.loadViewIfNeeded()
        tabs.selectedIndex = 1

        let split = try XCTUnwrap(tabs.viewControllers?[1] as? GroupsSplitViewController)
        let groups = split.groupsListViewController
        groups.loadViewIfNeeded()
        groups.testing_replaceGroups([group])
        XCTAssertEqual(groups.testing_filteredCount, 1)

        groups.testing_selectRow(at: 0)
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))

        XCTAssertEqual(split.selectedGroupId, group.id)
    }

    func testPad_toolsButton_presentsToolsSheet() throws {
        try XCTSkipUnless(isPad, "iPad-only Tools sheet")

        let tabs = NativeRootTabBarController()
        _ = makePadWindow(root: tabs)
        tabs.loadViewIfNeeded()

        tabs.presentToolsSheet(animated: false)
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))

        let presented = try XCTUnwrap(tabs.presentedViewController as? UINavigationController)
        XCTAssertEqual(presented.view.accessibilityIdentifier, "pad.sheet.tools")
        XCTAssertTrue(presented.viewControllers.first is VersesHomeViewController)
        XCTAssertEqual(presented.modalPresentationStyle, .formSheet)
    }

    func testPad_profileButton_presentsProfileSheet() throws {
        try XCTSkipUnless(isPad, "iPad-only Profile sheet")

        let tabs = NativeRootTabBarController()
        _ = makePadWindow(root: tabs)
        tabs.loadViewIfNeeded()

        tabs.presentProfileSheet(animated: false)
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))

        let presented = try XCTUnwrap(tabs.presentedViewController as? UINavigationController)
        XCTAssertEqual(presented.view.accessibilityIdentifier, "pad.sheet.profile")
        XCTAssertTrue(presented.viewControllers.first is ProfileViewController)
        XCTAssertEqual(presented.modalPresentationStyle, .formSheet)
    }

    func testPad_notebookSplit_usesNotesLikePrimaryWidth() throws {
        try XCTSkipUnless(isPad, "iPad-only column metrics")
        let split = NotebookSplitViewController()
        _ = split.view
        XCTAssertEqual(split.preferredPrimaryColumnWidthFraction, PadChrome.notebookPrimaryFraction, accuracy: 0.001)
        XCTAssertEqual(split.minimumPrimaryColumnWidth, PadChrome.notebookPrimaryMin)
        XCTAssertEqual(split.maximumPrimaryColumnWidth, PadChrome.notebookPrimaryMax)
    }

    func testPad_groupsSplit_isTripleColumn() throws {
        try XCTSkipUnless(isPad, "iPad-only triple column")
        let split = GroupsSplitViewController()
        _ = split.view
        XCTAssertEqual(split.style, .tripleColumn)
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
