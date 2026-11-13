import Foundation

/// Stale-while-revalidate helpers for native GET traffic.
/// Correctness: mutations invalidate; account switch clears account-scoped keys;
/// pull-to-refresh / `force` always hits the network; concurrent callers coalesce.
enum NativeSWR {
    enum Key: Hashable, CustomStringConvertible {
        case notes
        case speakers
        case granted
        case groups
        case groupNotes(String)
        case prefs
        case me
        case note(String)
        case bibleBooks(String)
        case authProviders
        case themesCatalog
        case readingCatalog

        var description: String {
            switch self {
            case .notes: return "notes"
            case .speakers: return "speakers"
            case .granted: return "granted"
            case .groups: return "groups"
            case .groupNotes(let id): return "groupNotes:\(id)"
            case .prefs: return "prefs"
            case .me: return "me"
            case .note(let id): return "note:\(id)"
            case .bibleBooks(let locale): return "bibleBooks:\(locale)"
            case .authProviders: return "authProviders"
            case .themesCatalog: return "themesCatalog"
            case .readingCatalog: return "readingCatalog"
            }
        }

        var isAccountScoped: Bool {
            switch self {
            case .bibleBooks, .authProviders, .themesCatalog, .readingCatalog: return false
            default: return true
            }
        }
    }

    /// Sensible TTLs (seconds).
    enum TTL {
        static let lists: TimeInterval = 180 // notes / speakers / granted / groups
        /// Group detail notes — short throttle so re-open skips network (~30s).
        static let groupNotes: TimeInterval = 30
        static let prefs: TimeInterval = 180
        static let me: TimeInterval = 180
        static let note: TimeInterval = 45
        /// Bible books never expire by time — only by `bibleBooksBundleVersion`.
        static let bibleBooks: TimeInterval = .greatestFiniteMagnitude
        static let authProviders: TimeInterval = 604_800 // 7 days
        static let activitySync: TimeInterval = 180
        /// Themes / reading catalog: treat as permanent until push / version bump / pull-to-refresh.
        static let catalogContent: TimeInterval = .greatestFiniteMagnitude
    }

    /// Must match `scripts/generate-bible-books-bundle.mjs` → `BIBLE_BOOKS_BUNDLE_VERSION`.
    static let bibleBooksBundleVersion = 1

    private static let lock = NSLock()
    private static var fetchedAt: [String: Date] = [:]
    private static var memory: [String: Any] = [:]
    private static var inFlight: [String: Any] = [:]
    /// Bumped on `invalidate` so in-flight GETs started before a mutation cannot
    /// `markFetched` / `saveDisk` with a pre-mutation snapshot (coalesce race).
    private static var epoch: [String: UInt64] = [:]
    private static var activityLastForceAt: Date?
    private static var activityLastSuccessAt: Date?

    // MARK: - Probe (tests)

    /// When true, `NativeAPIClient.perform` records path hits for assertions.
    static var networkProbeEnabled = false
    private static var networkHits: [String] = []

    static func resetProbe() {
        lock.lock(); defer { lock.unlock() }
        networkHits = []
    }

    static func recordNetworkHit(_ path: String) {
        guard networkProbeEnabled else { return }
        lock.lock(); defer { lock.unlock() }
        networkHits.append(path)
    }

    static func probeHits() -> [String] {
        lock.lock(); defer { lock.unlock() }
        return networkHits
    }

    static func probeCount(containing fragment: String) -> Int {
        probeHits().filter { $0.contains(fragment) }.count
    }

    // MARK: - Freshness

