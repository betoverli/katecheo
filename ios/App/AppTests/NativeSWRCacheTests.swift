import XCTest
@testable import App

/// Counts native GETs along the same call paths Caderno / Perfil / Versos / foreground use.
final class NativeSWRCacheTests: XCTestCase {
    override func setUp() {
        super.setUp()
        NativeSWR.resetAllForTests()
        NativeSWR.networkProbeEnabled = true
        NativeAPIClient.session = MockNativeURLProtocol.makeSession()
        MockNativeURLProtocol.reset()
        _ = KeychainStore.setBearerToken("test-bearer-swr")
    }

    override func tearDown() {
        NativeSWR.resetAllForTests()
        NativeAPIClient.session = .shared
        _ = KeychainStore.deleteBearerToken()
        super.tearDown()
    }

    private func countExact(_ suffix: String) -> Int {
        NativeSWR.probeHits().filter { $0 == suffix || $0.hasSuffix(suffix) }.count
    }

    // MARK: - Caderno appear (listNotes + speakers + granted)

    func testNotebookAppear_secondPass_skipsNetworkWithinTTL() async throws {
        MockNativeURLProtocol.notesJSON = Self.notesPayload
        MockNativeURLProtocol.speakersJSON = Self.speakersPayload
        MockNativeURLProtocol.grantedJSON = Self.grantedPayload

        // First appear — 3 list GETs
        _ = try await NativeAPIClient.listNotes()
        _ = try await NativeAPIClient.listSpeakers()
        _ = try await NativeAPIClient.listGrantedNotes()
        XCTAssertEqual(countExact("/api/native/v1/notes"), 1)
        XCTAssertEqual(countExact("/api/native/v1/speakers"), 1)
        XCTAssertEqual(countExact("/api/native/v1/notes/granted"), 1)

        NativeSWR.resetProbe()

        // Second appear within TTL — 0 network
        _ = try await NativeAPIClient.listNotes()
        _ = try await NativeAPIClient.listSpeakers()
        _ = try await NativeAPIClient.listGrantedNotes()
        XCTAssertEqual(countExact("/api/native/v1/notes"), 0)
        XCTAssertEqual(countExact("/api/native/v1/speakers"), 0)
        XCTAssertEqual(countExact("/api/native/v1/notes/granted"), 0)

        // Pull-to-refresh forces network again
        _ = try await NativeAPIClient.listNotes(force: true)
        XCTAssertEqual(countExact("/api/native/v1/notes"), 1)
    }

    func testNotebookMutation_invalidatesNotesCache() async throws {
        MockNativeURLProtocol.notesJSON = Self.notesPayload
        MockNativeURLProtocol.upsertNoteJSON = Self.singleNotePayload
        _ = try await NativeAPIClient.listNotes()
        NativeSWR.resetProbe()
        _ = try await NativeAPIClient.listNotes()
        XCTAssertEqual(countExact("/api/native/v1/notes"), 0)

        var note = NativeAPIClient.emptyNote(id: "n1")
        note.title = "edited"
        _ = try await NativeAPIClient.upsertNote(note)
        NativeSWR.resetProbe()
        _ = try await NativeAPIClient.listNotes()
        XCTAssertEqual(countExact("/api/native/v1/notes"), 1, "own edit must refetch list")
    }

    // MARK: - Profile / prefs

    func testProfileAppear_secondPass_skipsMe() async throws {
        MockNativeURLProtocol.meJSON = Self.mePayload
        _ = try await NativeAPIClient.getMe()
        NativeSWR.resetProbe()
        _ = try await NativeAPIClient.getMe()
        XCTAssertEqual(NativeSWR.probeCount(containing: "/me"), 0)
        _ = try await NativeAPIClient.getMe(force: true)
        XCTAssertEqual(NativeSWR.probeCount(containing: "/me"), 1)
    }

    func testPrefs_sharedAcrossVersesAndReading() async throws {
        MockNativeURLProtocol.prefsJSON = Self.prefsPayload
        _ = try await NativeAPIClient.getPrefs()
        NativeSWR.resetProbe()
        // Verses tab + Reading + NoteDetail-style prefs hits
        _ = try await NativeAPIClient.getPrefs()
        _ = try await NativeAPIClient.getPrefs()
        _ = try await NativeAPIClient.getPrefs()
        XCTAssertEqual(NativeSWR.probeCount(containing: "/prefs"), 0)
    }

