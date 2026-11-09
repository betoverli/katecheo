import Foundation

/// Public site identity for Katecheo. Bundle id / URL schemes stay `com.verse2note.*`
/// / `verse2note` for install continuity; user-visible brand is Katecheo.
enum AppSite {
    static let brandName = "Katecheo"
    static let primaryHost = "katecheo.app"
    static let fallbackHost = "verse2note.com"

    static let primaryOrigin = URL(string: "https://katecheo.app")!
    static let fallbackOrigin = URL(string: "https://verse2note.com")!

    /// Hosts accepted for Universal Links / deep links during cutover.
    static let acceptedHosts: Set<String> = [
        "katecheo.app",
        "www.katecheo.app",
        "verse2note.com",
        "www.verse2note.com",
    ]

    private static let resolvedDefaultsKey = "katecheo.apiBaseResolved.v1"
    private static let lock = NSLock()
    private static var memoryResolved: URL?

    /// Info.plist override (tests / staging). Empty → primary with fallback.
    static var configuredOverride: URL? {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "Verse2NoteAPIBase") as? String,
           let url = URL(string: raw), !raw.isEmpty
        {
            return url
        }
        return nil
    }

    /// Preferred API / share origin. Uses last successful host after a fallback probe.
    static var baseURL: URL {
        if let configuredOverride { return configuredOverride }
        lock.lock(); defer { lock.unlock() }
        if let memoryResolved { return memoryResolved }
        if let stored = UserDefaults.standard.string(forKey: resolvedDefaultsKey),
           let url = URL(string: stored)
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

    /// After a transport failure against the primary host, flip to the legacy origin once.
    @discardableResult
    static func considerFallback(after error: Error, for requestURL: URL?) -> Bool {
        if configuredOverride != nil { return false }
        guard let host = requestURL?.host?.lowercased() else { return false }
        let primary = host == primaryHost || host == "www.\(primaryHost)"
        guard primary else { return false }
        let ns = error as NSError
        // DNS / TLS / cannot connect — typical pre-propagation failures.
        let retryable = [
            NSURLErrorCannotFindHost,
            NSURLErrorDNSLookupFailed,
            NSURLErrorSecureConnectionFailed,
            NSURLErrorServerCertificateUntrusted,
            NSURLErrorCannotConnectToHost,
            NSURLErrorTimedOut,
            NSURLErrorNotConnectedToInternet,
        ]
        guard retryable.contains(ns.code) else { return false }
        lock.lock()
        memoryResolved = fallbackOrigin
        lock.unlock()
        UserDefaults.standard.set(fallbackOrigin.absoluteString, forKey: resolvedDefaultsKey)
        return true
    }

    static func resetResolvedBaseForTests() {
        lock.lock()
        memoryResolved = nil
        lock.unlock()
        UserDefaults.standard.removeObject(forKey: resolvedDefaultsKey)
    }
}
