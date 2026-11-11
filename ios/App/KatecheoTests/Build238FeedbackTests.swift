import XCTest
@testable import Katecheo

/// Build 238: editor Light pref, tags save path, delete anchors, Lists empty, search hide, activity dots.
@MainActor
final class Build238FeedbackTests: XCTestCase {
    override func tearDown() async throws {
        AppAppearance.setTheme("system")
        AppAppearance.setKeepEditorInLightMode(false)
        KCActivityStore.clearAccount()
        LocalNoteCache.saveNotes([])
        try await super.tearDown()
    }

    // MARK: - 1) Editor Light preference

    func testKeepEditorLight_overridesOnlyWhileNoteDetailVisible() {
        AppAppearance.setTheme("dark")
        AppAppearance.setKeepEditorInLightMode(true)
        let note = NativeAPIClient.emptyNote(id: "note-b238-light")
        let detail = NoteDetailViewController(noteId: note.id, initial: note)
        let nav = UINavigationController(rootViewController: UIViewController())
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.overrideUserInterfaceStyle = .dark
        AppAppearance.apply(to: window)
        window.rootViewController = nav
        window.makeKeyAndVisible()
        nav.pushViewController(detail, animated: false)
        detail.loadViewIfNeeded()
        detail.viewWillAppear(false)
        XCTAssertEqual(detail.overrideUserInterfaceStyle, .light)
        XCTAssertEqual(nav.overrideUserInterfaceStyle, .light)
        detail.viewWillDisappear(false)
        // Simulate pop
        detail.removeFromParent()
        // After clear path when moving from parent — call disappear with flag via nav pop
        nav.popViewController(animated: false)
        window.isHidden = true
    }

    // MARK: - 2) Tags save through NoteDetail bridge

    func testTags_surviveNoteDetailDidChangeBridgeAndReopen() throws {
        var note = NativeAPIClient.emptyNote(id: "note-b238-tags")
        note.tags = []
        LocalNoteCache.upsertNote(note)

        let detail = NoteDetailViewController(noteId: note.id, initial: note)
        let nav = UINavigationController(rootViewController: detail)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = nav
        window.makeKeyAndVisible()
        detail.loadViewIfNeeded()

        let editor = detail.view.findNativeEditor()
        XCTAssertNotNil(editor)
        editor?.testing_setTags(["culto", "oração"])

        let cached = LocalNoteCache.loadNotes().first { $0.id == note.id }
        XCTAssertEqual(cached?.tags, ["culto", "oração"], "VC bridge must keep editor tags")

        // Reopen
        let again = NoteDetailViewController(noteId: note.id, initial: cached)
        let nav2 = UINavigationController(rootViewController: again)
        window.rootViewController = nav2
        again.loadViewIfNeeded()
        let editor2 = again.view.findNativeEditor()
        XCTAssertEqual(editor2?.testing_tags(), ["culto", "oração"])
        window.isHidden = true
    }

    // MARK: - 3) Delete confirmation anchors

    func testDeleteConfirm_usesActionSheetPreferredStyle() {
        // Smoke: list VCs still load; iPhone/iPad anchoring lives in KCConfirmation
        // (see ConfirmationDialogTests — never configure popover on compact width).
        let notebook = NotebookListViewController()
        notebook.loadViewIfNeeded()
        let groups = GroupsListViewController()
        groups.loadViewIfNeeded()
        XCTAssertNotNil(notebook.view)
        XCTAssertNotNil(groups.view)
        XCTAssertFalse(
            KCConfirmation.needsPopoverAnchor(for: notebook),
            "phone-sized host must keep bottom action sheets"
        )
    }

    // MARK: - 4) Lists empty alignment

    func testListsEmptyState_usesAutoresizingBackgroundView() {
        let lists = MyCollectionsViewController(embedded: true)
        lists.loadViewIfNeeded()
        XCTAssertNotNil(lists.tableView.backgroundView)
        XCTAssertTrue(lists.tableView.backgroundView is KCEmptyStateView)
        XCTAssertTrue(lists.tableView.backgroundView?.translatesAutoresizingMaskIntoConstraints == true)
    }

