import XCTest
@testable import Katecheo

/// Caderno routing: iPhone keeps pre-#131 push nav; iPad uses Notes-style split.
@MainActor
final class NotebookSplitRoutingTests: XCTestCase {
    private var hostWindow: UIWindow?

    override func tearDown() async throws {
        hostWindow?.isHidden = true
        hostWindow = nil
        LocalNoteCache.saveNotes([])
        LocalSessionCache.clearGroups()
        try await super.tearDown()
    }

    private var isPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    // MARK: - Idiom factory

    func testPrefersSplit_onlyOnIPad() {
        XCTAssertEqual(NotebookChrome.prefersSplit, isPad)
        XCTAssertNotEqual(NotebookChrome.prefersSplit, isPhone && !isPad)
    }

    func testMakeTabRoot_phoneUsesNavigationWithList() throws {
        try XCTSkipUnless(isPhone, "iPhone-only hierarchy contract (TF 460 regression)")
        let root = NotebookChrome.makeTabRoot()
        let nav = try XCTUnwrap(root as? UINavigationController)
        XCTAssertTrue(nav.viewControllers.first is NotebookListViewController)
        XCTAssertFalse(root is NotebookSplitViewController)
    }

    func testMakeTabRoot_padUsesSplit() throws {
        try XCTSkipUnless(isPad, "iPad-only split chrome")
        XCTAssertTrue(NotebookChrome.makeTabRoot() is NotebookSplitViewController)
    }

    func testMakeGroupCaderno_phoneUsesListNotSplit() throws {
        try XCTSkipUnless(isPhone, "iPhone-only group Caderno")
        let group = Self.sampleGroup()
        let vc = NotebookChrome.makeGroupCaderno(group: group)
        XCTAssertTrue(vc is NotebookListViewController)
        XCTAssertFalse(vc is NotebookSplitViewController)
    }

    // MARK: - Real window: note open on iPhone

    func testPhone_selectingNoteRow_pushesNoteDetailOntoNavStack() throws {
        try XCTSkipUnless(isPhone, "must run on iPhone simulator in CI")

        let note = NativeAPIClient.emptyNote()
        var titled = note
        titled.title = "Nota de teste"
        LocalNoteCache.saveNotes([titled])

        let tabs = NativeRootTabBarController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = tabs
        window.makeKeyAndVisible()
        hostWindow = window
        tabs.loadViewIfNeeded()

        let nav = try XCTUnwrap(tabs.viewControllers?.first as? UINavigationController)
        let list = try XCTUnwrap(nav.viewControllers.first as? NotebookListViewController)
        list.loadViewIfNeeded()
        list.viewWillAppear(false)
        list.view.layoutIfNeeded()

        let rows = list.tableView(list.tableView, numberOfRowsInSection: 0)
        XCTAssertGreaterThan(rows, 0, "seeded note must appear in Caderno")

        list.tableView(list.tableView, didSelectRowAt: IndexPath(row: 0, section: 0))
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))

        let top = try XCTUnwrap(nav.topViewController as? NoteDetailViewController)
        XCTAssertEqual(top.openedNoteId, titled.id)
        XCTAssertTrue(top.hidesBottomBarWhenPushed, "compact push must hide the tab bar")
        XCTAssertEqual(nav.viewControllers.count, 2)
    }

    // MARK: - Real window: group open on iPhone

    func testPhone_selectingGroupRow_pushesGroupCadernoList() throws {
        try XCTSkipUnless(isPhone, "must run on iPhone simulator in CI")

        let group = Self.sampleGroup()
        LocalSessionCache.saveGroups([group])

        let tabs = NativeRootTabBarController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = tabs
        window.makeKeyAndVisible()
        hostWindow = window
        tabs.loadViewIfNeeded()
        tabs.selectedIndex = 1

        let nav = try XCTUnwrap(tabs.viewControllers?[1] as? UINavigationController)
        let groups = try XCTUnwrap(nav.viewControllers.first as? GroupsListViewController)
        groups.loadViewIfNeeded()
        // Avoid viewWillAppear network wipe — seed after load.
        groups.testing_replaceGroups([group])
        XCTAssertEqual(groups.testing_filteredCount, 1)

        groups.tableView(groups.tableView, didSelectRowAt: IndexPath(row: 0, section: 0))
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))

        let top = try XCTUnwrap(nav.topViewController as? NotebookListViewController)
        XCTAssertEqual(top.title, group.name)
        XCTAssertFalse(nav.topViewController is NotebookSplitViewController)
        XCTAssertEqual(nav.viewControllers.count, 2)
    }

    func testPhone_rootTabs_useNavigationNotSplit() throws {
        try XCTSkipUnless(isPhone, "iPhone root chrome")
        let tabs = NativeRootTabBarController()
        tabs.loadViewIfNeeded()
        XCTAssertTrue(tabs.viewControllers?.first is UINavigationController)
        XCTAssertFalse(tabs.viewControllers?.first is NotebookSplitViewController)
    }

    // MARK: - Split (iPad) smoke

    func testSplit_initializesWithListAndEmptyDetail() throws {
        try XCTSkipUnless(isPad, "split is iPad-only")
        let split = NotebookSplitViewController()
        _ = split.view
        XCTAssertNotNil(split.listViewController)
        XCTAssertNil(split.selectedNoteId)
    }

    func testShowNote_setsSelectedNoteId() throws {
        try XCTSkipUnless(isPad, "split is iPad-only")
        let split = NotebookSplitViewController()
        _ = split.view
        let note = NativeAPIClient.emptyNote()
        let detail = NoteDetailViewController(noteId: note.id, initial: note)
        split.showNote(detail, animated: false)
        XCTAssertEqual(split.selectedNoteId, note.id)
    }

    func testShowEmptyDetail_clearsSelection() throws {
        try XCTSkipUnless(isPad, "split is iPad-only")
        let split = NotebookSplitViewController()
        _ = split.view
        let note = NativeAPIClient.emptyNote()
        split.showNote(NoteDetailViewController(noteId: note.id, initial: note), animated: false)
        split.showEmptyDetail(animated: false)
        XCTAssertNil(split.selectedNoteId)
    }

    func testDeepLinkRouter_mapsNotebookPaths() {
        XCTAssertEqual(NativeDeepLinkRouter.destination(href: "/notebook"), .notebook)
        XCTAssertEqual(NativeDeepLinkRouter.destination(href: "/notebook/abc123"), .note(id: "abc123"))
    }

    func testNoteDetail_hidesBottomBarByDefaultForCompactPush() {
        let note = NativeAPIClient.emptyNote()
        let detail = NoteDetailViewController(noteId: note.id, initial: note)
        XCTAssertTrue(detail.hidesBottomBarWhenPushed)
        detail.applyTabBarHidingForSplit(isCollapsed: false)
        XCTAssertFalse(detail.hidesBottomBarWhenPushed)
        detail.applyTabBarHidingForSplit(isCollapsed: true)
        XCTAssertTrue(detail.hidesBottomBarWhenPushed)
    }

    func testGroupSplit_wrapsGroupList() throws {
        try XCTSkipUnless(isPad, "split is iPad-only")
        let split = NotebookSplitViewController(group: Self.sampleGroup())
        _ = split.view
        split.listViewController.loadViewIfNeeded()
        XCTAssertEqual(split.listViewController.title, "Grupo")
    }

    private static func sampleGroup() -> NativeAPIClient.GroupDTO {
        NativeAPIClient.GroupDTO(
            id: "g1",
            name: "Grupo",
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
