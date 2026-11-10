import Foundation
import UIKit

/// Per-account unread activity for tab/chip dots (build-238).
/// Notification Center reads clear matching items via `notificationIds`.
///
/// Sources of truth after Beto-approved native wraps:
/// - Friends pending → `GET /links` incoming (clears only on accept/decline)
/// - Friend accepted / shares / groups / reading digests → unread `GET /notifications`
/// - Shared grants list → `GET /notes/granted` (+ shares unread for dots)
/// - Group pending → native members API
/// - Seen cross-device → `POST /notifications/read` (`read_at`)
enum V2NActivityStore {
    enum Kind: String, Codable, CaseIterable {
        case sharedNote
        case groupActivity
        case groupPending
        case friendPending
        case friendAccepted
        case readingDue
    }

    enum Source: String, Codable {
        case links
        case inbox
        case grants
        case members
        case push
        case local
    }

    struct Item: Codable, Equatable, Hashable {
        var id: String
        var kind: Kind
        var targetId: String
        var title: String?
        var createdAt: Date
        var notificationIds: [String]
        var source: Source

        init(
            id: String,
            kind: Kind,
            targetId: String,
            title: String? = nil,
            createdAt: Date = Date(),
            notificationIds: [String] = [],
            source: Source
        ) {
            self.id = id
            self.kind = kind
            self.targetId = targetId
            self.title = title
            self.createdAt = createdAt
            self.notificationIds = notificationIds
            self.source = source
        }

        enum CodingKeys: String, CodingKey {
            case id, kind, targetId, title, createdAt, notificationIds, source
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            kind = try c.decode(Kind.self, forKey: .kind)
            targetId = try c.decode(String.self, forKey: .targetId)
            title = try c.decodeIfPresent(String.self, forKey: .title)
            createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
            notificationIds = try c.decodeIfPresent([String].self, forKey: .notificationIds) ?? []
            source = try c.decodeIfPresent(Source.self, forKey: .source) ?? .local
        }
    }

    private static let changed = Notification.Name("v2n.activity.changed")
    static var didChangeNotification: Notification.Name { changed }

    /// Friends dots are live once links accept/decline exist.
    static let friendsDotsEnabled = true

    private static func accountId() -> String? {
        LocalSessionCache.loadMe()?.id
    }

    private static func storageKey(for accountId: String) -> String {
        "v2n.activity.items.\(accountId)"
    }

    private static func baselineKey(for accountId: String) -> String {
        "v2n.activity.sharedBaseline.\(accountId)"
    }

    private static func loadItems() -> [Item] {
        guard let accountId = accountId(),
              let data = UserDefaults.standard.data(forKey: storageKey(for: accountId)),
              let items = try? JSONDecoder().decode([Item].self, from: data)
        else { return [] }
        return items
    }

    private static func saveItems(_ items: [Item]) {
        guard let accountId = accountId() else { return }
        let unique = Dictionary(grouping: items, by: \.id).compactMap { $0.value.first }
        if let data = try? JSONEncoder().encode(unique) {
            UserDefaults.standard.set(data, forKey: storageKey(for: accountId))
        }
        NotificationCenter.default.post(name: changed, object: nil)
    }

    static func all() -> [Item] { loadItems() }

    static func items(kind: Kind) -> [Item] {
        loadItems().filter { $0.kind == kind }
    }

    static func hasAny(kinds: Kind...) -> Bool {
        let set = Set(kinds)
        return loadItems().contains { set.contains($0.kind) }
    }

    static func targetIds(kind: Kind) -> Set<String> {
        Set(items(kind: kind).map(\.targetId))
    }

    static func notificationIds(for kind: Kind, targetId: String? = nil) -> [String] {
        loadItems()
            .filter { $0.kind == kind && (targetId == nil || $0.targetId == targetId) }
            .flatMap(\.notificationIds)
    }

