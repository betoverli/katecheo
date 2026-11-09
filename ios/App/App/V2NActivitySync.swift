import Foundation

/// Fetches links / granted notes / unread notifications and reconciles `V2NActivityStore`.
/// Call on foreground, account switch, push receipt, and after friend mutations.
/// Debounced (~3 min) unless `force` / push hint; concurrent callers coalesce on one in-flight task.
enum V2NActivitySync {
    private static var inFlight: Task<RefreshResult, Never>?

    /// Result of a refresh attempt (for tests / push path).
    enum RefreshResult: Equatable {
        case updated
        case skippedNoBearer
        case skippedFresh
        case offlineKeptLocal
        case unauthorized
    }

    @MainActor
    @discardableResult
    static func refreshFromServer(force: Bool = false) async -> RefreshResult {
        guard NativeAPIClient.hasBearer else { return .skippedNoBearer }
        if !force, NativeSWR.shouldSkipActivitySync(force: false) {
            return .skippedFresh
        }
        if let existing = inFlight {
            return await existing.value
        }
        let task = Task<RefreshResult, Never> {
            do {
                async let links = NativeAPIClient.listLinks()
                // Force granted on explicit refresh / push so Shared dots stay correct.
                async let granted = NativeAPIClient.listGrantedNotes(force: force)
                // Summary first page + continue unread cursor so dots never miss page 2+.
                async let summary = NativeAPIClient.notificationsSummary()
                let (linkPack, grants, sum) = try await (links, granted, summary)
                var unreadItems = sum.items
                var cursor = sum.nextCursor
                var pages = 0
                while let next = cursor, !next.isEmpty, pages < 40 {
                    pages += 1
                    let page = try await NativeAPIClient.listNotifications(
                        cursor: next,
                        limit: 50,
                        unreadOnly: true
                    )
                    unreadItems.append(contentsOf: page.items)
                    cursor = page.nextCursor
                }
                await MainActor.run {
                    V2NActivityStore.reconcileServer(
                        incoming: linkPack.incoming,
                        granted: grants,
                        inbox: unreadItems
                    )
                }
                NativeSWR.markActivitySyncSuccess()
                return .updated
            } catch NativeAPIClient.APIError.unauthorized {
                return .unauthorized
            } catch {
                // Offline / transient — do **not** invent push dots; keep prior server reconcile.
                return .offlineKeptLocal
            }
        }
        inFlight = task
        let result = await task.value
        inFlight = nil
        return result
    }

    /// Push must not light dots until server state confirms (or refresh is skipped offline).
    @MainActor
    static func handlePushHint(href: String?, title: String?) async {
        _ = href
        _ = title
        // Never persist speculative push items. Reconcile from Bearer account state.
        _ = await refreshFromServer(force: true)
    }

    static func markRead(ids: [String]) async {
        let unique = Array(Set(ids.filter { !$0.isEmpty }))
        guard !unique.isEmpty, NativeAPIClient.hasBearer else { return }
        for id in unique {
            do {
                try await NativeAPIClient.markNotificationsRead(id: id)
            } catch {
                // Idempotent retry on next open/foreground.
            }
        }
    }
}