    // MARK: - Bible books (≤1/day)

    func testBibleBooks_cachedForDay() async throws {
        MockNativeURLProtocol.bibleBooksJSON = Self.biblePayload
        _ = try await NativeAPIClient.fetchBibleBooks(locale: "pt")
        XCTAssertEqual(NativeSWR.probeCount(containing: "/bible/books"), 1)
        NativeSWR.resetProbe()
        _ = try await NativeAPIClient.fetchBibleBooks(locale: "pt")
        XCTAssertEqual(NativeSWR.probeCount(containing: "/bible/books"), 0)
        _ = try await NativeAPIClient.fetchBibleBooks(locale: "pt", force: true)
        XCTAssertEqual(NativeSWR.probeCount(containing: "/bible/books"), 1)
    }

    // MARK: - Single note short TTL

    func testGetNote_shortTTL_skipsRepeat() async throws {
        MockNativeURLProtocol.noteByIdJSON = Self.singleNotePayload
        _ = try await NativeAPIClient.getNote(id: "n1")
        NativeSWR.resetProbe()
        _ = try await NativeAPIClient.getNote(id: "n1")
        XCTAssertEqual(NativeSWR.probeCount(containing: "/notes/n1"), 0)
    }

    // MARK: - Activity debounce + coalesce

    func testActivitySync_debouncedUnlessForce() async {
        MockNativeURLProtocol.linksJSON = #"{"ok":true,"friends":[],"incoming":[],"outgoing":[]}"#
        MockNativeURLProtocol.grantedJSON = Self.grantedPayload
        MockNativeURLProtocol.summaryJSON = #"{"ok":true,"items":[],"unread":0,"byKind":{}}"#

        let first = await V2NActivitySync.refreshFromServer(force: true)
        XCTAssertEqual(first, .updated)
        let second = await V2NActivitySync.refreshFromServer(force: false)
        XCTAssertEqual(second, .skippedFresh)
        let forced = await V2NActivitySync.refreshFromServer(force: true)
        XCTAssertEqual(forced, .updated)
    }

    func testActivitySync_coalescesConcurrent() async {
        MockNativeURLProtocol.linksJSON = #"{"ok":true,"friends":[],"incoming":[],"outgoing":[]}"#
        MockNativeURLProtocol.grantedJSON = Self.grantedPayload
        MockNativeURLProtocol.summaryJSON = #"{"ok":true,"items":[],"unread":0,"byKind":{}}"#
        MockNativeURLProtocol.artificialDelayMs = 80

        NativeSWR.resetProbe()
        async let a = V2NActivitySync.refreshFromServer(force: true)
        async let b = V2NActivitySync.refreshFromServer(force: true)
        let results = await (a, b)
        XCTAssertEqual(results.0, .updated)
        XCTAssertEqual(results.1, .updated)
        // links+granted+summary once (not doubled)
        XCTAssertEqual(NativeSWR.probeCount(containing: "/links"), 1)
        XCTAssertEqual(NativeSWR.probeCount(containing: "/granted"), 1)
        XCTAssertEqual(NativeSWR.probeCount(containing: "/notifications/summary"), 1)
        MockNativeURLProtocol.artificialDelayMs = 0
    }

    func testAccountSwitch_clearsCaches() async throws {
        MockNativeURLProtocol.notesJSON = Self.notesPayload
        MockNativeURLProtocol.speakersJSON = Self.speakersPayload
        _ = try await NativeAPIClient.listNotes()
        _ = try await NativeAPIClient.listSpeakers()
        XCTAssertFalse(LocalNoteCache.loadNotes().isEmpty)
        XCTAssertFalse(LocalNoteCache.loadSpeakers().isEmpty)

        NativeSWR.clearAccountScoped()
        XCTAssertTrue(LocalNoteCache.loadNotes().isEmpty, "account switch must clear Caderno disk")
        XCTAssertTrue(LocalNoteCache.loadSpeakers().isEmpty)
        XCTAssertEqual(NativeOutbox.pendingCount, 0)

        NativeSWR.resetProbe()
        _ = try await NativeAPIClient.listNotes()
        XCTAssertEqual(countExact("/api/native/v1/notes"), 1)
    }

