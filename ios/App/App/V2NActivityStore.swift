import Foundation
import UIKit

/// Per-account unread activity for tab/chip dots (build-238).
/// No notification center — only reachable destinations.
///
/// Honest scope (audit 2026-11-08):
/// - Supported now: `groupPending` (native members + decide); push-ingested
///   group/reading/note opens (device-local until native inbox).
/// - Gated / incomplete: Shared grants, friends pending/accept, digest-due reading,
///   stable group activity unread, account-level cross-device seen — web has the data
///   (`listGrantedNotes`, `listLinks`/`acceptLink`/`declineLink`, `listNotifications`/
///   `markNotificationsRead` + `read_at`); native `/api/native/v1` does not wrap them yet.
/// Do not merge heuristic badge kinds as “complete.”
enum V2NActivityStore {
    enum Kind: String, Codable, CaseIterable {
        case sharedNote
        case groupActivity
        case groupPending
        case friendPending
        case friendAccepted
        case readingDue
    }

    struct Item: Codable, Equatable, Hashable {
        var id: String
        var kind: Kind
        var targetId: String
        var title: String?
        var createdAt: Date
    }

    private static let changed = Notification.Name("v2n.activity.changed")
    static var didChangeNotification: Notification.Name { changed }

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

    static func upsert(kind: Kind, targetId: String, title: String? = nil) {
        guard accountId() != nil, !targetId.isEmpty else { return }
        let id = "\(kind.rawValue):\(targetId)"
        var items = loadItems()
        if let idx = items.firstIndex(where: { $0.id == id }) {
            if let title { items[idx].title = title }
            saveItems(items)
            return
        }
        items.append(Item(id: id, kind: kind, targetId: targetId, title: title, createdAt: Date()))
        saveItems(items)
    }

    static func clear(kind: Kind, targetId: String) {
        let id = "\(kind.rawValue):\(targetId)"
        saveItems(loadItems().filter { $0.id != id })
    }

    static func clearKind(_ kind: Kind) {
        saveItems(loadItems().filter { $0.kind != kind })
    }

    static func clearAccount() {
        guard let accountId = accountId() else { return }
        UserDefaults.standard.removeObject(forKey: storageKey(for: accountId))
        UserDefaults.standard.removeObject(forKey: baselineKey(for: accountId))
        NotificationCenter.default.post(name: changed, object: nil)
    }

    // MARK: - Shared notes (Caderno → Compartilhadas)

    /// Incomplete without native `listGrantedNotes`.
    /// Do **not** invent unread from `visibility == shared|link` — the native notes list
    /// only returns owned notes coerced to `private|unlisted`, so that filter never equals
    /// real grants (web uses `note_grants` via `listGrantedNotes`).
    /// Push `/n/{id}` may still upsert a reachable note open; Shared chip/tab stay off
    /// (`notebookDot` / `sharedChipDot`) until grants exist.
    static func reconcileSharedNotes(_ notes: [NativeAPIClient.NoteDocument]) {
        _ = notes
        _ = baselineKey
    }

    static func markSharedNoteOpened(_ noteId: String) {
        guard let accountId = accountId() else { return }
        UserDefaults.standard.set(true, forKey: openedNoteKey(accountId: accountId, noteId: noteId))
        clear(kind: .sharedNote, targetId: noteId)
    }

    private static func openedNoteKey(accountId: String, noteId: String) -> String {
        "v2n.activity.openedNote.\(accountId).\(noteId)"
    }

    // MARK: - Reading due

    /// Incomplete without digest/inbox semantics.
    /// Server due = `maybeSendDigests` (one `kind=reading` row/day when there is a next unmarked
    /// day). Treating “any unmarked day on any active plan” as due is a heuristic — disabled.
    /// Push `/reading/{planId}` ingest remains (reachable destination).
    static func reconcileReadingDue(prefs: NativeAPIClient.PrefsDTO?, plans: [NativeAPIClient.PlanCardDTO]) {
        _ = prefs
        _ = plans
        // No-op: keep only push-ingested readingDue items already in the store.
    }

    static func dismissReadingDue(planId: String) {
        clear(kind: .readingDue, targetId: planId)
    }

    // MARK: - Groups

    static func ingestGroupActivity(groupId: String, title: String? = nil) {
        upsert(kind: .groupActivity, targetId: groupId, title: title)
    }

    static func markGroupViewed(_ groupId: String) {
        clear(kind: .groupActivity, targetId: groupId)
    }

    static func reconcileGroupPending(groupId: String, pendingCount: Int) {
        if pendingCount > 0 {
            upsert(kind: .groupPending, targetId: groupId)
        } else {
            clear(kind: .groupPending, targetId: groupId)
        }
    }

    // MARK: - Friends (blocked until native wrap of links.ts)

    /// Web already has `listLinks` / `acceptLink` / `declineLink`. Native has none.
    /// Do not create Profile dots that open a dead-end Amigos screen.
    static let friendsDotsEnabled = false

    static func ingestFriendPending(targetId: String = "inbox", title: String? = nil) {
        guard friendsDotsEnabled else { return }
        upsert(kind: .friendPending, targetId: targetId, title: title)
    }

    static func ingestFriendAccepted(targetId: String, title: String? = nil) {
        guard friendsDotsEnabled else { return }
        upsert(kind: .friendAccepted, targetId: targetId, title: title)
    }

    static func markFriendsAcceptedSeen() {
        clearKind(.friendAccepted)
    }

    // MARK: - Push href ingest

    static func ingestPush(href: String, title: String?) {
        let dest = NativeDeepLinkRouter.destination(href: href)
        switch dest {
        case .group(let id):
            ingestGroupActivity(groupId: id, title: title)
        case .note(let id):
            // Reachable note open — not claimed as grant/Shared until listGrantedNotes exists.
            upsert(kind: .sharedNote, targetId: id, title: title)
        case .readingPlan(let id):
            upsert(kind: .readingDue, targetId: id, title: title)
        case .reading:
            upsert(kind: .readingDue, targetId: "digest", title: title)
        case .profile:
            // Friends dots gated — push still opens Profile via deep link, without a lying badge.
            if friendsDotsEnabled {
                if href.contains("friends") {
                    ingestFriendPending(title: title)
                } else {
                    ingestFriendAccepted(targetId: "seen", title: title)
                }
            }
        default:
            break
        }
    }

    // MARK: - Aggregates for chrome

    /// Only kinds with a real native destination + clear path today.
    /// Shared grants / friends / digest-due / cross-device seen need Beto-approved native wraps.
    static var notebookDot: Bool { false } // blocked: needs listGrantedNotes
    static var groupsDot: Bool { hasAny(kinds: .groupActivity, .groupPending) }
    static var toolsDot: Bool { hasAny(kinds: .readingDue) } // push-ingested digest/plan only
    static var profileDot: Bool { friendsDotsEnabled && hasAny(kinds: .friendPending, .friendAccepted) }
    static var sharedChipDot: Bool { false }
    static var readingChipDot: Bool { toolsDot }
    static var friendsEntryDot: Bool { profileDot }

    /// What is actually supported without new server routes (for docs/PR).
    static var supportedWithoutNewBackend: [String] {
        [
            "groupPending (GET members + POST decide)",
            "groupActivity / readingDue / note open from APNs href (device-local until inbox API)",
        ]
    }
}