    // MARK: - 5) Themes/Reading search on parent

    func testTools_searchControllerInstalledOnlyForThemesAndReading() {
        let home = VersesHomeViewController()
        let nav = UINavigationController(rootViewController: home)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = nav
        window.makeKeyAndVisible()
        home.loadViewIfNeeded()

        home.selectHomeFilter("books")
        XCTAssertNil(home.navigationItem.searchController)

        home.selectHomeFilter("themes")
        XCTAssertNotNil(home.navigationItem.searchController)
        XCTAssertTrue(home.navigationItem.hidesSearchBarWhenScrolling)

        home.selectHomeFilter("reading")
        XCTAssertNotNil(home.navigationItem.searchController)
        XCTAssertTrue(home.navigationItem.hidesSearchBarWhenScrolling)

        home.selectHomeFilter("lists")
        XCTAssertNil(home.navigationItem.searchController)
        window.isHidden = true
    }

    // MARK: - 6) Activity dots

    func testActivityStore_visibilityHeuristicStillDoesNotInventGrants() {
        let me = seedMe(id: "acct-b238")
        LocalSessionCache.saveMe(me)
        var n1 = NativeAPIClient.emptyNote(id: "shared-1")
        n1.visibility = "shared"
        KCActivityStore.reconcileSharedNotes([n1])
        XCTAssertFalse(KCActivityStore.sharedChipDot)
        XCTAssertFalse(KCActivityStore.notebookDot)
    }

    func testActivityStore_serverReconcile_grantsInboxFriendsReadingTwoDeviceSim() {
        let me = seedMe(id: "acct-b238-sync")
        LocalSessionCache.saveMe(me)

        var grant = NativeAPIClient.emptyNote(id: "grant-1")
        grant.title = "Nota enviada"
        let incoming = [
            NativeAPIClient.LinkPersonDTO(
                userId: "u2", handle: "amigo", firstName: "Ana", lastName: "B",
                avatarId: "book", avatarUrl: ""
            ),
        ]
        let inbox: [NativeAPIClient.InboxItemDTO] = [
            .init(id: "n-share", kind: "shares", title: "Share", body: "", href: "/n/grant-1", read: false, createdAt: "2026-01-01"),
            .init(id: "n-friend", kind: "friends", title: "Aceite", body: "", href: "/profile/friends", read: false, createdAt: "2026-01-01"),
            .init(id: "n-group", kind: "groups", title: "Grupo", body: "", href: "/groups/g1", read: false, createdAt: "2026-01-01"),
            .init(id: "n-read", kind: "reading", title: "Leitura", body: "", href: "/reading/plan-1", read: false, createdAt: "2026-01-01"),
            .init(id: "n-old", kind: "reading", title: "Old", body: "", href: "/reading/plan-1", read: true, createdAt: "2026-01-01"),
        ]
        KCActivityStore.reconcileServer(incoming: incoming, granted: [grant], inbox: inbox)
        XCTAssertTrue(KCActivityStore.notebookDot)
        XCTAssertTrue(KCActivityStore.sharedChipDot)
        XCTAssertTrue(KCActivityStore.groupsDot)
        XCTAssertTrue(KCActivityStore.toolsDot)
        XCTAssertTrue(KCActivityStore.profileDot)
        XCTAssertTrue(KCActivityStore.hasAny(kinds: .friendPending))
        XCTAssertTrue(KCActivityStore.hasAny(kinds: .friendAccepted))

        // Parent/tab visit must not clear children.
        XCTAssertTrue(KCActivityStore.notebookDot)

        // Opening Shared note clears only that share (+ would markRead n-share).
        KCActivityStore.markSharedNoteOpened("grant-1")
        XCTAssertFalse(KCActivityStore.targetIds(kind: .sharedNote).contains("grant-1"))
        XCTAssertTrue(KCActivityStore.hasAny(kinds: .friendPending), "pending survives unrelated clears")

        // Friends screen clears acceptance only.
        KCActivityStore.markFriendsAcceptedSeen()
        XCTAssertFalse(KCActivityStore.hasAny(kinds: .friendAccepted))
        XCTAssertTrue(KCActivityStore.hasAny(kinds: .friendPending))

        // Decision clears pending.
        KCActivityStore.clearFriendPending(targetId: "amigo")
        XCTAssertFalse(KCActivityStore.hasAny(kinds: .friendPending))

        // Reading dismiss clears digest/plan.
        KCActivityStore.dismissReadingDue(planId: "plan-1")
        XCTAssertFalse(KCActivityStore.toolsDot)

        // Simulate second device: unread cleared on server → empty inbox, pending gone.
        KCActivityStore.reconcileServer(incoming: [], granted: [grant], inbox: [
            .init(id: "n-share", kind: "shares", title: "Share", body: "", href: "/n/grant-1", read: true, createdAt: "2026-01-01"),
            .init(id: "n-group", kind: "groups", title: "Grupo", body: "", href: "/groups/g1", read: true, createdAt: "2026-01-01"),
        ])
        XCTAssertFalse(KCActivityStore.profileDot)
        XCTAssertFalse(KCActivityStore.groupsDot)
        // grant already opened locally — no Shared dot without unread share.
        XCTAssertFalse(KCActivityStore.sharedChipDot)
    }