    static func isFresh(_ key: Key, ttl: TimeInterval, now: Date = Date()) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let at = fetchedAt[key.description] else { return false }
        return now.timeIntervalSince(at) < ttl
    }

    static func markFetched(_ key: Key, value: Any, at: Date = Date()) {
        lock.lock(); defer { lock.unlock() }
        fetchedAt[key.description] = at
        memory[key.description] = value
    }

    static func cachedValue<T>(_ key: Key) -> T? {
        lock.lock(); defer { lock.unlock() }
        return memory[key.description] as? T
    }

    static func invalidate(_ keys: Key...) {
        lock.lock(); defer { lock.unlock() }
        for key in keys {
            let k = key.description
            fetchedAt.removeValue(forKey: k)
            memory.removeValue(forKey: k)
            // Drop coalesce handle so the next fetch starts a post-mutation GET.
            // The old Task may still finish; `epoch` prevents it from writing cache.
            inFlight.removeValue(forKey: k)
            epoch[k, default: 0] &+= 1
        }
    }

    static func invalidateNotesSubtree(noteId: String? = nil) {
        invalidate(.notes, .granted)
        if let noteId { invalidate(.note(noteId)) }
        // Drop every per-note entry when noteId omitted (bulk).
        if noteId == nil {
            let noteKeys = fetchedAt.keys.filter { $0.hasPrefix("note:") }
            for k in noteKeys {
                fetchedAt.removeValue(forKey: k)
                memory.removeValue(forKey: k)
            }
        }
    }

    static func clearAccountScoped() {
        lock.lock(); defer { lock.unlock() }
        let keys = fetchedAt.keys.filter { key in
            !(key.hasPrefix("bibleBooks:")
                || key == Key.authProviders.description
                || key == Key.themesCatalog.description
                || key == Key.readingCatalog.description)
        }
        for k in keys {
            fetchedAt.removeValue(forKey: k)
            memory.removeValue(forKey: k)
        }
        activityLastForceAt = nil
        activityLastSuccessAt = nil
        clearAccountDiskCaches()
        // Disk mirrors + outbox are account-owned (explore gap from SWR work).
        LocalNoteCache.clearAll()
        LocalGroupNotesCache.clearAll()
        NativeOutbox.clearAll()
    }

    static func resetAllForTests() {
        lock.lock(); defer { lock.unlock() }
        fetchedAt.removeAll()
        memory.removeAll()
        inFlight.removeAll()
        epoch.removeAll()
        activityLastForceAt = nil
        activityLastSuccessAt = nil
        networkHits = []
        networkProbeEnabled = false
        clearAccountDiskCaches()
        clearPublicDiskCaches()
        // Avoid leaking session mirrors / outbox / notes across XCTest cases.
        LocalNoteCache.clearAll()
        LocalGroupNotesCache.clearAll()
        NativeOutbox.clearAll()
        LocalSessionCache.clearMe()
        LocalSessionCache.clearGroups()
    }

    // MARK: - Activity debounce

    static func shouldSkipActivitySync(force: Bool, now: Date = Date()) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if force { return false }
        guard let last = activityLastSuccessAt else { return false }
        return now.timeIntervalSince(last) < TTL.activitySync
    }

    static func markActivitySyncSuccess(at: Date = Date()) {
        lock.lock(); defer { lock.unlock() }
        activityLastSuccessAt = at
    }

    // MARK: - Fetch with coalesce + TTL

    /// Return memory/disk if fresh (unless `force`); otherwise run `network` once and share among waiters.
    /// Callers that want instant paint should read disk themselves, then `await` this for the authoritative value.
    static func fetch<T>(
        key: Key,
        ttl: TimeInterval,
        force: Bool,
        loadDisk: (() -> T?)? = nil,
        saveDisk: ((T) -> Void)? = nil,
        network: @escaping () async throws -> T
    ) async throws -> T {
        if !force, isFresh(key, ttl: ttl), let mem: T = cachedValue(key) {
            return mem
        }
        if !force, isFresh(key, ttl: ttl), let disk = loadDisk?() {
            markFetched(key, value: disk)
            return disk
        }

        // Coalesce in-flight network work across concurrent screen transitions.
        let task: Task<T, Error> = {
            lock.lock()
            if let existing = inFlight[key.description] as? Task<T, Error> {
                lock.unlock()
                return existing
            }
            let startEpoch = epoch[key.description, default: 0]
            let created = Task<T, Error> {
                do {
                    let value = try await network()
                    lock.lock()
                    let stale = epoch[key.description, default: 0] != startEpoch
                    inFlight.removeValue(forKey: key.description)
                    if !stale {
                        fetchedAt[key.description] = Date()
                        memory[key.description] = value
                    }
                    lock.unlock()
                    if !stale {
                        saveDisk?(value)
                        return value
                    }
                    // Mutation won the race — keep post-mutation memory/disk.
                    if let mem: T = cachedValue(key) { return mem }
                    if let disk = loadDisk?() { return disk }
                    return value
                } catch {
                    lock.lock(); inFlight.removeValue(forKey: key.description); lock.unlock()
                    // Offline: prefer memory / disk over failing the screen.
                    if let mem: T = cachedValue(key) { return mem }
                    if let disk = loadDisk?() { return disk }
                    throw error
                }
            }
            inFlight[key.description] = created
            lock.unlock()
            return created
        }()

        return try await task.value
    }

    // MARK: - Disk helpers (granted / prefs / bible / providers)

    private static var swrDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("NativeSWR", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func clearAccountDiskCaches() {
        let names = ["granted-v1.json", "prefs-v1.json"]
        for name in names {
            try? FileManager.default.removeItem(at: swrDirectory.appendingPathComponent(name))
        }
    }

    private static func clearPublicDiskCaches() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: swrDirectory, includingPropertiesForKeys: nil) else { return }
        for url in files where url.lastPathComponent.hasPrefix("bible-")
            || url.lastPathComponent.hasPrefix("auth-providers")
            || url.lastPathComponent.hasPrefix("themes-")
            || url.lastPathComponent.hasPrefix("reading-")
        {
            try? fm.removeItem(at: url)
        }
        UserDefaults.standard.removeObject(forKey: "katecheo.catalog.themesVersion")
        UserDefaults.standard.removeObject(forKey: "katecheo.catalog.readingVersion")
    }

    static func saveGranted(_ notes: [NativeAPIClient.NoteDocument]) {
        guard let data = try? JSONEncoder().encode(notes) else { return }
        try? data.write(to: swrDirectory.appendingPathComponent("granted-v1.json"), options: .atomic)
    }

    static func loadGranted() -> [NativeAPIClient.NoteDocument]? {
        guard let data = try? Data(contentsOf: swrDirectory.appendingPathComponent("granted-v1.json")),
              let notes = try? JSONDecoder().decode([NativeAPIClient.NoteDocument].self, from: data)
        else { return nil }
        return notes
    }

    static func savePrefs(_ prefs: NativeAPIClient.PrefsDTO) {
        guard let data = try? JSONEncoder().encode(prefs) else { return }
        try? data.write(to: swrDirectory.appendingPathComponent("prefs-v1.json"), options: .atomic)
    }

    static func loadPrefs() -> NativeAPIClient.PrefsDTO? {
        guard let data = try? Data(contentsOf: swrDirectory.appendingPathComponent("prefs-v1.json")),
              let prefs = try? JSONDecoder().decode(NativeAPIClient.PrefsDTO.self, from: data)
        else { return nil }
        return prefs
    }

    static func saveBibleBooks(_ books: [NativeAPIClient.BibleBookDTO], locale: String) {
        guard let data = try? JSONEncoder().encode(books) else { return }
        try? data.write(to: swrDirectory.appendingPathComponent("bible-\(locale)-v1.json"), options: .atomic)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "katecheo.swr.bibleFetched.\(locale)")
        UserDefaults.standard.set(bibleBooksBundleVersion, forKey: "katecheo.swr.bibleVersion.\(locale)")
    }

    static func loadBibleBooks(locale: String) -> [NativeAPIClient.BibleBookDTO]? {
        let storedVersion = UserDefaults.standard.integer(forKey: "katecheo.swr.bibleVersion.\(locale)")
        guard storedVersion == bibleBooksBundleVersion else { return nil }
        guard let data = try? Data(contentsOf: swrDirectory.appendingPathComponent("bible-\(locale)-v1.json")),
              let books = try? JSONDecoder().decode([NativeAPIClient.BibleBookDTO].self, from: data),
              !books.isEmpty
        else { return nil }
        return books
    }

    static func bibleFetchedAt(locale: String) -> Date? {
        let raw = UserDefaults.standard.double(forKey: "katecheo.swr.bibleFetched.\(locale)")
        guard raw > 0 else { return nil }
        return Date(timeIntervalSince1970: raw)
    }

    /// Localized book rows from the shipped `BibleBooksData.json` (offline from first launch).
    static func loadBundledBibleBooks(locale: String) -> [NativeAPIClient.BibleBookDTO]? {
        guard let url = Bundle.main.url(forResource: "BibleBooksData", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let root = try? JSONDecoder().decode(BundledBibleRoot.self, from: data),
              root.version == bibleBooksBundleVersion
        else { return nil }
        let loc: String = {
            let lower = locale.lowercased()
            if lower.hasPrefix("en") { return "en" }
            if lower.hasPrefix("es") { return "es" }
            return "pt"
        }()
        return root.books.map { book in
            NativeAPIClient.BibleBookDTO(
                id: book.id,
                testament: book.testament,
                name: book.names[loc] ?? book.names["en"] ?? book.id,
                abbr: book.abbr[loc] ?? book.abbr["en"] ?? book.id,
                chapters: book.chapters,
                verses: book.verses
            )
        }
    }

    private struct BundledBibleRoot: Decodable {
        var version: Int
        var books: [BundledBibleBook]
    }

    private struct BundledBibleBook: Decodable {
        var id: String
        var testament: String
        var names: [String: String]
        var abbr: [String: String]
        var chapters: Int
        var verses: [Int]
    }

    // MARK: Themes / Reading catalog disk

    static func saveThemesPayload(_ data: Data) {
        try? data.write(to: swrDirectory.appendingPathComponent("themes-index-v1.json"), options: .atomic)
    }

    static func loadThemesPayload() -> Data? {
        try? Data(contentsOf: swrDirectory.appendingPathComponent("themes-index-v1.json"))
    }

    static func saveReadingPayload(_ data: Data) {
        try? data.write(to: swrDirectory.appendingPathComponent("reading-index-v1.json"), options: .atomic)
    }

    static func loadReadingPayload() -> Data? {
        try? Data(contentsOf: swrDirectory.appendingPathComponent("reading-index-v1.json"))
    }

    static var storedThemesVersion: String? {
        get { UserDefaults.standard.string(forKey: "katecheo.catalog.themesVersion") }
        set { UserDefaults.standard.set(newValue, forKey: "katecheo.catalog.themesVersion") }
    }

    static var storedReadingVersion: String? {
        get { UserDefaults.standard.string(forKey: "katecheo.catalog.readingVersion") }
        set { UserDefaults.standard.set(newValue, forKey: "katecheo.catalog.readingVersion") }
    }

    static func invalidateThemesCatalog() {
        invalidate(.themesCatalog)
        try? FileManager.default.removeItem(at: swrDirectory.appendingPathComponent("themes-index-v1.json"))
        // Keep storedThemesVersion — silent push clears payload; version check owns the etag.
    }

    static func invalidateReadingCatalog() {
        invalidate(.readingCatalog)
        try? FileManager.default.removeItem(at: swrDirectory.appendingPathComponent("reading-index-v1.json"))
    }

    static func saveAuthProvidersJSON(_ data: Data) {
        try? data.write(to: swrDirectory.appendingPathComponent("auth-providers-v1.json"), options: .atomic)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "katecheo.swr.authProvidersFetched")
    }

    static func loadAuthProvidersJSON() -> Data? {
        try? Data(contentsOf: swrDirectory.appendingPathComponent("auth-providers-v1.json"))
    }

    static func authProvidersFetchedAt() -> Date? {
        let raw = UserDefaults.standard.double(forKey: "katecheo.swr.authProvidersFetched")
        guard raw > 0 else { return nil }
        return Date(timeIntervalSince1970: raw)
    }
}
