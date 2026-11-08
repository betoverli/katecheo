import Foundation

/// Fetches links / granted notes / notifications and reconciles `V2NActivityStore`.
/// Call on foreground, account switch, and after friend accept/decline.
enum V2NActivitySync {
    private static var inFlight: Task<Void, Never>?

    @MainActor
    static func refreshFromServer() async {
        guard NativeAPIClient.hasBearer else { return }
        if let existing = inFlight {
            await existing.value
            return
        }
        let task = Task {
            do {
                async let links = NativeAPIClient.listLinks()
                async let granted = NativeAPIClient.listGrantedNotes()
                async let inbox = NativeAPIClient.listNotifications()
                let (linkPack, grants, notifPack) = try await (links, granted, inbox)
                await MainActor.run {
                    V2NActivityStore.reconcileServer(
                        incoming: linkPack.incoming,
                        granted: grants,
                        inbox: notifPack.items
                    )
                }
            } catch NativeAPIClient.APIError.unauthorized {
                // Session handler elsewhere; do not clear other accounts' stores here.
            } catch {
                // Keep last known local dots offline.
            }
        }
        inFlight = task
        await task.value
        inFlight = nil
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
