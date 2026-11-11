import XCTest
@testable import Katecheo

/// Counts native GETs along the same call paths Caderno / Perfil / Versos / foreground use.
final class NativeSWRCacheTests: XCTestCase {
    override func setUp() {
        super.setUp()
        NativeSWR.resetAllForTests()
        NativeSWR.networkProbeEnabled = true
        MockNativeURLProtocol.reset()
        MockNativeURLProtocol.register()
        NativeAPIClient.session = MockNativeURLProtocol.makeSession()
        NativeAPIClient.testAuthToken = "test-bearer-swr"
        XCTAssertTrue(NativeAPIClient.hasBearer, "test auth token must be set")
    }

    override func tearDown() {
        NativeAPIClient.testAuthToken = nil
        NativeSWR.resetAllForTests()
        NativeAPIClient.session = .shared
        MockNativeURLProtocol.unregister()
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

        let notes = try await NativeAPIClient.listNotes()
        XCTAssertFalse(notes.isEmpty)
        _ = try await NativeAPIClient.listSpeakers()
        _ = try await NativeAPIClient.listGrantedNotes()
        XCTAssertEqual(countExact("/api/native/v1/notes"), 1)
        XCTAssertEqual(countExact("/api/native/v1/speakers"), 1)
        XCTAssertEqual(countExact("/api/native/v1/notes/granted"), 1)

        NativeSWR.resetProbe()

        _ = try await NativeAPIClient.listNotes()
        _ = try await NativeAPIClient.listSpeakers()
        _ = try await NativeAPIClient.listGrantedNotes()
        XCTAssertEqual(countExact("/api/native/v1/notes"), 0)
        XCTAssertEqual(countExact("/api/native/v1/speakers"), 0)
        XCTAssertEqual(countExact("/api/native/v1/notes/granted"), 0)

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
        XCTAssertEqual(countExact("/api/native/v1/me"), 0)
        _ = try await NativeAPIClient.getMe(force: true)
        XCTAssertEqual(countExact("/api/native/v1/me"), 1)
    }

    func testPrefs_sharedAcrossVersesAndReading() async throws {
        MockNativeURLProtocol.prefsJSON = Self.prefsPayload
        _ = try await NativeAPIClient.getPrefs()
        NativeSWR.resetProbe()
        _ = try await NativeAPIClient.getPrefs()
        _ = try await NativeAPIClient.getPrefs()
        _ = try await NativeAPIClient.getPrefs()
        XCTAssertEqual(countExact("/api/native/v1/prefs"), 0)
    }

    // MARK: - Bible books (permanent — no daily refetch)

    func testBibleBooks_permanentCache_noDailyRefetch() async throws {
        MockNativeURLProtocol.bibleBooksJSON = Self.biblePayload
        let first = try await NativeAPIClient.fetchBibleBooks(locale: "pt")
        XCTAssertFalse(first.isEmpty)
        // Bundled JSON or one recovery GET — never more than one network hit for cold start.
        XCTAssertLessThanOrEqual(NativeSWR.probeCount(containing: "/bible/books"), 1)
        NativeSWR.resetProbe()
        _ = try await NativeAPIClient.fetchBibleBooks(locale: "pt")
        XCTAssertEqual(NativeSWR.probeCount(containing: "/bible/books"), 0, "second call must use disk/memory")
        _ = try await NativeAPIClient.fetchBibleBooks(locale: "pt", force: true)
        XCTAssertEqual(
            NativeSWR.probeCount(containing: "/bible/books"),
            0,
            "force re-reads disk/bundle; no periodic network revalidation"
        )
    }

    func testThemesCatalog_diskCache_skipsNetworkUntilForce() async throws {
        MockNativeURLProtocol.themesJSON = Self.themesPayload
        _ = try await NativeAPIClient.fetchThemes(force: true)
        XCTAssertEqual(NativeSWR.probeCount(containing: "/bible/themes"), 1)
        NativeSWR.resetProbe()
        _ = try await NativeAPIClient.fetchThemes(force: false)
        XCTAssertEqual(NativeSWR.probeCount(containing: "/bible/themes"), 0)
        NativeSWR.invalidateThemesCatalog()
        NativeSWR.resetProbe()
        _ = try await NativeAPIClient.fetchThemes(force: false)
        XCTAssertEqual(NativeSWR.probeCount(containing: "/bible/themes"), 1)
    }