    static func upsert(
        kind: Kind,
        targetId: String,
        title: String? = nil,
        notificationIds: [String] = [],
        source: Source
    ) {
        guard accountId() != nil, !targetId.isEmpty else { return }
        let id = "\(kind.rawValue):\(targetId)"
        var items = loadItems()
        if let idx = items.firstIndex(where: { $0.id == id }) {
            if let title { items[idx].title = title }
            let merged = Set(items[idx].notificationIds).union(notificationIds)
            items[idx].notificationIds = Array(merged)
            items[idx].source = source
            saveItems(items)
            return
        }
        items.append(
            Item(
                id: id,
                kind: kind,
                targetId: targetId,
                title: title,
                notificationIds: notificationIds,
                source: source
            )
        )
        saveItems(items)
    }

    static func clear(kind: Kind, targetId: String) {
        let id = "\(kind.rawValue):\(targetId)"
        saveItems(loadItems().filter { $0.id != id })
    }

    static func clearKind(_ kind: Kind) {
        saveItems(loadItems().filter { $0.kind != kind })
    }

    static func clearAccount(_ explicitAccountId: String? = nil) {
        guard let accountId = explicitAccountId ?? accountId() else { return }
        UserDefaults.standard.removeObject(forKey: storageKey(for: accountId))
        UserDefaults.standard.removeObject(forKey: baselineKey(for: accountId))
        // Also drop opened-note flags for this account prefix.
        let prefix = "v2n.activity.openedNote.\(accountId)."
        for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            UserDefaults.standard.removeObject(forKey: key)
        }
        NotificationCenter.default.post(name: changed, object: nil)
    }

    // MARK: - Server reconcile (links + grants + inbox)

    /// Replace server-backed kinds from a fresh fetch. Keeps `groupPending` (members) and
    /// does not invent unmarked reading days or visibility heuristics.
    static func reconcileServer(
        incoming: [NativeAPIClient.LinkPersonDTO],
        granted: [NativeAPIClient.NoteDocument],
        inbox: [NativeAPIClient.InboxItemDTO]
    ) {
        guard let accountId = accountId() else { return }
        // Drop speculative push leftovers; members pending + explicit local only survive.
        var next = loadItems().filter { item in
            item.source == .members || item.source == .local
        }
        let unread = inbox.filter { !$0.read }

        // Friends pending — links.incoming only; persists until accept/decline.
        for person in incoming {
            let target = person.handle.isEmpty ? person.userId : person.handle
            next.append(
                Item(
                    id: "\(Kind.friendPending.rawValue):\(target)",
                    kind: .friendPending,
                    targetId: target,
                    title: person.displayName,
                    notificationIds: [],
                    source: .links
                )
            )
        }

        // Shared grants baseline + unread shares from inbox.
        let grantedIds = Set(granted.map(\.id))
        let baselineDone = UserDefaults.standard.bool(forKey: baselineKey(for: accountId))
        if !baselineDone {
            for id in grantedIds {
                UserDefaults.standard.set(true, forKey: openedNoteKey(accountId: accountId, noteId: id))
            }
            UserDefaults.standard.set(true, forKey: baselineKey(for: accountId))
        }

        var shareNotifByNote: [String: [String]] = [:]
        var friendAcceptedNotifs: [String] = []
        var groupNotifById: [String: [String]] = [:]
        var readingNotifByPlan: [String: [String]] = [:]

        for item in unread {
            let dest = NativeDeepLinkRouter.destination(href: item.href)
            switch item.kind {
            case "shares":
                if case .note(let noteId) = dest {
                    shareNotifByNote[noteId, default: []].append(item.id)
                }
            case "friends":
                // Acceptance / social friend events (pending list comes from links).
                friendAcceptedNotifs.append(item.id)
            case "groups":
                if case .group(let groupId) = dest {
                    groupNotifById[groupId, default: []].append(item.id)
                } else {
                    groupNotifById["_groups", default: []].append(item.id)
                }
            case "reading":
                if case .readingPlan(let planId) = dest {
                    readingNotifByPlan[planId, default: []].append(item.id)
                } else {
                    readingNotifByPlan["digest", default: []].append(item.id)
                }
            default:
                break
            }
        }

        for note in granted {
            let opened = UserDefaults.standard.bool(forKey: openedNoteKey(accountId: accountId, noteId: note.id))
            let notifs = shareNotifByNote[note.id] ?? []
            if !opened || !notifs.isEmpty {
                next.append(
                    Item(
                        id: "\(Kind.sharedNote.rawValue):\(note.id)",
                        kind: .sharedNote,
                        targetId: note.id,
                        title: note.title,
                        notificationIds: notifs,
                        source: notifs.isEmpty ? .grants : .inbox
                    )
                )
            }
        }
        // Unread share for a note not yet in granted list (race) — still show target.
        for (noteId, notifs) in shareNotifByNote where !grantedIds.contains(noteId) {
            next.append(
                Item(
                    id: "\(Kind.sharedNote.rawValue):\(noteId)",
                    kind: .sharedNote,
                    targetId: noteId,
                    title: nil,
                    notificationIds: notifs,
                    source: .inbox
                )
            )
        }

        if !friendAcceptedNotifs.isEmpty {
            next.append(
                Item(
                    id: "\(Kind.friendAccepted.rawValue):inbox",
                    kind: .friendAccepted,
                    targetId: "inbox",
                    title: nil,
                    notificationIds: friendAcceptedNotifs,
                    source: .inbox
                )
            )
        }

        for (groupId, notifs) in groupNotifById {
            next.append(
                Item(
                    id: "\(Kind.groupActivity.rawValue):\(groupId)",
                    kind: .groupActivity,
                    targetId: groupId,
                    title: nil,
                    notificationIds: notifs,
                    source: .inbox
                )
            )
        }

        for (planId, notifs) in readingNotifByPlan {
            next.append(
                Item(
                    id: "\(Kind.readingDue.rawValue):\(planId)",
                    kind: .readingDue,
                    targetId: planId,
                    title: nil,
                    notificationIds: notifs,
                    source: .inbox
                )
            )
        }

        saveItems(next)
    }

    // MARK: - Shared notes

    /// Legacy no-op: owned notes visibility is not grants. Use `reconcileServer`.
    static func reconcileSharedNotes(_ notes: [NativeAPIClient.NoteDocument]) {
        _ = notes
    }

    static func markSharedNoteOpened(_ noteId: String) {
        guard let accountId = accountId() else { return }
        UserDefaults.standard.set(true, forKey: openedNoteKey(accountId: accountId, noteId: noteId))
        let ids = notificationIds(for: .sharedNote, targetId: noteId)
        clear(kind: .sharedNote, targetId: noteId)
        Task { await V2NActivitySync.markRead(ids: ids) }
    }

    private static func openedNoteKey(accountId: String, noteId: String) -> String {
        "v2n.activity.openedNote.\(accountId).\(noteId)"
    }

    // MARK: - Reading due

    /// Heuristic unmarked-day reconcile stays off — digest rows come from inbox.
    static func reconcileReadingDue(prefs: NativeAPIClient.PrefsDTO?, plans: [NativeAPIClient.PlanCardDTO]) {
        _ = prefs
        _ = plans
    }

    static func dismissReadingDue(planId: String) {
        let ids = notificationIds(for: .readingDue, targetId: planId)
            + notificationIds(for: .readingDue, targetId: "digest")
        clear(kind: .readingDue, targetId: planId)
        clear(kind: .readingDue, targetId: "digest")
        Task { await V2NActivitySync.markRead(ids: ids) }
    }

    // MARK: - Groups

    static func ingestGroupActivity(groupId: String, title: String? = nil) {
        upsert(kind: .groupActivity, targetId: groupId, title: title, source: .push)
    }

    static func markGroupViewed(_ groupId: String) {
        let ids = notificationIds(for: .groupActivity, targetId: groupId)
            + notificationIds(for: .groupActivity, targetId: "_groups")
        clear(kind: .groupActivity, targetId: groupId)
        clear(kind: .groupActivity, targetId: "_groups")
        Task { await V2NActivitySync.markRead(ids: ids) }
    }

    static func reconcileGroupPending(groupId: String, pendingCount: Int) {
        if pendingCount > 0 {
            upsert(kind: .groupPending, targetId: groupId, source: .members)
        } else {
            clear(kind: .groupPending, targetId: groupId)
        }
    }

    // MARK: - Friends

    static func ingestFriendPending(targetId: String = "inbox", title: String? = nil) {
        upsert(kind: .friendPending, targetId: targetId, title: title, source: .push)
    }

    static func ingestFriendAccepted(targetId: String, title: String? = nil) {
        upsert(kind: .friendAccepted, targetId: targetId, title: title, source: .push)
    }

    /// Clears acceptance signals only — never pending requests.
    static func markFriendsAcceptedSeen() {
        let ids = notificationIds(for: .friendAccepted)
        clearKind(.friendAccepted)
        Task { await V2NActivitySync.markRead(ids: ids) }
    }

    static func clearFriendPending(targetId: String) {
        clear(kind: .friendPending, targetId: targetId)
    }

    // MARK: - Notification Center ↔ dots

    /// Removes inbox notification ids acknowledged in the Notification Center.
    /// Drops inbox-backed items once their ids are gone; keeps unopened shared grants.
    static func acknowledgeNotificationIds(_ ids: [String]) {
        let idSet = Set(ids.filter { !$0.isEmpty })
        guard !idSet.isEmpty else { return }
        var changed = false
        var next: [Item] = []
        for var item in loadItems() {
            let before = item.notificationIds
            guard !before.isEmpty else {
                next.append(item)
                continue
            }
            let after = before.filter { !idSet.contains($0) }
            if after.count == before.count {
                next.append(item)
                continue
            }
            changed = true
            item.notificationIds = after
            if after.isEmpty {
                // Keep non-inbox sources. Do **not** promote inbox-only shares to `.grants`
                // (that would leave the Caderno dot lit after reading in the center).
                // Unopened grants are restored on the next server reconcile if still unseen.
                if item.source == .links || item.source == .members || item.source == .local || item.source == .grants {
                    next.append(item)
                } else if item.kind == .friendPending {
                    next.append(item)
                }
                // else: drop inbox-backed friendAccepted / groupActivity / readingDue / share
            } else {
                next.append(item)
            }
        }
        if changed {
            saveItems(next)
        }
    }

    /// Clears every inbox-backed activity item (mark-all-read in the center).
    /// Keeps links pending, members pending, and unopened shared grants.
    static func acknowledgeAllInboxNotifications() {
        let account = accountId()
        let next = loadItems().compactMap { item -> Item? in
            if item.source == .links || item.source == .members || item.source == .local {
                var copy = item
                copy.notificationIds = []
                return copy
            }
            if item.kind == .sharedNote,
               let account,
               !UserDefaults.standard.bool(forKey: openedNoteKey(accountId: account, noteId: item.targetId)) {
                var copy = item
                copy.notificationIds = []
                copy.source = .grants
                return copy
            }
            if item.kind == .friendPending {
                var copy = item
                copy.notificationIds = []
                return copy
            }
            return nil
        }
        saveItems(next)
    }

    // MARK: - Push

    /// Speculative push dots are forbidden — server reconcile only (`V2NActivitySync.handlePushHint`).
    /// Kept as a no-op so call sites compile; does not mutate the store.
    static func ingestPush(href: String, title: String?) {
        _ = href
        _ = title
    }

    // MARK: - Aggregates (children roll up; parent visit does not clear)

    static var notebookDot: Bool { hasAny(kinds: .sharedNote) }
    static var groupsDot: Bool { hasAny(kinds: .groupActivity, .groupPending) }
    static var toolsDot: Bool { hasAny(kinds: .readingDue) }
    static var profileDot: Bool { friendsDotsEnabled && hasAny(kinds: .friendPending, .friendAccepted) }
    static var sharedChipDot: Bool { notebookDot }
    static var readingChipDot: Bool { toolsDot }
    static var friendsEntryDot: Bool { profileDot }
}
