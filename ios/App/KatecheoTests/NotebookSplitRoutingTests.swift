import XCTest
@testable import Katecheo

/// Caderno split: regular shows detail in secondary; compact pushes like today.
@MainActor
final class NotebookSplitRoutingTests: XCTestCase {
    func testSplit_initializesWithListAndEmptyDetail() {
        let split = NotebookSplitViewController()
        _ = split.view
        XCTAssertNotNil(split.listViewController)
        XCTAssertNil(split.selectedNoteId)
        XCTAssertTrue(split.viewControllers.count >= 1 || split.viewController(for: .primary) != nil)
    }

    func testShowNote_setsSelectedNoteId() {
        let split = NotebookSplitViewController()
        _ = split.view
        let note = NativeAPIClient.emptyNote()
        let detail = NoteDetailViewController(noteId: note.id, initial: note)
        split.showNote(detail, animated: false)
        XCTAssertEqual(split.selectedNoteId, note.id)
        XCTAssertEqual(detail.openedNoteId, note.id)
    }

    func testShowEmptyDetail_clearsSelection() {
        let split = NotebookSplitViewController()
        _ = split.view
        let note = NativeAPIClient.emptyNote()
        split.showNote(NoteDetailViewController(noteId: note.id, initial: note), animated: false)
        XCTAssertEqual(split.selectedNoteId, note.id)
        split.showEmptyDetail(animated: false)
        XCTAssertNil(split.selectedNoteId)
    }

    func testClearDetailAfterDeletingNote_matchesOpenNote() {
        let split = NotebookSplitViewController()
        _ = split.view
        let note = NativeAPIClient.emptyNote()
        split.showNote(NoteDetailViewController(noteId: note.id, initial: note), animated: false)
        split.clearDetailAfterDeletingNote(id: note.id)
        XCTAssertNil(split.selectedNoteId)
    }

    func testDeepLinkRouter_mapsNotebookPaths() {
        XCTAssertEqual(
            NativeDeepLinkRouter.destination(href: "/notebook"),
            .notebook
        )
        let noteDest = NativeDeepLinkRouter.destination(href: "/notebook/abc123")
        XCTAssertEqual(noteDest, .note(id: "abc123"))
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

    func testRootTabs_useNotebookSplit() {
        let tabs = NativeRootTabBarController()
        _ = tabs.view
        XCTAssertTrue(tabs.viewControllers?.first is NotebookSplitViewController)
    }

    func testGroupSplit_wrapsGroupList() {
        let group = NativeAPIClient.GroupDTO(
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
        let split = NotebookSplitViewController(group: group)
        _ = split.view
        split.listViewController.loadViewIfNeeded()
        XCTAssertEqual(split.listViewController.title, "Grupo")
    }
}
