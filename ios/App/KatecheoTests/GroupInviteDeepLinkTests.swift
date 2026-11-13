import XCTest
@testable import Katecheo

final class GroupInviteDeepLinkTests: XCTestCase {
    func testDeepLink_groupInvite_opensInviteDestinationNotProfile() {
        XCTAssertEqual(
            NativeDeepLinkRouter.destination(href: "/groups/invite/abc123"),
            .groupInvite(id: "abc123")
        )
        XCTAssertEqual(
            NativeDeepLinkRouter.destination(href: "https://katecheo.app/groups/invite/abc123"),
            .groupInvite(id: "abc123")
        )
        XCTAssertNotEqual(
            NativeDeepLinkRouter.destination(href: "/groups/invite/abc123"),
            .profile
        )
        XCTAssertNotEqual(
            NativeDeepLinkRouter.destination(href: "/groups/invite/abc123"),
            .friends
        )
    }

    func testDeepLink_groupId_stillOpensGroup() {
        XCTAssertEqual(
            NativeDeepLinkRouter.destination(href: "/groups/g1"),
            .group(id: "g1")
        )
        XCTAssertEqual(
            NativeDeepLinkRouter.destination(href: "/groups"),
            .groups
        )
    }
}
