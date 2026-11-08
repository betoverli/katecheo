import Foundation
import UIKit

/// Per-account unread activity for tab/chip dots (build-238).
/// No notification center — only reachable destinations.
///
/// Sync reality:
/// - Shared notes / reading due / group pending: derived from native APIs already on device.
/// - Push-ingested items (group activity, friend signals): device-local until a native inbox API exists.
/// - No cross-device sync of read state without `/api/native/v1/notifications`.
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

    /// First paint after sign-in baselines existing shared notes so they are not all "new".
    static func reconcileSharedNotes(_ notes: [NativeAPIClient.NoteDocument]) {
        guard let accountId = accountId() else { return }
        let shared = notes.filter { $0.visibility == "shared" || $0.visibility == "link" }
        let sharedIds = Set(shared.map(\.id))
        let baselineDone = UserDefaults.standard.bool(forKey: baselineKey(for: accountId))
        if !baselineDone {
            for id in sharedIds {
                // Seed as already seen — only notes arriving after baseline get dots.
                clear(kind: .sharedNote, targetId: id)
            }
            UserDefaults.standard.set(true, forKey: baselineKey(for: accountId))
            return
        }
        var items = loadItems().filter { $0.kind != .sharedNote || sharedIds.contains($0.targetId) }
        let existing = Set(items.filter { $0.kind == .sharedNote }.map(\.targetId))
        for note in shared where !existing.contains(note.id) {
            // Only add if never opened on this account/device.
            let openedKey = openedNoteKey(accountId: accountId, noteId: note.id)
            if UserDefaults.standard.bool(forKey: openedKey) { continue }
            items.append(
                Item(
                    id: "\(Kind.sharedNote.rawValue):\(note.id)",
                    kind: .sharedNote,
                    targetId: note.id,
                    title: note.title,
                    createdAt: Date()
                )
            )
        }
        saveItems(items)
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

    static func reconcileReadingDue(prefs: NativeAPIClient.PrefsDTO?, plans: [NativeAPIClient.PlanCardDTO]) {
        let active = prefs?.activePlans ?? []
        let progress = prefs?.planProgress ?? [:]
        var items = loadItems().filter { $0.kind != .readingDue }
        for planId in active {
            let plan = plans.first { $0.id == planId }
            let days = max(plan?.days ?? 0, 0)
            guard days > 0 else { continue }
            let marked = Set(progress[planId] ?? [])
            let next = (1...days).first { !marked.contains($0) }
            if next != nil {
                items.append(
                    Item(
                        id: "\(Kind.readingDue.rawValue):\(planId)",
                        kind: .readingDue,
                        targetId: planId,
                        title: plan?.name,
                        createdAt: Date()
                    )
                )
            }
        }
        saveItems(items)
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

    // MARK: - Friends (push-sourced; no native friends API)

    static func ingestFriendPending(targetId: String = "inbox", title: String? = nil) {
        upsert(kind: .friendPending, targetId: targetId, title: title)
    }

    static func ingestFriendAccepted(targetId: String, title: String? = nil) {
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
            // Shared / group note deep link — treat as shared until opened.
            upsert(kind: .sharedNote, targetId: id, title: title)
        case .readingPlan(let id):
            upsert(kind: .readingDue, targetId: id, title: title)
        case .reading:
            // Generic reading digest — attach to a placeholder cleared when any plan is marked.
            upsert(kind: .readingDue, targetId: "digest", title: title)
        case .profile:
            // /profile/friends and /inbox land on profile — friend signal without kind field.
            if href.contains("friends") {
                ingestFriendPending(title: title)
            } else {
                ingestFriendAccepted(targetId: "seen", title: title)
            }
        default:
            break
        }
    }

    // MARK: - Aggregates for chrome

    static var notebookDot: Bool { hasAny(kinds: .sharedNote) }
    static var groupsDot: Bool { hasAny(kinds: .groupActivity, .groupPending) }
    static var toolsDot: Bool { hasAny(kinds: .readingDue) }
    static var profileDot: Bool { hasAny(kinds: .friendPending, .friendAccepted) }
    static var sharedChipDot: Bool { notebookDot }
    static var readingChipDot: Bool { toolsDot }
    static var friendsEntryDot: Bool { profileDot }
}
