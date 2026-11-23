import XCTest
@testable import Katecheo

/// TF 496: iPhone Caderno push must keep the system back button + interactive pop.
/// iPad expanded split secondary still hides back (Notes-style column).
@MainActor
final class NoteDetailBackChromeTests: XCTestCase {
    func testCompactPush_showsBackButtonAndEnablesSwipePop() {
        var note = NativeAPIClient.emptyNote(id: "back-chrome-1")
        note.title = "Nota"
        let detail = NoteDetailViewController(noteId: note.id, initial: note)
        let list = UIViewController()
        list.title = "Caderno"
        list.navigationItem.backButtonTitle = "Caderno"
        let nav = UINavigationController(rootViewController: list)
        nav.pushViewController(detail, animated: false)

        detail.loadViewIfNeeded()
        detail.beginAppearanceTransition(true, animated: false)
        detail.endAppearanceTransition()
        detail.viewDidAppear(false)

        XCTAssertFalse(
            detail.navigationItem.hidesBackButton,
            "iPhone / compact push must not hide the Caderno back button"
        )
        XCTAssertEqual(
            nav.interactivePopGestureRecognizer?.isEnabled,
            true,
            "Edge swipe-back must stay enabled on compact push"
        )
        XCTAssertNil(
            detail.splitViewController,
            "Sanity: this fixture is a plain nav stack (no split)"
        )
    }
}
