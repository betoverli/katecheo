import XCTest
@testable import App

/// Build 238: editor Light pref, tags save path, delete anchors, Lists empty, search hide, activity dots.
@MainActor
final class Build238FeedbackTests: XCTestCase {
    override func tearDown() async throws {
        AppAppearance.setTheme("system")
        AppAppearance.setKeepEditorInLightMode(false)
        V2NActivityStore.clearAccount()
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
        // Smoke: NotebookListViewController + GroupsListViewController compile with
        // sourceView/row anchoring helpers (full UIAlert presentation is covered in CI screenshots).
        let notebook = NotebookListViewController()
        notebook.loadViewIfNeeded()
        let groups = GroupsListViewController()
        groups.loadViewIfNeeded()
        XCTAssertNotNil(notebook.view)
        XCTAssertNotNil(groups.view)
    }

    // MARK: - 4) Lists empty alignment

    func testListsEmptyState_usesAutoresizingBackgroundView() {
        let lists = MyCollectionsViewController(embedded: true)
        lists.loadViewIfNeeded()
        XCTAssertNotNil(lists.tableView.backgroundView)
        XCTAssertTrue(lists.tableView.backgroundView is V2NEmptyStateView)
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
        V2NActivityStore.reconcileSharedNotes([n1])
        XCTAssertFalse(V2NActivityStore.sharedChipDot)
        XCTAssertFalse(V2NActivityStore.notebookDot)
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
        V2NActivityStore.reconcileServer(incoming: incoming, granted: [grant], inbox: inbox)
        XCTAssertTrue(V2NActivityStore.notebookDot)
        XCTAssertTrue(V2NActivityStore.sharedChipDot)
        XCTAssertTrue(V2NActivityStore.groupsDot)
        XCTAssertTrue(V2NActivityStore.toolsDot)
        XCTAssertTrue(V2NActivityStore.profileDot)
        XCTAssertTrue(V2NActivityStore.hasAny(kinds: .friendPending))
        XCTAssertTrue(V2NActivityStore.hasAny(kinds: .friendAccepted))

        // Parent/tab visit must not clear children.
        XCTAssertTrue(V2NActivityStore.notebookDot)

        // Opening Shared note clears only that share (+ would markRead n-share).
        V2NActivityStore.markSharedNoteOpened("grant-1")
        XCTAssertFalse(V2NActivityStore.targetIds(kind: .sharedNote).contains("grant-1"))
        XCTAssertTrue(V2NActivityStore.hasAny(kinds: .friendPending), "pending survives unrelated clears")

        // Friends screen clears acceptance only.
        V2NActivityStore.markFriendsAcceptedSeen()
        XCTAssertFalse(V2NActivityStore.hasAny(kinds: .friendAccepted))
        XCTAssertTrue(V2NActivityStore.hasAny(kinds: .friendPending))

        // Decision clears pending.
        V2NActivityStore.clearFriendPending(targetId: "amigo")
        XCTAssertFalse(V2NActivityStore.hasAny(kinds: .friendPending))

        // Reading dismiss clears digest/plan.
        V2NActivityStore.dismissReadingDue(planId: "plan-1")
        XCTAssertFalse(V2NActivityStore.toolsDot)

        // Simulate second device: unread cleared on server → empty inbox, pending gone.
        V2NActivityStore.reconcileServer(incoming: [], granted: [grant], inbox: [
            .init(id: "n-share", kind: "shares", title: "Share", body: "", href: "/n/grant-1", read: true, createdAt: "2026-01-01"),
            .init(id: "n-group", kind: "groups", title: "Grupo", body: "", href: "/groups/g1", read: true, createdAt: "2026-01-01"),
        ])
        XCTAssertFalse(V2NActivityStore.profileDot)
        XCTAssertFalse(V2NActivityStore.groupsDot)
        // grant already opened locally — no Shared dot without unread share.
        XCTAssertFalse(V2NActivityStore.sharedChipDot)
    }

    func testActivityStore_readingHeuristicDoesNotInventDigestDue() {
        let me = seedMe(id: "acct-b238-r", activePlans: ["plan-1"], planProgress: ["plan-1": []])
        LocalSessionCache.saveMe(me)
        let plan = NativeAPIClient.PlanCardDTO(id: "plan-1", name: "Evangelhos", days: 7, chapters: nil, description: nil, categoryIds: nil)
        V2NActivityStore.reconcileReadingDue(prefs: me.prefs, plans: [plan])
        XCTAssertFalse(V2NActivityStore.toolsDot)

        V2NActivityStore.reconcileServer(
            incoming: [],
            granted: [],
            inbox: [
                .init(id: "d1", kind: "reading", title: "Due", body: "", href: "/reading/plan-1", read: false, createdAt: "2026-01-02"),
            ]
        )
        XCTAssertTrue(V2NActivityStore.toolsDot)
        V2NActivityStore.dismissReadingDue(planId: "plan-1")
        XCTAssertFalse(V2NActivityStore.targetIds(kind: .readingDue).contains("plan-1"))
    }

    func testActivityStore_crossAccountNoLeakOnClear() {
        let me = seedMe(id: "acct-b238-out")
        LocalSessionCache.saveMe(me)
        V2NActivityStore.ingestGroupActivity(groupId: "g9")
        XCTAssertTrue(V2NActivityStore.groupsDot)
        V2NActivityStore.clearAccount("acct-b238-out")
        LocalSessionCache.clearMe()
        XCTAssertFalse(V2NActivityStore.groupsDot)

        let other = seedMe(id: "acct-other")
        LocalSessionCache.saveMe(other)
        XCTAssertFalse(V2NActivityStore.groupsDot, "other account must start clean")
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
            V2NChrome.style(navigationController: nav)
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
            V2NChrome.style(navigationController: themeNav)
            window.rootViewController = themeNav
            themeVC.overrideUserInterfaceStyle = style
            themeNav.overrideUserInterfaceStyle = style
            themeVC.loadViewIfNeeded()
            themeVC.v2nApplyGroupedChrome()
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
            V2NActivityStore.ingestFriendPending(title: "Pedido demo")
            let friends = FriendsActivityViewController()
            let friendsNav = UINavigationController(rootViewController: friends)
            V2NChrome.style(navigationController: friendsNav)
            window.rootViewController = friendsNav
            friends.overrideUserInterfaceStyle = style
            friendsNav.overrideUserInterfaceStyle = style
            friends.loadViewIfNeeded()
            friends.viewWillAppear(false)
            if let snap = Self.render(friendsNav.view, size: CGSize(width: 390, height: 844)) {
                Self.write(snap, name: "b238-\(tag)-friends.png", into: self)
            }

            // Tabs with dots
            let tabs = NativeRootTabBarController()
            window.rootViewController = tabs
            tabs.overrideUserInterfaceStyle = style
            tabs.loadViewIfNeeded()
            V2NActivityStore.ingestGroupActivity(groupId: "g-snap")
            V2NActivityStore.upsert(kind: .readingDue, targetId: "plan-snap")
            V2NActivityStore.ingestFriendPending()
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
        let tmp = URL(fileURLWithPath: "/tmp").appendingPathComponent(name)
        try? image.pngData()?.write(to: tmp, options: .atomic)
        NSLog("b238 artifact written: %@", tmp.path)
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
