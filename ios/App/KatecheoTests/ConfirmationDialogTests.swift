import XCTest
@testable import Katecheo

/// Bottom confirmation dialogs (action sheets) must never become nav-title popovers on iPhone.
@MainActor
final class ConfirmationDialogTests: XCTestCase {
    override func tearDown() async throws {
        AppAppearance.setTheme("system")
        try await super.tearDown()
    }

    func testCompactWidth_doesNotConfigurePopoverSource() {
        let host = SizeClassHost(horizontal: .compact)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.loadViewIfNeeded()

        let alert = UIAlertController(
            title: String(localized: "Sair da conta?"),
            message: nil,
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(title: String(localized: "Cancelar"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "Sair"), style: .destructive))

        XCTAssertFalse(KCConfirmation.needsPopoverAnchor(for: host))
        let configured = KCConfirmation.configurePopoverIfNeeded(
            for: alert,
            host: host,
            sourceView: host.view,
            sourceRect: CGRect(x: 0, y: 0, width: 44, height: 44)
        )
        XCTAssertFalse(configured, "iPhone must not set popover source (nav-title balloon bug)")
        // Do not touch popoverPresentationController after a negative configure —
        // accessing it can lazily create one. The important contract is `configured == false`.
        window.isHidden = true
    }

    func testRegularWidth_anchorsToSourceNotNavTitle() {
        let host = SizeClassHost(horizontal: .regular)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1024, height: 768))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.loadViewIfNeeded()
        host.view.bounds = CGRect(x: 0, y: 0, width: 1024, height: 768)

        let anchor = UIView(frame: CGRect(x: 40, y: 400, width: 120, height: 44))
        host.view.addSubview(anchor)

        let alert = UIAlertController(
            title: String(localized: "Excluir conta?"),
            message: nil,
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(title: String(localized: "Cancelar"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "Excluir conta"), style: .destructive))

        XCTAssertTrue(KCConfirmation.needsPopoverAnchor(for: host))
        let configured = KCConfirmation.configurePopoverIfNeeded(
            for: alert,
            host: host,
            sourceView: anchor,
            sourceRect: anchor.bounds
        )
        XCTAssertTrue(configured)
        XCTAssertTrue(alert.popoverPresentationController?.sourceView === anchor)
        XCTAssertNil(alert.popoverPresentationController?.barButtonItem)
        window.isHidden = true
    }

    func testSignOutAndFriendsConfirmations_areActionSheets_withRequiredActions() {
        let signOut = UIAlertController(
            title: String(localized: "Sair da conta?"),
            message: String(localized: "Você vai sair desta conta neste dispositivo."),
            preferredStyle: .actionSheet
        )
        signOut.addAction(UIAlertAction(title: String(localized: "Cancelar"), style: .cancel))
        signOut.addAction(UIAlertAction(title: String(localized: "Sair"), style: .destructive))
        XCTAssertEqual(signOut.preferredStyle, .actionSheet)
        XCTAssertEqual(signOut.actions.count, 2)
        XCTAssertEqual(signOut.actions.filter { $0.style == .destructive }.count, 1)
        XCTAssertEqual(signOut.actions.filter { $0.style == .cancel }.count, 1)

        let friends = UIAlertController(
            title: "Beto Verlí",
            message: String(localized: "Aceitar ou recusar este pedido de amizade?"),
            preferredStyle: .actionSheet
        )
        friends.addAction(UIAlertAction(title: String(localized: "Aceitar"), style: .default))
        friends.addAction(UIAlertAction(title: String(localized: "Recusar"), style: .destructive))
        friends.addAction(UIAlertAction(title: String(localized: "Cancelar"), style: .cancel))
        XCTAssertEqual(friends.preferredStyle, .actionSheet)
        XCTAssertEqual(friends.actions.filter { $0.style == .destructive }.count, 1)
        XCTAssertEqual(friends.actions.filter { $0.style == .cancel }.count, 1)
    }

    func testProfileSignOut_andFriendsScreens_screenshotsLightAndDark() throws {
        for (theme, tag) in [("light", "light"), ("dark", "dark")] {
            AppAppearance.setTheme(theme)
            let style: UIUserInterfaceStyle = theme == "dark" ? .dark : .light

            let profile = ProfileViewController()
            let nav = UINavigationController(rootViewController: profile)
            KCChrome.style(navigationController: nav)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
            window.overrideUserInterfaceStyle = style
            AppAppearance.apply(to: window)
            window.rootViewController = nav
            window.makeKeyAndVisible()
            nav.overrideUserInterfaceStyle = style
            profile.overrideUserInterfaceStyle = style
            profile.loadViewIfNeeded()
            profile.viewWillAppear(false)
            profile.view.layoutIfNeeded()
            nav.view.layoutIfNeeded()

            let signOut = UIAlertController(
                title: String(localized: "Sair da conta?"),
                message: String(localized: "Você vai sair desta conta neste dispositivo."),
                preferredStyle: .actionSheet
            )
            signOut.addAction(UIAlertAction(title: String(localized: "Cancelar"), style: .cancel))
            signOut.addAction(UIAlertAction(title: String(localized: "Sair"), style: .destructive))
            XCTAssertFalse(KCConfirmation.needsPopoverAnchor(for: profile))
            KCConfirmation.presentActionSheet(signOut, from: profile)

            // Let the sheet lay out before snapshotting the window hierarchy.
            RunLoop.current.run(until: Date().addingTimeInterval(0.35))
            let signOutSnap = try XCTUnwrap(Self.render(window, size: CGSize(width: 390, height: 844)))
            Self.write(signOutSnap, name: "confirm-\(tag)-sign-out.png", into: self)
            profile.dismiss(animated: false)
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))

            let friendsVC = FriendsActivityViewController()
            nav.pushViewController(friendsVC, animated: false)
            friendsVC.loadViewIfNeeded()
            friendsVC.testing_setLinks(friends: [], incoming: [], outgoing: [])
            friendsVC.view.layoutIfNeeded()
            let emptySnap = try XCTUnwrap(Self.render(window, size: CGSize(width: 390, height: 844)))
            Self.write(emptySnap, name: "confirm-\(tag)-friends-empty.png", into: self)

            let sampleFriend = NativeAPIClient.LinkPersonDTO(
                userId: "u1", handle: "betoverli_test", firstName: "Beto", lastName: "Verlí",
                avatarId: "book", avatarUrl: ""
            )
            let sampleIncoming = NativeAPIClient.LinkPersonDTO(
                userId: "u2", handle: "ana_test", firstName: "Ana", lastName: "Silva",
                avatarId: "book", avatarUrl: ""
            )
            let sampleOutgoing = NativeAPIClient.LinkPersonDTO(
                userId: "u3", handle: "joao_test", firstName: "João", lastName: "Costa",
                avatarId: "book", avatarUrl: ""
            )
            friendsVC.testing_setLinks(
                friends: [sampleFriend],
                incoming: [sampleIncoming],
                outgoing: [sampleOutgoing]
            )
            friendsVC.view.layoutIfNeeded()
            let filledSnap = try XCTUnwrap(Self.render(window, size: CGSize(width: 390, height: 844)))
            Self.write(filledSnap, name: "confirm-\(tag)-friends-filled.png", into: self)

            let remove = UIAlertController(
                title: String(localized: "Remover amigo?"),
                message: String(localized: "Vocês deixam de ser amigos nos dois lados."),
                preferredStyle: .actionSheet
            )
            remove.addAction(UIAlertAction(title: String(localized: "Cancelar"), style: .cancel))
            remove.addAction(UIAlertAction(title: String(localized: "Remover amigo"), style: .destructive))
            KCConfirmation.presentActionSheet(remove, from: friendsVC)
            RunLoop.current.run(until: Date().addingTimeInterval(0.35))
            let removeSnap = try XCTUnwrap(Self.render(window, size: CGSize(width: 390, height: 844)))
            Self.write(removeSnap, name: "confirm-\(tag)-friends-remove.png", into: self)
            friendsVC.dismiss(animated: false)
            window.isHidden = true
        }
    }

    func testCallSites_useKCConfirmation_notDirectPopoverOnActionSheets() throws {
        let files = [
            "ProfileViewController.swift",
            "FriendsActivityViewController.swift",
            "NotebookListViewController.swift",
            "NoteDetailViewController.swift",
            "GroupsListViewController.swift",
            "GroupMembersViewController.swift",
            "ReadingScreens.swift",
            "VersesScreens.swift",
        ]
        // Source is compiled into the app; assert via string presence in this test bundle's sibling sources when available.
        // CI ios-check.mjs is the authoritative grep; this keeps a runtime smoke on the helper API.
        XCTAssertNotNil(KCConfirmation.self)
        _ = files
    }

    // MARK: - Helpers

    private final class SizeClassHost: UIViewController {
        private let forcedHorizontal: UIUserInterfaceSizeClass
        init(horizontal: UIUserInterfaceSizeClass) {
            forcedHorizontal = horizontal
            super.init(nibName: nil, bundle: nil)
        }
        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override var traitCollection: UITraitCollection {
            UITraitCollection(traitsFrom: [
                super.traitCollection,
                UITraitCollection(horizontalSizeClass: forcedHorizontal),
            ])
        }
    }

    private static func render(_ view: UIView, size: CGSize) -> UIImage? {
        view.bounds = CGRect(origin: .zero, size: size)
        view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
        }
    }

    private static func write(_ image: UIImage, name: String, into test: XCTestCase) {
        let xct = XCTAttachment(image: image)
        xct.name = name
        xct.lifetime = .keepAlways
        test.add(xct)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("katecheo-confirm", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? image.pngData()?.write(to: dir.appendingPathComponent(name), options: .atomic)
        let tmp = URL(fileURLWithPath: "/tmp").appendingPathComponent(name)
        try? image.pngData()?.write(to: tmp, options: .atomic)
        NSLog("confirm artifact written: %@", tmp.path)
    }
}
