import XCTest
@testable import App

/// Icon-only swipe actions (Mail/Notes style) — title nil, localized a11y label.
@MainActor
final class KCSwipeActionTests: XCTestCase {
    func testIconOnly_shareAndDeleteHaveNilTitleAndLocalizedA11y() {
        let share = UIContextualAction.kcIconOnly(
            style: .normal,
            systemName: "square.and.arrow.up",
            accessibilityLabel: String(localized: "Compartilhar"),
            backgroundColor: KCDesign.bookmark
        ) { _, _, done in done(true) }

        XCTAssertNil(share.title)
        XCTAssertNotNil(share.image)
        XCTAssertEqual(share.accessibilityLabel, String(localized: "Compartilhar"))
        XCTAssertEqual(share.backgroundColor, KCDesign.bookmark)

        let delete = UIContextualAction.kcIconOnly(
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