    // MARK: - Auth providers long cache

    func testAuthProviders_longCache() async {
        MockNativeURLProtocol.providersJSON = #"{"ok":true,"google":true,"apple":true,"email":true}"#
        _ = await NativeLoginService.shared.fetchProviders()
        let firstHits = NativeSWR.probeCount(containing: "auth/providers")
        XCTAssertGreaterThanOrEqual(firstHits, 1)
        NativeSWR.resetProbe()
        _ = await NativeLoginService.shared.fetchProviders()
        // Second call should not hit network path (records cache:… instead)
        XCTAssertEqual(NativeSWR.probeCount(containing: "/api/native/v1/auth/providers"), 0)
    }

    // MARK: - Screen transition tallies (documented before/after)

    /// Documents Caderno `viewWillAppear` → `reload` call shape before vs after SWR.
    func testScreenTransition_notebook_callCounts() async throws {
        MockNativeURLProtocol.notesJSON = Self.notesPayload
        MockNativeURLProtocol.speakersJSON = Self.speakersPayload
        MockNativeURLProtocol.grantedJSON = Self.grantedPayload
        MockNativeURLProtocol.linksJSON = #"{"ok":true,"friends":[],"incoming":[],"outgoing":[]}"#
        MockNativeURLProtocol.summaryJSON = #"{"ok":true,"items":[],"unread":0,"byKind":{}}"#

        // BEFORE (legacy): every appear hit notes+speakers+granted (+ activity).
        let beforePerAppear = 3

        NativeSWR.resetProbe()
        _ = try await NativeAPIClient.listNotes(force: true)
        _ = try await NativeAPIClient.listSpeakers(force: true)
        _ = try await NativeAPIClient.listGrantedNotes(force: true)
        let firstAppear = countExact("/api/native/v1/notes")
            + countExact("/api/native/v1/speakers")
            + countExact("/api/native/v1/notes/granted")
        XCTAssertEqual(firstAppear, beforePerAppear)

        NativeSWR.resetProbe()
        _ = try await NativeAPIClient.listNotes(force: false)
        _ = try await NativeAPIClient.listSpeakers(force: false)
        _ = try await NativeAPIClient.listGrantedNotes(force: false)
        let secondAppear = countExact("/api/native/v1/notes")
            + countExact("/api/native/v1/speakers")
            + countExact("/api/native/v1/notes/granted")
        XCTAssertEqual(secondAppear, 0, "AFTER: second Caderno appear within TTL → 0 list GETs (was \(beforePerAppear))")
    }

    func testScreenTransition_profileAndVerses_callCounts() async throws {
        MockNativeURLProtocol.meJSON = Self.mePayload
        MockNativeURLProtocol.prefsJSON = Self.prefsPayload
        MockNativeURLProtocol.bibleBooksJSON = Self.biblePayload

        // Profile appear ×2
        _ = try await NativeAPIClient.getMe(force: true)
        NativeSWR.resetProbe()
        _ = try await NativeAPIClient.getMe(force: false)
        XCTAssertEqual(NativeSWR.probeCount(containing: "/me"), 0, "AFTER Profile re-appear: 0 (was 1)")

        // Verses books+prefs ×2
        _ = try await NativeAPIClient.fetchBibleBooks(locale: "pt", force: true)
        _ = try await NativeAPIClient.getPrefs(force: true)
        NativeSWR.resetProbe()
        _ = try await NativeAPIClient.fetchBibleBooks(locale: "pt", force: false)
        _ = try await NativeAPIClient.getPrefs(force: false)
        XCTAssertEqual(NativeSWR.probeCount(containing: "/bible/books"), 0, "AFTER Verses re-appear: 0 bible (was 1)")
        XCTAssertEqual(NativeSWR.probeCount(containing: "/prefs"), 0, "AFTER Verses re-appear: 0 prefs (was 1)")
    }

    // MARK: - Fixtures

