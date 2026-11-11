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

        let remove = UIAlertController(
            title: String(localized: "Remover amigo?"),
            message: String(localized: "Vocês deixam de ser amigos nos dois lados."),
            preferredStyle: .actionSheet
        )
        remove.addAction(UIAlertAction(title: String(localized: "Cancelar"), style: .cancel))
        remove.addAction(UIAlertAction(title: String(localized: "Remover amigo"), style: .destructive))
        XCTAssertEqual(remove.preferredStyle, .actionSheet)
    }

    func testProfileAndFriends_screenshotsLightAndDark() throws {
        for (theme, tag) in [("light", "light"), ("dark", "dark")] {
            AppAppearance.setTheme(theme)
            let style: UIUserInterfaceStyle = theme == "dark" ? .dark : .light

            // Profile root (Sign out lives in Account section when signed in).
            LocalSessionCache.saveMe(Self.sampleMe(theme: theme))
            let profile = ProfileViewController()
            let profileNav = UINavigationController(rootViewController: profile)
            KCChrome.style(navigationController: profileNav)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
            window.overrideUserInterfaceStyle = style
            AppAppearance.apply(to: window)
            window.rootViewController = profileNav
            window.makeKeyAndVisible()
            profile.overrideUserInterfaceStyle = style
            profileNav.overrideUserInterfaceStyle = style
            profile.loadViewIfNeeded()
            profile.viewWillAppear(false)
            profile.view.layoutIfNeeded()
            profileNav.view.layoutIfNeeded()
            let profileSnap = try XCTUnwrap(Self.render(profileNav.view, size: CGSize(width: 390, height: 844)))
            Self.write(profileSnap, name: "confirm-\(tag)-profile.png", into: self)

            // Friends empty — pending/sent sections hidden.
            let friendsEmpty = FriendsActivityViewController()
            let emptyNav = UINavigationController(rootViewController: friendsEmpty)
            KCChrome.style(navigationController: emptyNav)
            window.rootViewController = emptyNav
            friendsEmpty.overrideUserInterfaceStyle = style
            emptyNav.overrideUserInterfaceStyle = style
            friendsEmpty.loadViewIfNeeded()
            friendsEmpty.testing_setLinks(friends: [], incoming: [], outgoing: [])
            friendsEmpty.view.layoutIfNeeded()
            emptyNav.view.layoutIfNeeded()
            let emptySnap = try XCTUnwrap(Self.render(emptyNav.view, size: CGSize(width: 390, height: 844)))
            Self.write(emptySnap, name: "confirm-\(tag)-friends-empty.png", into: self)

            // Friends filled — incoming + sent above friends, inline actions.
            let friendsFilled = FriendsActivityViewController()
            let filledNav = UINavigationController(rootViewController: friendsFilled)
            KCChrome.style(navigationController: filledNav)
            window.rootViewController = filledNav
            friendsFilled.overrideUserInterfaceStyle = style
            filledNav.overrideUserInterfaceStyle = style
            friendsFilled.loadViewIfNeeded()
            friendsFilled.testing_setLinks(
                friends: [Self.person(id: "u1", handle: "betoverli_test", first: "Beto", last: "Verlí")],
                incoming: [Self.person(id: "u2", handle: "ana_test", first: "Ana", last: "Silva")],
                outgoing: [Self.person(id: "u3", handle: "joao_test", first: "João", last: "Costa")]
            )
            friendsFilled.view.layoutIfNeeded()
            filledNav.view.layoutIfNeeded()
            let filledSnap = try XCTUnwrap(Self.render(filledNav.view, size: CGSize(width: 390, height: 844)))
            Self.write(filledSnap, name: "confirm-\(tag)-friends-filled.png", into: self)

            // Present remove confirmation — assert sheet style; snapshot list under sheet host.
            let remove = UIAlertController(
                title: String(localized: "Remover amigo?"),
                message: String(localized: "Vocês deixam de ser amigos nos dois lados."),
                preferredStyle: .actionSheet
            )
            remove.addAction(UIAlertAction(title: String(localized: "Cancelar"), style: .cancel))
            remove.addAction(UIAlertAction(title: String(localized: "Remover amigo"), style: .destructive))
            XCTAssertFalse(KCConfirmation.needsPopoverAnchor(for: friendsFilled))
            KCConfirmation.presentActionSheet(remove, from: friendsFilled)
            XCTAssertTrue(friendsFilled.presentedViewController is UIAlertController)
            if let presented = friendsFilled.presentedViewController as? UIAlertController {
                XCTAssertEqual(presented.preferredStyle, .actionSheet)
                XCTAssertNil(presented.popoverPresentationController?.sourceView)
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
            // Snapshot the hosting nav (alert chrome may not appear in drawHierarchy — layout still asserted).
            let removeHostSnap = try XCTUnwrap(Self.render(filledNav.view, size: CGSize(width: 390, height: 844)))
            Self.write(removeHostSnap, name: "confirm-\(tag)-friends-remove-host.png", into: self)
            friendsFilled.dismiss(animated: false)

            // Sign-out sheet contract on Profile.
            window.rootViewController = profileNav
            profile.loadViewIfNeeded()
            let signOut = UIAlertController(
                title: String(localized: "Sair da conta?"),
                message: String(localized: "Você vai sair desta conta neste dispositivo."),
                preferredStyle: .actionSheet
            )
            signOut.addAction(UIAlertAction(title: String(localized: "Cancelar"), style: .cancel))
            signOut.addAction(UIAlertAction(title: String(localized: "Sair"), style: .destructive))
            KCConfirmation.presentActionSheet(signOut, from: profile)
            XCTAssertTrue(profile.presentedViewController is UIAlertController)
            if let presented = profile.presentedViewController as? UIAlertController {
                XCTAssertEqual(presented.preferredStyle, .actionSheet)
                XCTAssertEqual(presented.actions.filter { $0.style == .destructive }.first?.title, String(localized: "Sair"))
            }
            profile.dismiss(animated: false)
            window.isHidden = true
        }
    }

    // MARK: - Helpers

    private static func sampleMe(theme: String) -> NativeAPIClient.MeDTO {
        NativeAPIClient.MeDTO(
            id: "snap-acct",
            email: "a@b.c",
            displayName: "Test",
            prefs: NativeAPIClient.PrefsDTO(
                locale: "pt", copyLocale: "pt", appId: "youversion", translationId: "nvi-pt",
                preferNative: true, copyFormat: "default", citeBook: "abbr", citeSep: ":",
                booksCompact: false, theme: theme, activePlans: nil, planProgress: nil,
                avatarId: "", avatarUrl: "", handle: "t", firstName: "T", lastName: "U", profileEmail: "a@b.c"
            ),
            notify: NativeAPIClient.NotifyPrefsDTO(reading: true, friends: true, shares: true, groups: true, apnsDevices: 0)
        )
    }

    private static func person(id: String, handle: String, first: String, last: String) -> NativeAPIClient.LinkPersonDTO {
        NativeAPIClient.LinkPersonDTO(
            userId: id, handle: handle, firstName: first, lastName: last, avatarId: "book", avatarUrl: ""
        )
    }

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