    func testReadingCatalog_diskCache_skipsNetworkUntilForce() async throws {
        MockNativeURLProtocol.plansJSON = Self.plansPayload
        _ = try await NativeAPIClient.fetchReadingPlans(force: true)
        XCTAssertEqual(NativeSWR.probeCount(containing: "/api/native/v1/plans"), 1)
        NativeSWR.resetProbe()
        _ = try await NativeAPIClient.fetchReadingPlans(force: false)
        XCTAssertEqual(NativeSWR.probeCount(containing: "/api/native/v1/plans"), 0)
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
        MockNativeURLProtocol.linksJSON = Self.linksPayload
        MockNativeURLProtocol.grantedJSON = Self.grantedPayload
        MockNativeURLProtocol.summaryJSON = Self.summaryPayload

        let first = await KCActivitySync.refreshFromServer(force: true)
        XCTAssertEqual(first, .updated)
        let second = await KCActivitySync.refreshFromServer(force: false)
        XCTAssertEqual(second, .skippedFresh)
        let forced = await KCActivitySync.refreshFromServer(force: true)
        XCTAssertEqual(forced, .updated)
    }

    func testActivitySync_coalescesConcurrent() async {
        MockNativeURLProtocol.linksJSON = Self.linksPayload
        MockNativeURLProtocol.grantedJSON = Self.grantedPayload
        MockNativeURLProtocol.summaryJSON = Self.summaryPayload
        MockNativeURLProtocol.artificialDelayMs = 80

        NativeSWR.resetProbe()
        async let a = KCActivitySync.refreshFromServer(force: true)
        async let b = KCActivitySync.refreshFromServer(force: true)
        let results = await (a, b)
        XCTAssertEqual(results.0, .updated)
        XCTAssertEqual(results.1, .updated)
        XCTAssertEqual(countExact("/api/native/v1/links"), 1)
        XCTAssertEqual(countExact("/api/native/v1/notes/granted"), 1)
        XCTAssertEqual(NativeSWR.probeCount(containing: "/notifications/summary"), 1)
        MockNativeURLProtocol.artificialDelayMs = 0
    }

    func testAccountSwitch_clearsCaches() async throws {
        MockNativeURLProtocol.notesJSON = Self.notesPayload
        MockNativeURLProtocol.speakersJSON = Self.speakersPayload
        let notes = try await NativeAPIClient.listNotes()
        let speakers = try await NativeAPIClient.listSpeakers()
        XCTAssertFalse(notes.isEmpty)
        XCTAssertFalse(speakers.isEmpty)
        XCTAssertFalse(LocalNoteCache.loadNotes().isEmpty)
        XCTAssertFalse(LocalNoteCache.loadSpeakers().isEmpty)

        NativeSWR.clearAccountScoped()
        XCTAssertTrue(LocalNoteCache.loadNotes().isEmpty, "account switch must clear Caderno disk")
        XCTAssertTrue(LocalNoteCache.loadSpeakers().isEmpty)
        XCTAssertEqual(NativeOutbox.pendingCount, 0)

        NativeSWR.resetProbe()
        NativeAPIClient.testAuthToken = "test-bearer-swr"
        _ = try await NativeAPIClient.listNotes()
        XCTAssertEqual(countExact("/api/native/v1/notes"), 1)
    }

    // MARK: - Auth providers long cache

    func testAuthProviders_longCache() async {
        MockNativeURLProtocol.providersJSON = Self.providersPayload
        _ = await NativeLoginService.shared.fetchProviders()
        let firstHits = NativeSWR.probeCount(containing: "auth/providers")
        XCTAssertGreaterThanOrEqual(firstHits, 1)
        NativeSWR.resetProbe()
        _ = await NativeLoginService.shared.fetchProviders()
        XCTAssertEqual(NativeSWR.probeCount(containing: "/api/native/v1/auth/providers"), 0)
    }

    // MARK: - Screen transition tallies (documented before/after)

    func testScreenTransition_notebook_callCounts() async throws {
        MockNativeURLProtocol.notesJSON = Self.notesPayload
        MockNativeURLProtocol.speakersJSON = Self.speakersPayload
        MockNativeURLProtocol.grantedJSON = Self.grantedPayload

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

        _ = try await NativeAPIClient.getMe(force: true)
        NativeSWR.resetProbe()
        _ = try await NativeAPIClient.getMe(force: false)
        XCTAssertEqual(countExact("/api/native/v1/me"), 0, "AFTER Profile re-appear: 0 (was 1)")

        _ = try await NativeAPIClient.fetchBibleBooks(locale: "pt", force: false)
        _ = try await NativeAPIClient.getPrefs(force: true)
        NativeSWR.resetProbe()
        _ = try await NativeAPIClient.fetchBibleBooks(locale: "pt", force: false)
        _ = try await NativeAPIClient.getPrefs(force: false)
        XCTAssertEqual(NativeSWR.probeCount(containing: "/bible/books"), 0, "AFTER Verses re-appear: 0 bible")
        XCTAssertEqual(countExact("/api/native/v1/prefs"), 0, "AFTER Verses re-appear: 0 prefs (was 1)")
    }