    private static let notesPayload = #"{"ok":true,"notes":[{"schemaVersion":1,"id":"n1","title":"A","happenedAt":"2026-01-01","tags":[],"visibility":"private","updatedAt":"2026-01-01T00:00:00Z","body":{"blocks":[]}}]}"#
    private static let speakersPayload = #"{"ok":true,"speakers":[{"id":"s1","name":"Ana","color":"#111","updatedAt":"2026-01-01T00:00:00Z"}]}"#
    private static let grantedPayload = #"{"ok":true,"notes":[]}"#
    private static let singleNotePayload = #"{"ok":true,"note":{"schemaVersion":1,"id":"n1","title":"A","happenedAt":"2026-01-01","tags":[],"visibility":"private","updatedAt":"2026-01-01T00:00:00Z","body":{"blocks":[]}},"speakers":[],"via":"owned"}"#
    private static let mePayload = #"{"ok":true,"me":{"id":"u1","email":"a@b.c","displayName":"A","prefs":{"locale":"pt","copyLocale":"pt","appId":"youversion","translationId":"NVI","preferNative":false,"copyFormat":"text","citeBook":"name","citeSep":"colon","booksCompact":false,"theme":"system","avatarId":"","avatarUrl":"","handle":"ana","firstName":"Ana","lastName":"","profileEmail":"a@b.c"},"notify":{"reading":true,"friends":true,"shares":true,"groups":true}}}"#
    private static let prefsPayload = #"{"ok":true,"prefs":{"locale":"pt","copyLocale":"pt","appId":"youversion","translationId":"NVI","preferNative":false,"copyFormat":"text","citeBook":"name","citeSep":"colon","booksCompact":false,"theme":"system","avatarId":"","avatarUrl":"","handle":"ana","firstName":"Ana","lastName":"","profileEmail":"a@b.c"}}"#
    private static let biblePayload = #"{"ok":true,"locale":"pt","books":[{"id":"GEN","testament":"ot","name":"Gênesis","abbr":"Gn","chapters":1,"verses":[31]}]}"#
}

// MARK: - URLProtocol mock

final class MockNativeURLProtocol: URLProtocol {
    static var notesJSON: String?
    static var speakersJSON: String?
    static var grantedJSON: String?
    static var upsertNoteJSON: String?
    static var noteByIdJSON: String?
    static var meJSON: String?
    static var prefsJSON: String?
    static var bibleBooksJSON: String?
    static var linksJSON: String?
    static var summaryJSON: String?
    static var providersJSON: String?
    static var artificialDelayMs: UInt64 = 0

    static func reset() {
        notesJSON = nil
        speakersJSON = nil
        grantedJSON = nil
        upsertNoteJSON = nil
        noteByIdJSON = nil
        meJSON = nil
        prefsJSON = nil
        bibleBooksJSON = nil
        linksJSON = nil
        summaryJSON = nil
        providersJSON = nil
        artificialDelayMs = 0
    }

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockNativeURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url?.path ?? ""
        let method = request.httpMethod ?? "GET"
        var body: String?
        if path.hasSuffix("/notes/granted") {
            body = Self.grantedJSON
        } else if path.range(of: #"/notes/[^/]+$"#, options: .regularExpression) != nil, method == "GET" {
            body = Self.noteByIdJSON
        } else if path.hasSuffix("/notes"), method == "GET" {
            body = Self.notesJSON
        } else if path.hasSuffix("/notes"), method == "POST" {
            body = Self.upsertNoteJSON ?? Self.noteByIdJSON
        } else if path.hasSuffix("/speakers") {
            body = Self.speakersJSON
        } else if path.hasSuffix("/me") {
            body = Self.meJSON
        } else if path.hasSuffix("/prefs") {
            body = Self.prefsJSON
        } else if path.contains("/bible/books") {
            body = Self.bibleBooksJSON
        } else if path.hasSuffix("/links") {
            body = Self.linksJSON
        } else if path.contains("/notifications/summary") {
            body = Self.summaryJSON
        } else if path.contains("/auth/providers") {
            body = Self.providersJSON
        }

        let data = (body ?? #"{"ok":true}"#).data(using: .utf8)!
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if Self.artificialDelayMs > 0 {
            let ms = Self.artificialDelayMs
            DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(Int(ms))) {
                self.client?.urlProtocol(self, didLoad: data)
                self.client?.urlProtocolDidFinishLoading(self)
            }
        } else {
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}