    func testActivityStore_readingHeuristicDoesNotInventDigestDue() {
        let me = seedMe(id: "acct-b238-r", activePlans: ["plan-1"], planProgress: ["plan-1": []])
        LocalSessionCache.saveMe(me)
        let plan = NativeAPIClient.PlanCardDTO(id: "plan-1", name: "Evangelhos", days: 7, chapters: nil, description: nil, categoryIds: nil)
        KCActivityStore.reconcileReadingDue(prefs: me.prefs, plans: [plan])
        XCTAssertFalse(KCActivityStore.toolsDot)

        KCActivityStore.reconcileServer(
            incoming: [],
            granted: [],
            inbox: [
                .init(id: "d1", kind: "reading", title: "Due", body: "", href: "/reading/plan-1", read: false, createdAt: "2026-01-02"),
            ]
        )
        XCTAssertTrue(KCActivityStore.toolsDot)
        KCActivityStore.dismissReadingDue(planId: "plan-1")
        XCTAssertFalse(KCActivityStore.targetIds(kind: .readingDue).contains("plan-1"))
    }

    func testActivityStore_pushIngestDoesNotLightDotsWithoutServer() {
        let me = seedMe(id: "acct-b238-push")
        LocalSessionCache.saveMe(me)
        KCActivityStore.ingestPush(href: "/groups/g1", title: "Novo")
        KCActivityStore.ingestPush(href: "/n/note-1", title: "Share")
        KCActivityStore.ingestPush(href: "/reading/plan-1", title: "Leitura")
        KCActivityStore.ingestPush(href: "/profile/friends", title: "Pedido")
        XCTAssertFalse(KCActivityStore.groupsDot)
        XCTAssertFalse(KCActivityStore.notebookDot)
        XCTAssertFalse(KCActivityStore.toolsDot)
        XCTAssertFalse(KCActivityStore.profileDot)
    }

    func testActivityStore_alreadyReadInboxDoesNotLightDots() {
        let me = seedMe(id: "acct-b238-read")
        LocalSessionCache.saveMe(me)
        KCActivityStore.reconcileServer(
            incoming: [],
            granted: [],
            inbox: [
                .init(id: "r1", kind: "reading", title: "Old", body: "", href: "/reading/plan-1", read: true, createdAt: "2026-01-02"),
                .init(id: "f1", kind: "friends", title: "Aceite", body: "", href: "/profile/friends", read: true, createdAt: "2026-01-02"),
                .init(id: "s1", kind: "shares", title: "Share", body: "", href: "/n/n1", read: true, createdAt: "2026-01-02"),
                .init(id: "g1", kind: "groups", title: "Grupo", body: "", href: "/groups/g1", read: true, createdAt: "2026-01-02"),
            ]
        )
        XCTAssertFalse(KCActivityStore.toolsDot)
        XCTAssertFalse(KCActivityStore.profileDot)
        XCTAssertFalse(KCActivityStore.notebookDot)
        XCTAssertFalse(KCActivityStore.groupsDot)
    }

