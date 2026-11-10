import Foundation

/// Public site identity for Katecheo.
/// Bundle id stays `com.verse2note.app` (and tests `com.verse2note.app.tests`);
/// custom URL scheme is `katecheo://`. API + Associated Domains use katecheo.app only.
enum AppSite {
    static let brandName = "Katecheo"
    static let primaryHost = "katecheo.app"

    static let primaryOrigin = URL(string: "https://katecheo.app")!

    /// Hosts accepted for Universal Links / deep links.
    static let acceptedHosts: Set<String> = [
        "katecheo.app",
        "www.katecheo.app",
    ]

    private static let resolvedDefaultsKey = "katecheo.apiBaseResolved.v1"
    private static let lock = NSLock()
    private static var memoryResolved: URL?

    /// Info.plist override (tests / staging). Empty → primary origin.
    static var configuredOverride: URL? {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "KatecheoAPIBase") as? String,
           let url = URL(string: raw), !raw.isEmpty
        {
            return url
        }
        return nil
    }

    /// Preferred API / share origin.
    static var baseURL: URL {
        if let configuredOverride { return configuredOverride }
        lock.lock(); defer { lock.unlock() }
        if let memoryResolved { return memoryResolved }
        if let stored = UserDefaults.standard.string(forKey: resolvedDefaultsKey),
           let url = URL(string: stored),
           let host = url.host?.lowercased(),
           acceptedHosts.contains(host)
        {
            memoryResolved = url
            return url
        }
        return primaryOrigin
    }

    static func absoluteURL(path: String) -> URL {
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return baseURL.appendingPathComponent(trimmed)
    }

    static func privacyURL() -> URL { absoluteURL(path: "privacy") }
    static func aboutURL() -> URL { absoluteURL(path: "about") }
    static func termsURL() -> URL { absoluteURL(path: "about") }

    /// No legacy-host fallback: katecheo.app is the only API domain in the app.
    @discardableResult
    static func considerFallback(after error: Error, for requestURL: URL?) -> Bool {
        _ = error
        _ = requestURL
        return false
    }

    static func resetResolvedBaseForTests() {
        lock.lock()
        memoryResolved = nil
        lock.unlock()
        UserDefaults.standard.removeObject(forKey: resolvedDefaultsKey)
    }
}