    // MARK: - Fixtures

    // Use ##"…"## so hex colors like #111111 don't terminate Swift raw strings.
    private static let notesPayload = ##"{"ok":true,"notes":[{"schemaVersion":1,"id":"n1","title":"A","happenedAt":"2026-01-01","tags":[],"visibility":"private","updatedAt":"2026-01-01T00:00:00Z","body":{"blocks":[]}}]}"##
    private static let speakersPayload = ##"{"ok":true,"speakers":[{"id":"s1","name":"Ana","color":"#111111","updatedAt":"2026-01-01T00:00:00Z"}]}"##
    private static let grantedPayload = ##"{"ok":true,"notes":[]}"##
    private static let singleNotePayload = ##"{"ok":true,"note":{"schemaVersion":1,"id":"n1","title":"A","happenedAt":"2026-01-01","tags":[],"visibility":"private","updatedAt":"2026-01-01T00:00:00Z","body":{"blocks":[]}},"speakers":[],"via":"owned"}"##
    private static let mePayload = ##"{"ok":true,"me":{"id":"u1","email":"a@b.c","displayName":"A","prefs":{"locale":"pt","copyLocale":"pt","appId":"youversion","translationId":"NVI","preferNative":false,"copyFormat":"text","citeBook":"name","citeSep":"colon","booksCompact":false,"theme":"system","avatarId":"","avatarUrl":"","handle":"ana","firstName":"Ana","lastName":"","profileEmail":"a@b.c"},"notify":{"reading":true,"friends":true,"shares":true,"groups":true}}}"##
    private static let prefsPayload = ##"{"ok":true,"prefs":{"locale":"pt","copyLocale":"pt","appId":"youversion","translationId":"NVI","preferNative":false,"copyFormat":"text","citeBook":"name","citeSep":"colon","booksCompact":false,"theme":"system","avatarId":"","avatarUrl":"","handle":"ana","firstName":"Ana","lastName":"","profileEmail":"a@b.c"}}"##
    private static let biblePayload = ##"{"ok":true,"locale":"pt","books":[{"id":"GEN","testament":"ot","name":"Genesis","abbr":"Gn","chapters":1,"verses":[31]}]}"##
    private static let themesPayload = ##"{"ok":true,"kind":"index","themeTotal":1,"categories":[],"themes":[{"id":"faith","name":"Faith","count":1}]}"##
    private static let plansPayload = ##"{"ok":true,"kind":"index","planTotal":1,"categories":[],"plans":[{"id":"gospels-30","name":"Gospels","days":30}]}"##
    private static let linksPayload = ##"{"ok":true,"friends":[],"incoming":[],"outgoing":[]}"##
    private static let summaryPayload = ##"{"ok":true,"items":[],"unread":0,"byKind":{}}"##
    private static let providersPayload = ##"{"ok":true,"google":true,"apple":true,"email":true}"##
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
    static var themesJSON: String?
    static var plansJSON: String?
    static var catalogVersionsJSON: String?
    static var linksJSON: String?
    static var summaryJSON: String?
    static var notificationsJSON: String?
    static var notificationsPage2JSON: String?
    static var notificationsReadJSON: String?
    static var notificationsDeleteJSON: String?
    static var notificationsClearJSON: String?
    static var providersJSON: String?
    static var groupNotesJSON: String?
    static var groupNotesETag: String?
    static var groupNotesStatus: Int?
    static var groupJSON: String?
    static var artificialDelayMs: UInt64 = 0
    private(set) static var readBodies: [[String: Any]] = []
    private(set) static var deletedNotificationIds: [String] = []
    private(set) static var clearNotificationsHits = 0
    private(set) static var notificationsListHits = 0
    private(set) static var groupNotesHits = 0
    private(set) static var lastIfNoneMatch: String?
    private(set) static var lastUpdatedSince: String?
    private static var registered = false

    static func register() {
        if !registered {
            URLProtocol.registerClass(MockNativeURLProtocol.self)
            registered = true
        }
    }

    static func unregister() {
        if registered {
            URLProtocol.unregisterClass(MockNativeURLProtocol.self)
            registered = false
        }
    }