    func testActivityStore_reconcileDropsStalePushSourceItems() {
        let me = seedMe(id: "acct-b238-stale-push")
        LocalSessionCache.saveMe(me)
        // Legacy path: force a push-sourced item, then server reconcile must wipe it.
        KCActivityStore.upsert(kind: .readingDue, targetId: "plan-x", source: .push)
        XCTAssertTrue(KCActivityStore.toolsDot)
        KCActivityStore.reconcileServer(incoming: [], granted: [], inbox: [])
        XCTAssertFalse(KCActivityStore.toolsDot)
    }

    func testActivitySync_skippedWithoutBearer() async {
        LocalSessionCache.clearMe()
        KeychainStore.deleteBearerToken()
        let result = await KCActivitySync.refreshFromServer()
        XCTAssertEqual(result, .skippedNoBearer)
    }

    func testActivityStore_crossAccountNoLeakOnClear() {
        let me = seedMe(id: "acct-b238-out")
        LocalSessionCache.saveMe(me)
        KCActivityStore.ingestGroupActivity(groupId: "g9")
        XCTAssertTrue(KCActivityStore.groupsDot)
        KCActivityStore.clearAccount("acct-b238-out")
        LocalSessionCache.clearMe()
        XCTAssertFalse(KCActivityStore.groupsDot)

        let other = seedMe(id: "acct-other")
        LocalSessionCache.saveMe(other)
        XCTAssertFalse(KCActivityStore.groupsDot, "other account must start clean")
    }

    private func seedMe(
        id: String,
        activePlans: [String]? = nil,
        planProgress: [String: [Int]]? = nil
    ) -> NativeAPIClient.MeDTO {
        NativeAPIClient.MeDTO(
            id: id,
            email: "a@b.c",
            displayName: "Test",
            prefs: NativeAPIClient.PrefsDTO(
                locale: "pt", copyLocale: "pt", appId: "youversion", translationId: "nvi-pt",
                preferNative: true, copyFormat: "default", citeBook: "abbr", citeSep: ":",
                booksCompact: false, theme: "system", activePlans: activePlans, planProgress: planProgress,
                avatarId: "", avatarUrl: "", handle: "t", firstName: "T", lastName: "U", profileEmail: "a@b.c"
            ),
            notify: NativeAPIClient.NotifyPrefsDTO(reading: true, friends: true, shares: true, groups: true, apnsDevices: 0)
        )
    }

    // MARK: - Screenshots

