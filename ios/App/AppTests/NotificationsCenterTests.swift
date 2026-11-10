import XCTest
@testable import App

/// Notification Center: view-model paging / mark-read / badge, plus Caderno UI path.
@MainActor
final class NotificationsCenterTests: XCTestCase {
    override func setUp() {
        super.setUp()
        NativeSWR.resetAllForTests()
        MockNativeURLProtocol.reset()
        MockNativeURLProtocol.register()
        NativeAPIClient.session = MockNativeURLProtocol.makeSession()
        NativeAPIClient.testAuthToken = "test-bearer-notify"
        V2NNotificationsBadge.setUnreadCount(0)
        V2NActivityStore.clearAccount()
        LocalSessionCache.saveMe(seedMe(id: "acct-notify"))
    }

    override func tearDown() {
        V2NActivityStore.clearAccount()
        V2NNotificationsBadge.setUnreadCount(0)
        NativeAPIClient.testAuthToken = nil
        NativeAPIClient.session = .shared
        MockNativeURLProtocol.unregister()
        NativeSWR.resetAllForTests()
        super.tearDown()
    }

    private func seedMe(id: String) -> NativeAPIClient.MeDTO {
        NativeAPIClient.MeDTO(
            id: id,
            email: "a@b.c",
            displayName: "Ana",
            prefs: NativeAPIClient.PrefsDTO(
                locale: "pt", copyLocale: "pt", appId: "youversion", translationId: "nvi-pt",
                preferNative: true, copyFormat: "default", citeBook: "abbr", citeSep: ":",
                booksCompact: false, theme: "system", activePlans: nil, planProgress: nil,
                avatarId: "", avatarUrl: "", handle: "ana", firstName: "Ana", lastName: "", profileEmail: "a@b.c"
            ),
            notify: NativeAPIClient.NotifyPrefsDTO(reading: true, friends: true, shares: true, groups: true, apnsDevices: 0)
        )
    }

    // MARK: - Badge helpers

    func testBadgeText_hiddenAtZero_capsAt99Plus() {
        XCTAssertNil(V2NNotificationsBadge.badgeText(for: 0))
        XCTAssertEqual(V2NNotificationsBadge.badgeText(for: 1), "1")
        XCTAssertEqual(V2NNotificationsBadge.badgeText(for: 99), "99")
        XCTAssertEqual(V2NNotificationsBadge.badgeText(for: 100), "99+")
        XCTAssertEqual(V2NNotificationsBadge.badgeText(for: 250), "99+")
    }

