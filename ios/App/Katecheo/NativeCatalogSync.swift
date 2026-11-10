import Foundation

/// Themes / Reading catalogs: disk-first, refresh on silent push or version mismatch (not on every appear).
enum NativeCatalogSync {
    static let themesDidChange = Notification.Name("katecheo.catalog.themesDidChange")
    static let readingDidChange = Notification.Name("katecheo.catalog.readingDidChange")

    /// Lightweight GET /catalog/versions — call on foreground / launch.
    @MainActor
    static func checkVersionsOnForeground() async {
        do {
            let versions = try await NativeAPIClient.fetchCatalogVersions()
            var themesChanged = false
            var readingChanged = false
            if let remote = versions.themes, !remote.isEmpty {
                if NativeSWR.storedThemesVersion != remote {
                    NativeSWR.invalidateThemesCatalog()
                    NativeSWR.storedThemesVersion = remote
                    themesChanged = true
                }
            }
            if let remote = versions.reading, !remote.isEmpty {
                if NativeSWR.storedReadingVersion != remote {
                    NativeSWR.invalidateReadingCatalog()
                    NativeSWR.storedReadingVersion = remote
                    readingChanged = true
                }
            }
            if themesChanged {
                NotificationCenter.default.post(name: themesDidChange, object: nil)
            }
            if readingChanged {
                NotificationCenter.default.post(name: readingDidChange, object: nil)
            }
        } catch {
            // Offline — keep disk catalogs.
        }
    }

    /// Silent push `type` → invalidate + notify UI.
    @MainActor
    static func handleSilentPush(type: String?) {
        guard let type, !type.isEmpty else { return }
        switch type {
        case "themes_updated":
            NativeSWR.invalidateThemesCatalog()
            NotificationCenter.default.post(name: themesDidChange, object: nil)
        case "reading_updated":
            NativeSWR.invalidateReadingCatalog()
            NotificationCenter.default.post(name: readingDidChange, object: nil)
        default:
            break
        }
    }
}