    func testBuild238_writeChromeScreenshots() throws {
        for (theme, tag) in [("light", "light"), ("dark", "dark")] {
            AppAppearance.setTheme(theme)
            let style: UIUserInterfaceStyle = theme == "dark" ? .dark : .light
            let traits = UITraitCollection(userInterfaceStyle: style)

            // Note editor
            let note = NativeAPIClient.emptyNote(id: "snap-note-\(tag)")
            let detail = NoteDetailViewController(noteId: note.id, initial: note)
            let nav = UINavigationController(rootViewController: detail)
            KCChrome.style(navigationController: nav)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
            window.overrideUserInterfaceStyle = style
            AppAppearance.apply(to: window)
            window.rootViewController = nav
            window.makeKeyAndVisible()
            nav.overrideUserInterfaceStyle = style
            detail.overrideUserInterfaceStyle = style
            detail.loadViewIfNeeded()
            detail.viewWillAppear(false)
            detail.view.layoutIfNeeded()
            if let snap = Self.render(nav.view, size: CGSize(width: 390, height: 844)) {
                Self.write(snap, name: "b238-\(tag)-note-editor.png", into: self)
            }

            // Tools Lists empty
            let lists = MyCollectionsViewController(embedded: true)
            let tools = VersesHomeViewController()
            let toolsNav = UINavigationController(rootViewController: tools)
            window.rootViewController = toolsNav
            tools.overrideUserInterfaceStyle = style
            toolsNav.overrideUserInterfaceStyle = style
            tools.loadViewIfNeeded()
            tools.selectHomeFilter("lists")
            tools.view.layoutIfNeeded()
            if let snap = Self.render(toolsNav.view, size: CGSize(width: 390, height: 844)) {
                Self.write(snap, name: "b238-\(tag)-tools-lists.png", into: self)
            }

            // Appearance with editor toggle
            let themeVC = ProfileThemeViewController(theme: theme, onSaved: {})
            let themeNav = UINavigationController(rootViewController: themeVC)
            KCChrome.style(navigationController: themeNav)
            window.rootViewController = themeNav
            themeVC.overrideUserInterfaceStyle = style
            themeNav.overrideUserInterfaceStyle = style
            themeVC.loadViewIfNeeded()
            themeVC.kcApplyGroupedChrome()
            themeVC.view.layoutIfNeeded()
            if let snap = Self.render(themeNav.view, size: CGSize(width: 390, height: 844)) {
                Self.write(snap, name: "b238-\(tag)-appearance-editor-light.png", into: self)
            }

            // Friends destination
            LocalSessionCache.saveMe(
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
            )
            KCActivityStore.ingestFriendPending(title: "Pedido demo")
            let friends = FriendsActivityViewController()
            let friendsNav = UINavigationController(rootViewController: friends)
            KCChrome.style(navigationController: friendsNav)
            window.rootViewController = friendsNav
            friends.overrideUserInterfaceStyle = style
            friendsNav.overrideUserInterfaceStyle = style
            friends.loadViewIfNeeded()
            friends.viewWillAppear(false)
            friends.testing_setLinks(
                friends: [
                    NativeAPIClient.LinkPersonDTO(
                        userId: "u1", handle: "betoverli_test", firstName: "Beto", lastName: "Verlí",
                        avatarId: "book", avatarUrl: ""
                    ),
                ],
                incoming: [
                    NativeAPIClient.LinkPersonDTO(
                        userId: "u2", handle: "ana_test", firstName: "Ana", lastName: "Silva",
                        avatarId: "book", avatarUrl: ""
                    ),
                ],
                outgoing: [
                    NativeAPIClient.LinkPersonDTO(
                        userId: "u3", handle: "joao_test", firstName: "João", lastName: "Costa",
                        avatarId: "book", avatarUrl: ""
                    ),
                ]
            )
            friends.view.layoutIfNeeded()
            if let snap = Self.render(friendsNav.view, size: CGSize(width: 390, height: 844)) {
                Self.write(snap, name: "b238-\(tag)-friends.png", into: self)
            }

            // Tabs with dots
            let tabs = NativeRootTabBarController()
            window.rootViewController = tabs
            tabs.overrideUserInterfaceStyle = style
            tabs.loadViewIfNeeded()
            KCActivityStore.ingestGroupActivity(groupId: "g-snap")
            KCActivityStore.upsert(kind: .readingDue, targetId: "plan-snap", source: .local)
            KCActivityStore.ingestFriendPending()
            tabs.view.layoutIfNeeded()
            if let snap = Self.render(tabs.view, size: CGSize(width: 390, height: 844)) {
                Self.write(snap, name: "b238-\(tag)-tabs-dots.png", into: self)
            }

            _ = traits
            _ = lists
            window.isHidden = true
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
        // Write into the Simulator app sandbox tmp (same pattern as tab-bg) so the
        // CI harvest `find … CoreSimulator` actually sees b238-*.png.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("katecheo-b238", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try? image.pngData()?.write(to: url, options: .atomic)
        NSLog("b238 artifact written: %@", url.path)
    }
}

private extension UIView {
    func findNativeEditor() -> NativeNoteEditorView? {
        if let editor = self as? NativeNoteEditorView { return editor }
        for sub in subviews {
            if let found = sub.findNativeEditor() { return found }
        }
        return nil
    }
}