    func testDayGrouping_todayYesterdayAndAbsolute() {
        let cal = Calendar(identifier: .gregorian)
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 15))!
        let today = cal.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 9))!
        let yesterday = cal.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 12))!
        let older = cal.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 8))!

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let items: [NativeAPIClient.InboxItemDTO] = [
            .init(id: "1", kind: "shares", title: "A", body: "", href: "/n/1", read: false, createdAt: iso.string(from: today)),
            .init(id: "2", kind: "friends", title: "B", body: "", href: "/profile/friends", read: false, createdAt: iso.string(from: yesterday)),
            .init(id: "3", kind: "reading", title: "C", body: "", href: "/reading/p1", read: true, createdAt: iso.string(from: older)),
        ]
        let sections = NotificationsCenterViewModel.groupByDay(items, now: now, calendar: cal)
        XCTAssertEqual(sections.count, 3)
        XCTAssertEqual(sections[0].title, String(localized: "Hoje"))
        XCTAssertEqual(sections[0].items.map(\.id), ["1"])
        XCTAssertEqual(sections[1].title, String(localized: "Ontem"))
        XCTAssertEqual(sections[1].items.map(\.id), ["2"])
        XCTAssertEqual(sections[2].items.map(\.id), ["3"])
    }

    func testSymbolName_perKind() {
        XCTAssertEqual(NotificationsCenterViewModel.symbolName(forKind: "shares"), "square.and.arrow.up")
        XCTAssertEqual(NotificationsCenterViewModel.symbolName(forKind: "groups"), "person.3")
        XCTAssertEqual(NotificationsCenterViewModel.symbolName(forKind: "friends"), "person.badge.plus")
        XCTAssertEqual(NotificationsCenterViewModel.symbolName(forKind: "reading"), "book")
        XCTAssertEqual(NotificationsCenterViewModel.symbolName(forKind: "other"), "bell")
    }

    // MARK: - View model paging / mark read / badge

    func testViewModel_pagingMarkReadAndBadge() async throws {
        MockNativeURLProtocol.notificationsJSON = Self.page1Payload
        MockNativeURLProtocol.notificationsPage2JSON = Self.page2Payload
        MockNativeURLProtocol.notificationsReadJSON = ##"{"ok":true}"##

        let vm = NotificationsCenterViewModel()
        await vm.loadInitial()
        XCTAssertEqual(vm.items.count, 2)
        XCTAssertEqual(vm.unreadCount, 3)
        XCTAssertEqual(V2NNotificationsBadge.unreadCount, 3)
        XCTAssertEqual(V2NNotificationsBadge.displayText, "3")
        XCTAssertEqual(vm.nextCursor, "cursor-2")
        XCTAssertEqual(MockNativeURLProtocol.notificationsListHits, 1)

        // Seed activity store with notificationIds so mark-read clears dots.
        V2NActivityStore.reconcileServer(
            incoming: [],
            granted: [],
            inbox: [
                .init(id: "n1", kind: "shares", title: "Share", body: "", href: "/n/note-1", read: false, createdAt: "2026-11-10T12:00:00Z"),
                .init(id: "n2", kind: "groups", title: "Grupo", body: "", href: "/groups/g1", read: false, createdAt: "2026-11-10T11:00:00Z"),
            ]
        )
        XCTAssertTrue(V2NActivityStore.notebookDot)
        XCTAssertTrue(V2NActivityStore.groupsDot)

        await vm.loadMoreIfNeeded(currentIndex: 1)
        XCTAssertEqual(vm.items.count, 3)
        XCTAssertNil(vm.nextCursor)
        XCTAssertEqual(MockNativeURLProtocol.notificationsListHits, 2)
        XCTAssertEqual(vm.unreadCount, 2)

        let ok = await vm.markRead(id: "n1")
        XCTAssertTrue(ok)
        XCTAssertTrue(vm.items.first(where: { $0.id == "n1" })?.read == true)
        XCTAssertEqual(vm.unreadCount, 1)
        XCTAssertEqual(V2NNotificationsBadge.unreadCount, 1)
        XCTAssertEqual(MockNativeURLProtocol.readBodies.count, 1)
        XCTAssertEqual(MockNativeURLProtocol.readBodies.first?["id"] as? String, "n1")
        XCTAssertFalse(V2NActivityStore.notebookDot, "reading share in center clears matching store item")
        XCTAssertTrue(V2NActivityStore.groupsDot, "unrelated group dot survives")

        let all = await vm.markAllRead()
        XCTAssertTrue(all)
        XCTAssertEqual(vm.unreadCount, 0)
        XCTAssertNil(V2NNotificationsBadge.displayText)
        XCTAssertFalse(V2NActivityStore.groupsDot)
        XCTAssertTrue(vm.items.allSatisfy(\.read))
        // Final POST may be mark-all (null id).
        XCTAssertGreaterThanOrEqual(MockNativeURLProtocol.readBodies.count, 2)
    }

    func testViewModel_errorState_thenRetry() async {
        MockNativeURLProtocol.notificationsJSON = nil
        let vm = NotificationsCenterViewModel()
        await vm.loadInitial()
        XCTAssertTrue(vm.showsError)
        XCTAssertNotNil(vm.errorMessage)

        MockNativeURLProtocol.notificationsJSON = Self.emptyPayload
        await vm.loadInitial()
        XCTAssertTrue(vm.showsEmpty)
        XCTAssertNil(vm.errorMessage)
        XCTAssertEqual(V2NNotificationsBadge.unreadCount, 0)
    }

    // MARK: - Real UI path

    func testCaderno_installsBellOnlyOnPersonalNotebook() {
        let personal = NotebookListViewController()
        personal.loadViewIfNeeded()
        let personalBell = personal.navigationItem.rightBarButtonItems?
            .compactMap { $0.customView as? V2NNotificationsBellButton }
        XCTAssertEqual(personalBell?.count, 1, "Caderno tab must show the notifications bell")

        let group = NativeAPIClient.GroupDTO(
            id: "g1",
            name: "Grupo",
            description: "",
            visibility: "private",
            postPolicy: "members",
            createdBy: "u1",
            memberCount: 2,
            myRole: "member",
            myStatus: "accepted",
            updatedAt: "2026-11-10T00:00:00Z",
            published: true
        )
        let groupList = NotebookListViewController(group: group)
        groupList.loadViewIfNeeded()
        let groupBell = groupList.navigationItem.rightBarButtonItems?
            .compactMap { $0.customView as? V2NNotificationsBellButton }
        XCTAssertEqual(groupBell?.count ?? 0, 0, "group notes list must not show Caderno bell")
    }

    func testNotificationsCenter_rendersSectionsAndMarkAllButton() async {
        MockNativeURLProtocol.notificationsJSON = Self.page1Payload
        let vc = NotificationsCenterViewController()
        let nav = UINavigationController(rootViewController: vc)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = nav
        window.makeKeyAndVisible()
        vc.loadViewIfNeeded()
        await vc.testing_viewModel.loadInitial()
        XCTAssertEqual(vc.title, String(localized: "Avisos"))
        XCTAssertEqual(vc.navigationItem.rightBarButtonItem?.title, String(localized: "Marcar todas como lidas"))
        XCTAssertGreaterThan(vc.testing_tableView.numberOfSections, 0)
        XCTAssertEqual(vc.testing_viewModel.items.count, 2)
        window.isHidden = true
    }

    func testBellButton_hidesBadgeAtZero_showsCap() {
        let bell = V2NNotificationsBellButton()
        bell.updateBadge(nil)
        XCTAssertNil(bell.accessibilityValue)
        bell.updateBadge("3")
        XCTAssertEqual(bell.accessibilityValue, "3")
        bell.updateBadge("99+")
        XCTAssertEqual(bell.accessibilityValue, "99+")
        XCTAssertEqual(bell.accessibilityLabel, String(localized: "Avisos"))
    }

    // MARK: - Fixtures

    private static let page1Payload = ##"""
    {"ok":true,"items":[
      {"id":"n1","kind":"shares","title":"Nota compartilhada","body":"Ana enviou uma nota","href":"/n/note-1","read":false,"createdAt":"2026-11-10T12:00:00Z"},
      {"id":"n2","kind":"groups","title":"Atividade no grupo","body":"Nova nota no grupo","href":"/groups/g1","read":false,"createdAt":"2026-11-09T12:00:00Z"}
    ],"nextCursor":"cursor-2","unread":3}
    """##

    private static let page2Payload = ##"""
    {"ok":true,"items":[
      {"id":"n3","kind":"reading","title":"Leitura","body":"Dia de hoje","href":"/reading/plan-1","read":true,"createdAt":"2026-11-01T12:00:00Z"}
    ],"nextCursor":null,"unread":2}
    """##

    private static let emptyPayload = ##"{"ok":true,"items":[],"nextCursor":null,"unread":0}"##
}
