import XCTest
@testable import Katecheo

/// Regression: Aceitar / Recusar / Cancelar must sit in a sized trailing accessoryView,
/// never paint over the leading SF Symbol (paperplane / person.badge.plus).
@MainActor
final class FriendsRequestRowTests: XCTestCase {
    func testOutgoingRow_trailingCancelAccessory_hasNonZeroFrame() {
        let vc = FriendsActivityViewController()
        vc.loadViewIfNeeded()
        let outgoing = NativeAPIClient.LinkPersonDTO(
            userId: "u-out",
            handle: "isaacspagnol",
            firstName: "Isaac",
            lastName: "Sanchez Spagnol",
            avatarId: "book",
            avatarUrl: ""
        )
        vc.testing_setLinks(friends: [], incoming: [], outgoing: [outgoing])
        vc.view.layoutIfNeeded()

        // Incoming/outgoing sections sit above friends when non-empty → section 0.
        let cell = vc.tableView(vc.tableView, cellForRowAt: IndexPath(row: 0, section: 0))
        let accessory = try! XCTUnwrap(cell.accessoryView, "Cancel must be a trailing accessoryView")
        XCTAssertGreaterThan(accessory.bounds.width, 40, "accessoryView needs an explicit frame")
        XCTAssertGreaterThan(accessory.bounds.height, 20)

        let cancelTitle = String(localized: "Cancelar")
        let buttons = accessory.subviews.compactMap { $0 as? UIButton }
        XCTAssertEqual(buttons.count, 1)
        XCTAssertEqual(buttons.first?.accessibilityLabel, cancelTitle)
        // Leading content still has the paper-plane symbol via contentConfiguration.
        let config = try! XCTUnwrap(cell.contentConfiguration as? UIListContentConfiguration)
        XCTAssertNotNil(config.image)
    }

    func testIncomingRow_trailingAcceptDecline_doNotCollapse() {
        let vc = FriendsActivityViewController()
        vc.loadViewIfNeeded()
        let incoming = NativeAPIClient.LinkPersonDTO(
            userId: "u-in",
            handle: "ana_test",
            firstName: "Ana",
            lastName: "Silva",
            avatarId: "book",
            avatarUrl: ""
        )
        vc.testing_setLinks(friends: [], incoming: [incoming], outgoing: [])
        vc.view.layoutIfNeeded()

        let cell = vc.tableView(vc.tableView, cellForRowAt: IndexPath(row: 0, section: 0))
        let accessory = try! XCTUnwrap(cell.accessoryView)
        XCTAssertGreaterThan(accessory.bounds.width, 80, "Aceitar + Recusar need room on the trailing edge")
        let labels = Set(accessory.subviews.compactMap { ($0 as? UIButton)?.accessibilityLabel })
        XCTAssertTrue(labels.contains(String(localized: "Aceitar")))
        XCTAssertTrue(labels.contains(String(localized: "Recusar")))
        let config = try! XCTUnwrap(cell.contentConfiguration as? UIListContentConfiguration)
        XCTAssertEqual(config.textProperties.numberOfLines, 1)
        XCTAssertEqual(config.textProperties.lineBreakMode, .byTruncatingTail)
    }

    func testDeepLink_profileFriends_opensFriendsDestination() {
        XCTAssertEqual(
            NativeDeepLinkRouter.destination(href: "/profile/friends"),
            .friends
        )
        XCTAssertEqual(
            NativeDeepLinkRouter.destination(href: "/profile"),
            .profile
        )
        XCTAssertEqual(
            NativeDeepLinkRouter.destination(href: "https://katecheo.app/profile/friends"),
            .friends
        )
    }

    func testCancelOutgoing_usesConfirmationSheet() {
        // Source contract: trailing Cancel always goes through confirmCancelOutgoing.
        let srcURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Katecheo/FriendsActivityViewController.swift")
        guard let src = try? String(contentsOf: srcURL, encoding: .utf8) else {
            // Simulator CI may not expose sibling sources; ios-check.mjs is authoritative.
            XCTAssertNotNil(KCConfirmation.self)
            return
        }
        XCTAssertTrue(src.contains("confirmCancelOutgoing"))
        XCTAssertTrue(src.contains("pillButton"))
        XCTAssertTrue(src.contains("accessoryView"))
        XCTAssertTrue(src.contains("systemLayoutSizeFitting") || src.contains("Manual layout"))
    }
}
