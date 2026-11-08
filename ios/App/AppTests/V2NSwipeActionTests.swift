import XCTest
@testable import App

/// Icon-only swipe actions (Mail/Notes style) — title nil, localized a11y label.
@MainActor
final class V2NSwipeActionTests: XCTestCase {
    func testIconOnly_shareAndDeleteHaveNilTitleAndLocalizedA11y() {
        let share = UIContextualAction.v2nIconOnly(
            style: .normal,
            systemName: "square.and.arrow.up",
            accessibilityLabel: String(localized: "Compartilhar"),
            backgroundColor: V2NDesign.bookmark
        ) { _, _, done in done(true) }

        XCTAssertNil(share.title)
        XCTAssertNotNil(share.image)
        XCTAssertEqual(share.accessibilityLabel, String(localized: "Compartilhar"))
        XCTAssertEqual(share.backgroundColor, V2NDesign.bookmark)

        let delete = UIContextualAction.v2nIconOnly(
            style: .destructive,
            systemName: "trash",
            accessibilityLabel: String(localized: "Excluir")
        ) { _, _, done in done(true) }

        XCTAssertNil(delete.title)
        XCTAssertNotNil(delete.image)
        XCTAssertEqual(delete.accessibilityLabel, String(localized: "Excluir"))
        XCTAssertEqual(delete.style, .destructive)
    }
}
