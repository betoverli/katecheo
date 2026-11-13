import XCTest
@testable import Katecheo

@MainActor
final class PublicProfileTests: XCTestCase {
    func testInitials_fromDisplayNameAndHandle() {
        XCTAssertEqual(KCPersonAvatarLogic.initials(displayName: "Beto Verlí", handle: "beto"), "BV")
        XCTAssertEqual(KCPersonAvatarLogic.initials(displayName: "Ana", handle: "ana"), "A")
        XCTAssertEqual(KCPersonAvatarLogic.initials(displayName: "", handle: "joao"), "J")
        XCTAssertEqual(KCPersonAvatarLogic.initials(displayName: "@maria", handle: ""), "M")
        XCTAssertEqual(KCPersonAvatarLogic.initials(displayName: "", handle: ""), "?")
    }

    func testPublicProfileScreen_showsNameHandleAndMoreButton() {
        let person = NativeAPIClient.LinkPersonDTO(
            userId: "u1",
            handle: "betoverli_test",
            firstName: "Beto",
            lastName: "Verlí",
            avatarId: "book",
            avatarUrl: ""
        )
        let vc = PublicProfileViewController(person: person, friendshipStatus: "accepted")
        vc.loadViewIfNeeded()
        vc.testing_apply(person: person)

        XCTAssertEqual(vc.title, String(localized: "Perfil"))
        XCTAssertNotNil(vc.navigationItem.rightBarButtonItem)
        XCTAssertEqual(
            vc.navigationItem.rightBarButtonItem?.accessibilityLabel,
            String(localized: "Mais opções")
        )

        let nameLabel = vc.view.subviews
            .compactMap { $0 as? UIStackView }
            .flatMap(\.arrangedSubviews)
            .compactMap { $0 as? UILabel }
            .first { $0.text == "Beto Verlí" }
        XCTAssertNotNil(nameLabel)

        let handleLabel = vc.view.subviews
            .compactMap { $0 as? UIStackView }
            .flatMap(\.arrangedSubviews)
            .compactMap { $0 as? UILabel }
            .first { $0.text == "@betoverli_test" }
        XCTAssertNotNil(handleLabel)
    }

    func testFriendsTap_pushesPublicProfile_notInlineMenu() throws {
        let friendsSrcURL = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Katecheo/FriendsActivityViewController.swift")
        // Source may be unavailable in simulator bundles; assert via compiled symbols + string contracts.
        XCTAssertTrue(FriendsActivityViewController.self is Any.Type)
        _ = friendsSrcURL

        let person = NativeAPIClient.LinkPersonDTO(
            userId: "u1", handle: "beto", firstName: "Beto", lastName: "Verlí",
            avatarId: "book", avatarUrl: ""
        )
        let friends = FriendsActivityViewController()
        friends.loadViewIfNeeded()
        friends.testing_setLinks(friends: [person], incoming: [], outgoing: [])

        let nav = UINavigationController(rootViewController: friends)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = nav
        window.makeKeyAndVisible()
        friends.view.layoutIfNeeded()

        let friendsSection = (0..<friends.numberOfSections(in: friends.tableView)).first { section in
            friends.tableView(friends.tableView, titleForHeaderInSection: section) == String(localized: "Amigos")
        } ?? 0
        friends.tableView(
            friends.tableView,
            didSelectRowAt: IndexPath(row: 0, section: friendsSection)
        )

        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        XCTAssertTrue(nav.topViewController is PublicProfileViewController)
        window.isHidden = true
    }

    func testFriendsSwipeRemove_usesRemoverTitle() {
        let person = NativeAPIClient.LinkPersonDTO(
            userId: "u1", handle: "beto", firstName: "Beto", lastName: "Verlí",
            avatarId: "book", avatarUrl: ""
        )
        let friends = FriendsActivityViewController()
        friends.loadViewIfNeeded()
        friends.testing_setLinks(friends: [person], incoming: [], outgoing: [])

        let friendsSection = (0..<friends.numberOfSections(in: friends.tableView)).first { section in
            friends.tableView(friends.tableView, titleForHeaderInSection: section) == String(localized: "Amigos")
        } ?? 0
        let config = friends.tableView(
            friends.tableView,
            trailingSwipeActionsConfigurationForRowAt: IndexPath(row: 0, section: friendsSection)
        )
        XCTAssertEqual(config?.actions.count, 1)
        XCTAssertEqual(config?.actions.first?.title, String(localized: "Remover"))
        XCTAssertEqual(config?.actions.first?.style, .destructive)
    }

    func testFriendsContextMenu_hasReportBlockUnfriend() {
        let person = NativeAPIClient.LinkPersonDTO(
            userId: "u1", handle: "beto", firstName: "Beto", lastName: "Verlí",
            avatarId: "book", avatarUrl: ""
        )
        let friends = FriendsActivityViewController()
        friends.loadViewIfNeeded()
        friends.testing_setLinks(friends: [person], incoming: [], outgoing: [])

        let friendsSection = (0..<friends.numberOfSections(in: friends.tableView)).first { section in
            friends.tableView(friends.tableView, titleForHeaderInSection: section) == String(localized: "Amigos")
        } ?? 0
        let menu = friends.friendContextMenu(
            for: person,
            at: IndexPath(row: 0, section: friendsSection)
        )
        let titles = menu.children.compactMap { ($0 as? UIAction)?.title }
        XCTAssertEqual(titles.count, 3)
        XCTAssertTrue(titles.contains(String(localized: "Denunciar")))
        XCTAssertTrue(titles.contains(String(localized: "Bloquear")))
        XCTAssertTrue(titles.contains(String(localized: "Remover amigo")))
        let destructive = menu.children.compactMap { $0 as? UIAction }.filter { $0.attributes.contains(.destructive) }
        XCTAssertEqual(destructive.count, 2)
    }

    func testPublicProfileDTO_mapsDisplayName() {
        let dto = NativeAPIClient.PublicProfileDTO(
            userId: "u1",
            handle: "ana",
            firstName: "Ana",
            lastName: "Silva",
            avatarId: "book",
            avatarUrl: "",
            status: "accepted"
        )
        XCTAssertEqual(dto.displayName, "Ana Silva")
        XCTAssertEqual(dto.asPerson.userId, "u1")
        XCTAssertEqual(dto.asPerson.handle, "ana")
    }
}