    static func reset() {
        notesJSON = nil
        speakersJSON = nil
        grantedJSON = nil
        upsertNoteJSON = nil
        noteByIdJSON = nil
        meJSON = nil
        prefsJSON = nil
        bibleBooksJSON = nil
        themesJSON = nil
        plansJSON = nil
        catalogVersionsJSON = nil
        linksJSON = nil
        summaryJSON = nil
        notificationsJSON = nil
        notificationsPage2JSON = nil
        notificationsReadJSON = nil
        notificationsDeleteJSON = nil
        notificationsClearJSON = nil
        providersJSON = nil
        groupNotesJSON = nil
        groupNotesETag = nil
        groupNotesStatus = nil
        groupJSON = nil
        artificialDelayMs = 0
        readBodies = []
        deletedNotificationIds = []
        clearNotificationsHits = 0
        notificationsListHits = 0
        groupNotesHits = 0
        lastIfNoneMatch = nil
        lastUpdatedSince = nil
    }

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockNativeURLProtocol.self]
        config.timeoutIntervalForRequest = 5
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
        } else if path.contains("/bible/themes") {
            body = Self.themesJSON
        } else if path.contains("/catalog/versions") {
            body = Self.catalogVersionsJSON
        } else if path.hasSuffix("/plans") || path.contains("/plans?") {
            body = Self.plansJSON
        } else if path.hasSuffix("/links") {
            body = Self.linksJSON
        } else if path.contains("/notifications/summary") {
            body = Self.summaryJSON
        } else if path.contains("/notifications/read"), method == "POST" {
            body = Self.notificationsReadJSON ?? ##"{"ok":true}"##
            let payload = Self.requestBodyData(from: request)
            if let payload,
               let obj = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] {
                Self.readBodies.append(obj)
            } else {
                Self.readBodies.append([:])
            }
        } else if path.contains("/notifications/clear"), method == "POST" || method == "DELETE" {
            Self.clearNotificationsHits += 1
            // nil fixture → 404 so optimistic UI can test rollback.
            body = Self.notificationsClearJSON
        } else if method == "DELETE",
                  path.range(of: #"/notifications/[^/]+$"#, options: .regularExpression) != nil,
                  !path.contains("/notifications/clear"),
                  !path.contains("/notifications/read"),
                  !path.contains("/notifications/summary") {
            let id = path.split(separator: "/").last.map(String.init) ?? ""
            Self.deletedNotificationIds.append(id)
            // nil fixture → 404 so optimistic UI can test rollback.
            body = Self.notificationsDeleteJSON
        } else if path.hasSuffix("/notifications") || path.contains("/notifications?") {
            Self.notificationsListHits += 1
            let cursor = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "cursor" })?
                .value
            if let cursor, !cursor.isEmpty {
                body = Self.notificationsPage2JSON ?? Self.notificationsJSON
            } else {
                body = Self.notificationsJSON
            }
        } else if path.contains("/auth/providers") {
            body = Self.providersJSON
        } else if path.range(of: #"/groups/[^/]+/notes$"#, options: .regularExpression) != nil, method == "GET" {
            Self.groupNotesHits += 1
            Self.lastIfNoneMatch = request.value(forHTTPHeaderField: "If-None-Match")
            Self.lastUpdatedSince = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "updatedSince" })?
                .value
            body = Self.groupNotesJSON
        } else if path.range(of: #"/groups/[^/]+$"#, options: .regularExpression) != nil, method == "GET" {
            body = Self.groupJSON
        }

        // Missing fixture → 404 (don't hit the real network / don't look like success).
        var status = body == nil ? 404 : 200
        if path.range(of: #"/groups/[^/]+/notes$"#, options: .regularExpression) != nil,
           method == "GET",
           let override = Self.groupNotesStatus
        {
            status = override
        }
        let data: Data
        if status == 304 {
            data = Data()
        } else {
            data = (body ?? ##"{"ok":false,"error":"mock_miss"}"##).data(using: .utf8)!
        }
        var headers: [String: String] = ["Content-Type": "application/json"]
        if let etag = Self.groupNotesETag,
           path.range(of: #"/groups/[^/]+/notes$"#, options: .regularExpression) != nil
        {
            headers["ETag"] = etag
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: nil,
            headerFields: headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)

        let finish = {
            self.client?.urlProtocol(self, didLoad: data)
            self.client?.urlProtocolDidFinishLoading(self)
        }
        if Self.artificialDelayMs > 0 {
            let ms = Self.artificialDelayMs
            DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(Int(ms)), execute: finish)
        } else {
            finish()
        }
    }

    override func stopLoading() {}

    /// URLSession often exposes POST bodies via `httpBodyStream` instead of `httpBody`.
    private static func requestBodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data.isEmpty ? nil : data
    }
}
