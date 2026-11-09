import Foundation

/// Fetches links / granted notes / unread notifications and reconciles `V2NActivityStore`.
/// Call on foreground, account switch, push receipt, and after friend mutations.
enum V2NActivitySync {
    private static var inFlight: Task<Void, Never>?

    /// Result of a refresh attempt (for tests / push path).
    enum RefreshResult: Equatable {
        case updated
        case skippedNoBearer
        case offlineKeptLocal
        case unauthorized
    }

    @MainActor
    @discardableResult
    static func refreshFromServer() async -> RefreshResult {
        guard NativeAPIClient.hasBearer else { return .skippedNoBearer }
        if let existing = inFlight {
            await existing.value
            return .updated
        }
        var result: RefreshResult = .offlineKeptLocal
        let task = Task {
            do {
                async let links = NativeAPIClient.listLinks()
                async let granted = NativeAPIClient.listGrantedNotes()
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
                result = .updated
            } catch NativeAPIClient.APIError.unauthorized {
                result = .unauthorized
            } catch {
                // Offline / transient — do **not** invent push dots; keep prior server reconcile.
                result = .offlineKeptLocal
            }
        }
        inFlight = task
        await task.value
        inFlight = nil
        return result
    }

    /// Push must not light dots until server state confirms (or refresh is skipped offline).
    @MainActor
    static func handlePushHint(href: String?, title: String?) async {
        _ = href
        _ = title
        // Never persist speculative push items. Reconcile from Bearer account state.
        _ = await refreshFromServer()
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
