import Foundation

/// URLSession client for `/api/native/v1` using the Keychain bearer.
/// Payloads are **NoteDocumentV1** (never HTML).
enum NativeAPIClient {
    /// Canonical Katecheo origin (katecheo.app).
    static var baseURL: URL { AppSite.baseURL }

    enum APIError: Error, LocalizedError {
        case unauthorized
        case http(Int, String)
        case decoding
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .unauthorized: return String(localized: "Sessão expirada. Entre novamente.")
            case .http(let code, let body): return "HTTP \(code): \(body)"
            case .decoding: return String(localized: "Resposta inválida.")
            case .invalidResponse: return String(localized: "Sem resposta.")
            }
        }
    }

    /// Replaceable for tests (URLProtocol / mock session).
    static var session: URLSession = .shared

    /// Test-only bearer so AppTests don't depend on the Keychain entitlement.
    /// Production code never sets this; `handleUnauthorized` clears it.
    static var testAuthToken: String?

    /// Clear Keychain bearer and notify UI to re-login. Idempotent.
    /// Only call for explicit 401 / invalid token — never for transport/network failures.
    static func handleUnauthorized() {
        testAuthToken = nil
        KeychainStore.deleteBearerToken()
        LocalSessionCache.clearAll()
        NativeSWR.clearAccountScoped()
        LocalSessionCache.showOfflineHint = false
        NotificationCenter.default.post(name: .nativeSessionDidExpire, object: nil)
        NotificationCenter.default.post(name: .nativeSessionDidChange, object: nil)
    }

    private static func throwIfUnauthorized(_ status: Int) throws {
        if status == 401 {
            handleUnauthorized()
            throw APIError.unauthorized
        }
    }

    // MARK: - NoteDocumentV1 (wire)

    struct TextSpan: Codable, Equatable {
        var type: String
        var text: String?
        var marks: [String]?
        var bookId: String?
        var chapter: Int?
        var verseStart: Int?
        var verseEnd: Int?
        var href: String?
    }

    struct LineBlock: Codable, Equatable {
        var id: String
        var type: String
        var spans: [TextSpan]?
        var speakerId: String?
        var title: String?
        var collapsed: Bool?
        var checked: Bool?
        var blocks: [LineBlock]?
    }

    struct NoteBody: Codable, Equatable {
        var blocks: [LineBlock]
    }

    struct NoteDocument: Codable, Equatable {
        var schemaVersion: Int
        var id: String
        var title: String
        var happenedAt: String
        var tags: [String]
        var noteSpeakerId: String?
        var visibility: String
        var updatedAt: String
        var body: NoteBody

        var preview: String {
            var parts: [String] = []
            for block in body.blocks {
                if block.type == "speakerSection" {
                    for child in block.blocks ?? [] {
                        parts.append(spanText(child.spans))
                    }
                } else {
                    parts.append(spanText(block.spans))
                }
                if parts.joined().count > 160 { break }
            }
            let text = parts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? String(localized: "Sem texto") : text
        }

        private func spanText(_ spans: [TextSpan]?) -> String {
            // Caderno preview: plain body text only — strip reference pills (TF210).
            (spans ?? []).compactMap { span in
                if span.type == "bibleRef" { return nil }
                let text = span.text ?? ""
                return text.isEmpty ? nil : text
            }.joined()
        }
    }

    struct SpeakerDTO: Codable, Equatable {
        var id: String
        var name: String
        var color: String
        var updatedAt: String
    }

    struct NotesResponse: Decodable {
        let ok: Bool?
        let notes: [NoteDocument]?
        let error: String?
    }

    struct NoteResponse: Decodable {
        let ok: Bool?
        let note: NoteDocument?
        let speakers: [SpeakerDTO]?
        /// `owned` | `grant` — grants are read-only and must not enter the owned LocalNoteCache.
        let via: String?
        let error: String?
    }

    struct LinkPersonDTO: Codable, Equatable {
        var userId: String
        var handle: String
        var firstName: String
        var lastName: String
        var avatarId: String
        var avatarUrl: String

        var displayName: String {
            let name = [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ")
            if !name.isEmpty { return name }
            if !handle.isEmpty { return "@\(handle)" }
            return String(localized: "Amigo")
        }
    }

    struct LinksResponse: Decodable {
        let ok: Bool?
        let friends: [LinkPersonDTO]?
        let incoming: [LinkPersonDTO]?
        let outgoing: [LinkPersonDTO]?
        let error: String?
    }

    struct InboxItemDTO: Codable, Equatable {
        var id: String
        var kind: String
        var title: String
        var body: String
        var href: String
        var read: Bool
        var createdAt: String
    }

    struct NotificationsResponse: Decodable {
        let ok: Bool?
        let items: [InboxItemDTO]?
        let nextCursor: String?
        let unread: Int?
        let byKind: [String: Int]?
        let error: String?
    }

    struct PeopleHitDTO: Codable, Equatable {
        var userId: String
        var handle: String
        var firstName: String
        var lastName: String
        var avatarId: String
        var avatarUrl: String
        var status: String

        var asPerson: LinkPersonDTO {
            LinkPersonDTO(
                userId: userId, handle: handle, firstName: firstName, lastName: lastName,
                avatarId: avatarId, avatarUrl: avatarUrl
            )
        }
    }

    struct PeopleSearchResponse: Decodable {
        let ok: Bool?
        let people: [PeopleHitDTO]?
        let error: String?
    }

    struct LinkActionResponse: Decodable {
        let ok: Bool?
        let error: String?
        let status: String?
    }

    struct SpeakersResponse: Decodable {
        let ok: Bool?
        let speakers: [SpeakerDTO]?
        let error: String?
    }

    struct SessionResponse: Decodable {
        let ok: Bool?
        let user: SessionUser?
        let error: String?
    }

    struct SessionUser: Decodable {
        let id: String
        let email: String?
    }

    struct GroupDTO: Codable, Equatable {
        var id: String
        var name: String
        var description: String
        var visibility: String
        var postPolicy: String
        var createdBy: String
        var memberCount: Int
        var myRole: String?
        var myStatus: String?
        var updatedAt: String
        var published: Bool?

        var isAdmin: Bool { myRole == "admin" && myStatus == "accepted" }
        var isAccepted: Bool { myStatus == "accepted" }
        var canPost: Bool {
            guard isAccepted else { return false }
            if postPolicy == "admins" { return isAdmin }
            return true
        }
    }

    struct GroupAuthorDTO: Codable, Equatable {
        var userId: String
        var handle: String
        var firstName: String
        var lastName: String

        var displayName: String {
            let full = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
            if !full.isEmpty { return full }
            if !handle.isEmpty { return "@\(handle)" }
            return String(localized: "Membro")
        }
    }

    struct GroupNoteCardDTO: Codable, Equatable {
        struct NoteMeta: Codable, Equatable {
            var id: String
            var title: String
            var happenedAt: String
            var updatedAt: String
        }

        var note: NoteMeta
        var author: GroupAuthorDTO
        var owned: Bool
        var document: NoteDocument?
    }

    struct GroupsResponse: Decodable {
        let ok: Bool?
        let groups: [GroupDTO]?
        let error: String?
    }

    struct GroupResponse: Decodable {
        let ok: Bool?
        let group: GroupDTO?
        let error: String?
    }

    struct GroupNotesResponse: Decodable {
        let ok: Bool?
        let notes: [GroupNoteCardDTO]?
        /// When true, `notes` is a delta since `updatedSince` — merge into cache.
        let incremental: Bool?
        let error: String?
    }

    struct GroupMemberDTO: Codable, Equatable {
        var userId: String
        var handle: String
        var firstName: String
        var lastName: String
        var avatarId: String
        var avatarUrl: String
        var role: String
        var status: String

        var displayName: String {
            let full = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
            if !full.isEmpty { return full }
            if !handle.isEmpty { return "@\(handle)" }
            return String(localized: "Membro")
        }

        var isAdmin: Bool { role == "admin" }
        var isPending: Bool { status == "pending" }
    }

    struct GroupMembersResponse: Decodable {
        let ok: Bool?
        let members: [GroupMemberDTO]?
        let error: String?
    }

    // MARK: - Profile / prefs (Phase 3)

    struct PrefsDTO: Codable, Equatable {
        var locale: String
        var copyLocale: String
        var appId: String
        var translationId: String
        var preferNative: Bool
        var copyFormat: String
        var citeBook: String
        var citeSep: String
        var booksCompact: Bool
        var theme: String
        var activePlans: [String]?
        var planProgress: [String: [Int]]?
        var avatarId: String
        var avatarUrl: String
        var handle: String
        var firstName: String
        var lastName: String
        var profileEmail: String

        var displayName: String {
            let full = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
            if !full.isEmpty { return full }
            if !handle.isEmpty { return "@\(handle)" }
            return profileEmail
        }
    }

    struct NotifyPrefsDTO: Codable, Equatable {
        var reading: Bool
        var friends: Bool
        var shares: Bool
        var groups: Bool
        var apnsDevices: Int?
    }

    struct MeDTO: Codable, Equatable {
        var id: String
        var email: String?
        var displayName: String
        var prefs: PrefsDTO
        var notify: NotifyPrefsDTO
    }

    struct MeResponse: Decodable {
        let ok: Bool?
        let me: MeDTO?
        let error: String?
    }

    struct PrefsResponse: Decodable {
        let ok: Bool?
        let prefs: PrefsDTO?
        let error: String?
    }

    struct NotifyPrefsResponse: Decodable {
        let ok: Bool?
        let notify: NotifyPrefsDTO?
        let error: String?
    }

    // MARK: - Requests

    private static func authorizedRequest(
        path: String,
        method: String,
        body: Data? = nil,
        query: [URLQueryItem] = []
    ) throws -> URLRequest {
        let token = (testAuthToken?.isEmpty == false ? testAuthToken : nil)
            ?? KeychainStore.bearerToken()
        guard let token, !token.isEmpty else {
            throw APIError.unauthorized
        }
        var url = baseURL
        for part in path.split(separator: "/") {
            url = url.appendingPathComponent(String(part))
        }
        if !query.isEmpty, var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            comps.queryItems = query
            if let withQuery = comps.url { url = withQuery }
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private static func perform(_ request: URLRequest) async throws -> (Int, Data) {
        let (status, data, _) = try await performDetailed(request)
        return (status, data)
    }

    private static func performDetailed(_ request: URLRequest) async throws -> (Int, Data, HTTPURLResponse?) {
        if let path = request.url?.path {
            NativeSWR.recordNetworkHit(path)
        }
        do {
            let (data, response) = try await session.data(for: request)
            let http = response as? HTTPURLResponse
            let status = http?.statusCode ?? 0
            return (status, data, http)
        } catch {
            // katecheo.app is the only API host — no legacy-domain retry.
            _ = AppSite.considerFallback(after: error, for: request.url)
            throw error
        }
    }

    static var hasBearer: Bool {
        if let testAuthToken, !testAuthToken.isEmpty { return true }
        return !(KeychainStore.bearerToken() ?? "").isEmpty
    }

    static func getSession() async throws -> SessionUser {
        let request = try authorizedRequest(path: "api/native/v1/session", method: "GET")
        let (status, data) = try await perform(request)
        try throwIfUnauthorized(status)
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        guard let decoded = try? JSONDecoder().decode(SessionResponse.self, from: data),
              let user = decoded.user
        else { throw APIError.decoding }
        return user
    }

    static func listNotes(force: Bool = false) async throws -> [NoteDocument] {
        try await NativeSWR.fetch(
            key: .notes,
            ttl: NativeSWR.TTL.lists,
            force: force,
            loadDisk: { LocalNoteCache.loadNotes() },
            saveDisk: { LocalNoteCache.saveNotes($0) },
            network: { try await listNotesUncached() }
        )
    }

    private static func listNotesUncached() async throws -> [NoteDocument] {
        let request = try authorizedRequest(path: "api/native/v1/notes", method: "GET")
        let (status, data) = try await perform(request)
        try throwIfUnauthorized(status)
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        guard let decoded = try? JSONDecoder().decode(NotesResponse.self, from: data),
              let notes = decoded.notes
        else { throw APIError.decoding }
        LocalNoteCache.saveNotes(notes)
        return notes
    }

    struct NotePack: Equatable {
        var note: NoteDocument
        var speakers: [SpeakerDTO]
        var via: String
    }

    static func getNote(id: String, force: Bool = false) async throws -> (note: NoteDocument, speakers: [SpeakerDTO], via: String) {
        let pack: NotePack = try await NativeSWR.fetch(
            key: .note(id),
            ttl: NativeSWR.TTL.note,
            force: force,
            loadDisk: {
                // Owned notes only — grants must not be served from Caderno disk cache.
                guard let note = LocalNoteCache.loadNotes().first(where: { $0.id == id }) else { return nil }
                return NotePack(note: note, speakers: LocalNoteCache.loadSpeakers(), via: "owned")
            },
            saveDisk: { pack in
                if pack.via != "grant" {
                    LocalNoteCache.upsertNote(pack.note)
                    _ = LocalNoteCache.mergeSpeakers(pack.speakers)
                }
            },
            network: { try await getNoteUncached(id: id) }
        )
        return (pack.note, pack.speakers, pack.via)
    }

    private static func getNoteUncached(id: String) async throws -> NotePack {
        let request = try authorizedRequest(path: "api/native/v1/notes/\(id)", method: "GET")
        let (status, data) = try await perform(request)
        try throwIfUnauthorized(status)
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        guard let decoded = try? JSONDecoder().decode(NoteResponse.self, from: data),
              let note = decoded.note
        else { throw APIError.decoding }
        let via = decoded.via ?? "owned"
        // Grants must not pollute the owned Caderno cache.
        if via != "grant" {
            LocalNoteCache.upsertNote(note)
        }
        // Note payload only includes speakers used by this note — merge, never replace
        // the full catalog cache (TF200 #3 empty picker).
        let noteSpeakers = decoded.speakers ?? []
        if via != "grant" {
            _ = LocalNoteCache.mergeSpeakers(noteSpeakers)
        }
        return NotePack(note: note, speakers: noteSpeakers, via: via)
    }

    static func listGrantedNotes(force: Bool = false) async throws -> [NoteDocument] {
        try await NativeSWR.fetch(
            key: .granted,
            ttl: NativeSWR.TTL.lists,
            force: force,
            loadDisk: { NativeSWR.loadGranted() },
            saveDisk: { NativeSWR.saveGranted($0) },
            network: { try await listGrantedNotesUncached() }
        )
    }

    private static func listGrantedNotesUncached() async throws -> [NoteDocument] {
        let request = try authorizedRequest(path: "api/native/v1/notes/granted", method: "GET")
        let (status, data) = try await perform(request)
        try throwIfUnauthorized(status)
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        guard let decoded = try? JSONDecoder().decode(NotesResponse.self, from: data),
              let notes = decoded.notes
        else { throw APIError.decoding }
        NativeSWR.saveGranted(notes)
        return notes
    }

    static func listLinks() async throws -> (friends: [LinkPersonDTO], incoming: [LinkPersonDTO], outgoing: [LinkPersonDTO]) {
        let request = try authorizedRequest(path: "api/native/v1/links", method: "GET")
        let (status, data) = try await perform(request)
        try throwIfUnauthorized(status)
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        guard let decoded = try? JSONDecoder().decode(LinksResponse.self, from: data) else {
            throw APIError.decoding
        }
        return (decoded.friends ?? [], decoded.incoming ?? [], decoded.outgoing ?? [])
    }

    static func acceptLink(handle: String) async throws {
        struct Body: Encodable { let handle: String }
        let body = try JSONEncoder().encode(Body(handle: handle))
        let request = try authorizedRequest(path: "api/native/v1/links/accept", method: "POST", body: body)
        let (status, data) = try await perform(request)
        try throwIfUnauthorized(status)
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
    }

    static func declineLink(handle: String) async throws {
        struct Body: Encodable { let handle: String }
        let body = try JSONEncoder().encode(Body(handle: handle))
        let request = try authorizedRequest(path: "api/native/v1/links/decline", method: "POST", body: body)
        let (status, data) = try await perform(request)
        try throwIfUnauthorized(status)
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
    }

    /// Unfriend — deletes the accepted link for both users (+ shared grants).
    static func removeLink(handle: String) async throws {
        struct Body: Encodable { let handle: String }
        let body = try JSONEncoder().encode(Body(handle: handle))
        let request = try authorizedRequest(path: "api/native/v1/links/remove", method: "POST", body: body)
        let (status, data) = try await perform(request)
        try throwIfUnauthorized(status)
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
    }

    /// Web `requestLink` — by @handle. Errors: missing / limit / rate (no user enumeration beyond web).
    @discardableResult
    static func requestLink(handle: String) async throws -> String {
        struct Body: Encodable { let handle: String }
        let body = try JSONEncoder().encode(Body(handle: handle))
        let request = try authorizedRequest(path: "api/native/v1/links/request", method: "POST", body: body)
        let (status, data) = try await perform(request)
        try throwIfUnauthorized(status)
        let decoded = try? JSONDecoder().decode(LinkActionResponse.self, from: data)
        guard status >= 200, status < 300, decoded?.ok == true else {
            let err = decoded?.error ?? (String(data: data, encoding: .utf8) ?? "")
            throw APIError.http(status, err)
        }
        return decoded?.status ?? "outgoing"
    }

    static func searchPeople(query: String) async throws -> [PeopleHitDTO] {
        let request = try authorizedRequest(
            path: "api/native/v1/links/search",
            method: "GET",
            query: [URLQueryItem(name: "q", value: query)]
        )
        let (status, data) = try await perform(request)
        try throwIfUnauthorized(status)
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        guard let decoded = try? JSONDecoder().decode(PeopleSearchResponse.self, from: data) else {
            throw APIError.decoding
        }
        return decoded.people ?? []
    }

    static func listNotifications(
        cursor: String? = nil,
        limit: Int? = nil,
        unreadOnly: Bool = false
    ) async throws -> (items: [InboxItemDTO], nextCursor: String?, unread: Int) {
        var query: [URLQueryItem] = []
        if let cursor, !cursor.isEmpty { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        if let limit { query.append(URLQueryItem(name: "limit", value: String(limit))) }
        if unreadOnly { query.append(URLQueryItem(name: "unreadOnly", value: "1")) }
        let request = try authorizedRequest(path: "api/native/v1/notifications", method: "GET", query: query)
        let (status, data) = try await perform(request)
        try throwIfUnauthorized(status)
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        guard let decoded = try? JSONDecoder().decode(NotificationsResponse.self, from: data) else {
            throw APIError.decoding
        }
        return (decoded.items ?? [], decoded.nextCursor, decoded.unread ?? 0)
    }

    /// Fetches every unread page (for correct dot aggregation beyond page 1).
    static func listAllUnreadNotifications(pageLimit: Int = 50, maxPages: Int = 40) async throws -> [InboxItemDTO] {
        var all: [InboxItemDTO] = []
        var cursor: String? = nil
        for _ in 0..<maxPages {
            let page = try await listNotifications(cursor: cursor, limit: pageLimit, unreadOnly: true)
            all.append(contentsOf: page.items)
            guard let next = page.nextCursor, !next.isEmpty else { break }
            cursor = next
        }
        return all
    }

    static func notificationsSummary() async throws -> (items: [InboxItemDTO], nextCursor: String?, unread: Int, byKind: [String: Int]) {
        let request = try authorizedRequest(path: "api/native/v1/notifications/summary", method: "GET")
        let (status, data) = try await perform(request)
        try throwIfUnauthorized(status)
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        guard let decoded = try? JSONDecoder().decode(NotificationsResponse.self, from: data) else {
            throw APIError.decoding
        }
        return (decoded.items ?? [], decoded.nextCursor, decoded.unread ?? 0, decoded.byKind ?? [:])
    }

    static func markNotificationsRead(id: String? = nil) async throws {
        // Zod `id.optional()` rejects JSON null — omit the key for mark-all.
        let body: Data
        if let id, !id.isEmpty {
            struct Body: Encodable { let id: String }
            body = try JSONEncoder().encode(Body(id: id))
        } else {
            body = Data("{}".utf8)
        }
        let request = try authorizedRequest(path: "api/native/v1/notifications/read", method: "POST", body: body)
        let (status, data) = try await perform(request)
        try throwIfUnauthorized(status)
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
    }

    /// Deletes one alert. Connection requests in Friends are unaffected.
    static func deleteNotification(id: String) async throws {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? trimmed
        let request = try authorizedRequest(path: "api/native/v1/notifications/\(encoded)", method: "DELETE")
        let (status, data) = try await perform(request)
        try throwIfUnauthorized(status)
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
    }

    /// Clears the entire alerts inbox on the server.
    static func clearNotifications() async throws {
        let request = try authorizedRequest(path: "api/native/v1/notifications/clear", method: "POST")
        let (status, data) = try await perform(request)
        try throwIfUnauthorized(status)
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
    }

    static func upsertNote(_ note: NoteDocument) async throws -> NoteDocument {
        var payload = note
        payload.schemaVersion = 1
        payload.updatedAt = ISO8601DateFormatter().string(from: Date())
        let body = try JSONEncoder().encode(payload)
        let request = try authorizedRequest(path: "api/native/v1/notes", method: "POST", body: body)
        let (status, data) = try await perform(request)
        try throwIfUnauthorized(status)
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        guard let decoded = try? JSONDecoder().decode(NoteResponse.self, from: data),
              let saved = decoded.note
        else { throw APIError.decoding }
        LocalNoteCache.upsertNote(saved)
        NativeSWR.invalidateNotesSubtree(noteId: saved.id)
        NativeSWR.markFetched(.note(saved.id), value: NotePack(note: saved, speakers: [], via: "owned"))
        NativeSWR.invalidate(.notes)
        return saved
    }

    static func deleteNote(id: String) async throws {
        let request = try authorizedRequest(path: "api/native/v1/notes/\(id)", method: "DELETE")
        let (status, data) = try await perform(request)
        try throwIfUnauthorized(status)
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        LocalNoteCache.removeNote(id: id)
        NativeSWR.invalidateNotesSubtree(noteId: id)
    }

    static func listSpeakers(force: Bool = false) async throws -> [SpeakerDTO] {
        try await NativeSWR.fetch(
            key: .speakers,
            ttl: NativeSWR.TTL.lists,
            force: force,
            loadDisk: { LocalNoteCache.loadSpeakers() },
            saveDisk: { LocalNoteCache.saveSpeakers($0) },
            network: { try await listSpeakersUncached() }
        )
    }

    private static func listSpeakersUncached() async throws -> [SpeakerDTO] {
        let request = try authorizedRequest(path: "api/native/v1/speakers", method: "GET")
        let (status, data) = try await perform(request)
        try throwIfUnauthorized(status)
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        guard let decoded = try? JSONDecoder().decode(SpeakersResponse.self, from: data),
              let speakers = decoded.speakers
        else { throw APIError.decoding }
        LocalNoteCache.saveSpeakers(speakers)
        return speakers
    }

    static func upsertSpeaker(_ speaker: SpeakerDTO) async throws {
        let body = try JSONEncoder().encode(speaker)
        let request = try authorizedRequest(path: "api/native/v1/speakers", method: "POST", body: body)
        let (status, data) = try await perform(request)
        try throwIfUnauthorized(status)
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        // Keep the picker catalog complete even before the next listSpeakers (TF194 #8).
        _ = LocalNoteCache.mergeSpeakers([speaker])
        NativeSWR.invalidate(.speakers)
    }

    static func deleteSpeaker(id: String) async throws {
        let request = try authorizedRequest(path: "api/native/v1/speakers/\(id)", method: "DELETE")
        let (status, data) = try await perform(request)
        try throwIfUnauthorized(status)
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        LocalNoteCache.removeSpeaker(id: id)
        NativeSWR.invalidate(.speakers)
    }

    static func emptyNote(id: String = UUID().uuidString.replacingOccurrences(of: "-", with: "")) -> NoteDocument {
        let day = ISO8601DateFormatter()
        day.formatOptions = [.withFullDate]
        let now = ISO8601DateFormatter().string(from: Date())
        return NoteDocument(
            schemaVersion: 1,
            id: id,
            title: "",
            happenedAt: day.string(from: Date()),
            tags: [],
            noteSpeakerId: nil,
            visibility: "private",
            updatedAt: now,
            body: NoteBody(blocks: [
                LineBlock(id: UUID().uuidString.replacingOccurrences(of: "-", with: ""), type: "paragraph", spans: [], speakerId: nil, title: nil, collapsed: nil, checked: nil, blocks: nil),
            ])
        )
    }

    // MARK: - Groups (Phase 2)

    static func listGroups(force: Bool = false) async throws -> [GroupDTO] {
        try await NativeSWR.fetch(
            key: .groups,
            ttl: NativeSWR.TTL.lists,
            force: force,
            loadDisk: { LocalSessionCache.loadGroups() },
            saveDisk: { LocalSessionCache.saveGroups($0) },
            network: { try await listGroupsUncached() }
        )
    }

    private static func listGroupsUncached() async throws -> [GroupDTO] {
        let request = try authorizedRequest(path: "api/native/v1/groups", method: "GET")
        let (status, data) = try await perform(request)
        try throwIfUnauthorized(status)
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        guard let decoded = try? JSONDecoder().decode(GroupsResponse.self, from: data),
              let groups = decoded.groups
        else { throw APIError.decoding }
        LocalSessionCache.saveGroups(groups)
        LocalSessionCache.showOfflineHint = false
        return groups
    }

    static func getGroup(id: String) async throws -> GroupDTO {
        let request = try authorizedRequest(path: "api/native/v1/groups/\(id)", method: "GET")
        let (status, data) = try await perform(request)
        try throwIfUnauthorized(status)
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        guard let decoded = try? JSONDecoder().decode(GroupResponse.self, from: data),
              let group = decoded.group
        else { throw APIError.decoding }
        return group
    }

    static func createGroup(name: String, visibility: String = "private", description: String = "") async throws -> GroupDTO {
        struct Body: Encodable {
            let name: String
            let visibility: String
            let description: String
        }
        let body = try JSONEncoder().encode(Body(name: name, visibility: visibility, description: description))
        let request = try authorizedRequest(path: "api/native/v1/groups", method: "POST", body: body)
        let (status, data) = try await perform(request)
        try throwIfUnauthorized(status)
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        guard let decoded = try? JSONDecoder().decode(GroupResponse.self, from: data),
              let group = decoded.group
        else { throw APIError.decoding }
        NativeSWR.invalidate(.groups)
        return group
    }

    static func updateGroup(id: String, name: String?, visibility: String? = nil, description: String? = nil) async throws -> GroupDTO {
        var payload: [String: String] = [:]
        if let name { payload["name"] = name }
        if let visibility { payload["visibility"] = visibility }
        if let description { payload["description"] = description }
        let body = try JSONSerialization.data(withJSONObject: payload)
        let request = try authorizedRequest(path: "api/native/v1/groups/\(id)", method: "PATCH", body: body)
        let (status, data) = try await perform(request)
        try throwIfUnauthorized(status)
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        guard let decoded = try? JSONDecoder().decode(GroupResponse.self, from: data),
              let group = decoded.group
        else { throw APIError.decoding }
        NativeSWR.invalidate(.groups)
        return group
    }

    static func deleteGroup(id: String) async throws {
        let request = try authorizedRequest(path: "api/native/v1/groups/\(id)", method: "DELETE")
        let (status, data) = try await perform(request)
        try throwIfUnauthorized(status)
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        NativeSWR.invalidate(.groups)
    }

    /// Group notes with on-device SWR (~30s throttle), ETag/304, and optional `updatedSince`.
    /// Pull-to-refresh passes `force: true`. Cache is keyed by signed-in user + group id.
    static func listGroupNotes(groupId: String, force: Bool = false) async throws -> [GroupNoteCardDTO] {
        let userId = LocalSessionCache.loadMe()?.id ?? ""
        return try await NativeSWR.fetch(
            key: .groupNotes(groupId),
            ttl: NativeSWR.TTL.groupNotes,
            force: force,
            loadDisk: { LocalGroupNotesCache.load(userId: userId, groupId: groupId) },
            saveDisk: { notes in
                let etag = LocalGroupNotesCache.etag(userId: userId, groupId: groupId)
                LocalGroupNotesCache.save(userId: userId, groupId: groupId, notes: notes, etag: etag)
            },
            network: { try await listGroupNotesUncached(groupId: groupId, force: force) }
        )
    }

    private static func listGroupNotesUncached(groupId: String, force: Bool) async throws -> [GroupNoteCardDTO] {
        let userId = LocalSessionCache.loadMe()?.id ?? ""
        let cachedEntry = LocalGroupNotesCache.loadEntry(userId: userId, groupId: groupId)
        var query: [URLQueryItem] = []
        // Conditional: ask only for notes newer than the cached watermark (server may still
        // return the full list; client merges by note id).
        if !force, let since = cachedEntry.flatMap({ entry -> String? in
            entry.notes.map(\.note.updatedAt).max()
        }), !since.isEmpty {
            query.append(URLQueryItem(name: "updatedSince", value: since))
        }

        var request = try authorizedRequest(
            path: "api/native/v1/groups/\(groupId)/notes",
            method: "GET",
            query: query
        )
        if !force, let etag = cachedEntry?.etag, !etag.isEmpty {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        let (status, data, http) = try await performDetailed(request)
        try throwIfUnauthorized(status)

        // Unchanged — keep disk cache, refresh SWR freshness.
        if status == 304, let cached = cachedEntry?.notes {
            return cached
        }

        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        guard let decoded = try? JSONDecoder().decode(GroupNotesResponse.self, from: data),
              let remote = decoded.notes
        else { throw APIError.decoding }

        let merged: [GroupNoteCardDTO]
        if decoded.incremental == true, let prior = cachedEntry?.notes {
            merged = mergeGroupNotes(prior: prior, delta: remote)
        } else {
            merged = remote
        }

        let responseEtag = http?.value(forHTTPHeaderField: "ETag")
        LocalGroupNotesCache.save(
            userId: userId,
            groupId: groupId,
            notes: merged,
            etag: responseEtag ?? cachedEntry?.etag
        )
        return merged
    }

    /// Merge incremental group-note deltas into the prior cache (by note id), newest first.
    static func mergeGroupNotes(
        prior: [GroupNoteCardDTO],
        delta: [GroupNoteCardDTO]
    ) -> [GroupNoteCardDTO] {
        var byId: [String: GroupNoteCardDTO] = [:]
        for card in prior { byId[card.note.id] = card }
        for card in delta { byId[card.note.id] = card }
        return byId.values.sorted { lhs, rhs in
            if lhs.note.happenedAt != rhs.note.happenedAt {
                return lhs.note.happenedAt > rhs.note.happenedAt
            }
            return lhs.note.updatedAt > rhs.note.updatedAt
        }
    }

    static func publishNote(noteId: String, toGroupId groupId: String) async throws {
        struct Body: Encodable { let noteId: String }
        let body = try JSONEncoder().encode(Body(noteId: noteId))
        let request = try authorizedRequest(path: "api/native/v1/groups/\(groupId)/notes", method: "POST", body: body)
        let (status, data) = try await perform(request)
        try throwIfUnauthorized(status)
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        NativeSWR.invalidate(.groupNotes(groupId))
    }

    static func unpublishNote(noteId: String, fromGroupId groupId: String) async throws {
        let request = try authorizedRequest(path: "api/native/v1/groups/\(groupId)/notes/\(noteId)", method: "DELETE")
        let (status, data) = try await perform(request)
        try throwIfUnauthorized(status)
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        NativeSWR.invalidate(.groupNotes(groupId))
        if let userId = LocalSessionCache.loadMe()?.id {
            // Drop the removed card from disk so next open doesn't flash a ghost row.
            if var cached = LocalGroupNotesCache.load(userId: userId, groupId: groupId) {
                cached.removeAll { $0.note.id == noteId }
                LocalGroupNotesCache.save(
                    userId: userId,
                    groupId: groupId,
                    notes: cached,
                    etag: nil
                )
            }
        }
    }

    static func listGroupsForNote(noteId: String) async throws -> [GroupDTO] {
        let request = try authorizedRequest(path: "api/native/v1/notes/\(noteId)/groups", method: "GET")
        let (status, data) = try await perform(request)
        try throwIfUnauthorized(status)
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        guard let decoded = try? JSONDecoder().decode(GroupsResponse.self, from: data),
              let groups = decoded.groups
        else { throw APIError.decoding }
        return groups
    }

    static func listGroupMembers(groupId: String) async throws -> [GroupMemberDTO] {
        let request = try authorizedRequest(path: "api/native/v1/groups/\(groupId)/members", method: "GET")
        let (status, data) = try await perform(request)
        try throwIfUnauthorized(status)
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        guard let decoded = try? JSONDecoder().decode(GroupMembersResponse.self, from: data),
              let members = decoded.members
        else { throw APIError.decoding }
        return members
    }

    static func decideGroupMember(groupId: String, userId: String, accept: Bool) async throws {
        struct Body: Encodable {
            let userId: String
            let accept: Bool
        }
        let body = try JSONEncoder().encode(Body(userId: userId, accept: accept))
        let request = try authorizedRequest(path: "api/native/v1/groups/\(groupId)/members/decide", method: "POST", body: body)
        let (status, data) = try await perform(request)
        try throwIfUnauthorized(status)
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
    }

    static func setGroupMemberRole(groupId: String, userId: String, role: String) async throws {
        struct Body: Encodable {
            let userId: String
            let role: String
        }
        let body = try JSONEncoder().encode(Body(userId: userId, role: role))
        let request = try authorizedRequest(path: "api/native/v1/groups/\(groupId)/members/role", method: "POST", body: body)
        let (status, data) = try await perform(request)
        try throwIfUnauthorized(status)
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
    }

    static func removeGroupMember(groupId: String, userId: String) async throws {
        let request = try authorizedRequest(path: "api/native/v1/groups/\(groupId)/members/\(userId)", method: "DELETE")
        let (status, data) = try await perform(request)
        try throwIfUnauthorized(status)
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
    }

    // MARK: - Profile (Phase 3)

    static func getMe(force: Bool = false) async throws -> MeDTO {
        try await NativeSWR.fetch(
            key: .me,
            ttl: NativeSWR.TTL.me,
            force: force,
            loadDisk: { LocalSessionCache.loadMe() },
            saveDisk: { LocalSessionCache.saveMe($0) },
            network: { try await getMeUncached() }
        )
    }

    private static func getMeUncached() async throws -> MeDTO {
        let request = try authorizedRequest(path: "api/native/v1/me", method: "GET")
        let (status, data) = try await perform(request)
        try throwIfUnauthorized(status)
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        guard let decoded = try? JSONDecoder().decode(MeResponse.self, from: data),
              let me = decoded.me
        else { throw APIError.decoding }
        LocalSessionCache.saveMe(me)
        LocalSessionCache.showOfflineHint = false
        await MainActor.run { AppAppearance.sync(from: me.prefs) }
        return me
    }

    static func patchMe(_ patch: [String: Any]) async throws -> MeDTO {
        let body = try JSONSerialization.data(withJSONObject: patch)
        let request = try authorizedRequest(path: "api/native/v1/me", method: "PATCH", body: body)
        let (status, data) = try await perform(request)
        try throwIfUnauthorized(status)
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        guard let decoded = try? JSONDecoder().decode(MeResponse.self, from: data),
              let me = decoded.me
        else { throw APIError.decoding }
        LocalSessionCache.saveMe(me)
        NativeSWR.invalidate(.me, .prefs)
        NativeSWR.markFetched(.me, value: me)
        NativeSWR.markFetched(.prefs, value: me.prefs)
        NativeSWR.savePrefs(me.prefs)
        await MainActor.run { AppAppearance.sync(from: me.prefs) }
        return me
    }

    static func getPrefs(force: Bool = false) async throws -> PrefsDTO {
        try await NativeSWR.fetch(
            key: .prefs,
            ttl: NativeSWR.TTL.prefs,
            force: force,
            loadDisk: { NativeSWR.loadPrefs() ?? LocalSessionCache.loadMe()?.prefs },
            saveDisk: { NativeSWR.savePrefs($0) },
            network: { try await getPrefsUncached() }
        )
    }

    private static func getPrefsUncached() async throws -> PrefsDTO {
        let request = try authorizedRequest(path: "api/native/v1/prefs", method: "GET")
        let (status, data) = try await perform(request)
        try throwIfUnauthorized(status)
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        guard let decoded = try? JSONDecoder().decode(PrefsResponse.self, from: data),
              let prefs = decoded.prefs
        else { throw APIError.decoding }
        ReferencePrefs.sync(from: prefs)
        NativeSWR.savePrefs(prefs)
        await MainActor.run { AppAppearance.sync(from: prefs) }
        return prefs
    }

    static func patchPrefs(_ patch: [String: Any]) async throws -> PrefsDTO {
        let body = try JSONSerialization.data(withJSONObject: patch)
        let request = try authorizedRequest(path: "api/native/v1/prefs", method: "PATCH", body: body)
        let (status, data) = try await perform(request)
        try throwIfUnauthorized(status)
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        guard let decoded = try? JSONDecoder().decode(PrefsResponse.self, from: data),
              let prefs = decoded.prefs
        else { throw APIError.decoding }
        ReferencePrefs.sync(from: prefs)
        NativeSWR.savePrefs(prefs)
        NativeSWR.invalidate(.prefs, .me)
        NativeSWR.markFetched(.prefs, value: prefs)
        await MainActor.run { AppAppearance.sync(from: prefs) }
        return prefs
    }

    static func getNotifyPrefs() async throws -> NotifyPrefsDTO {
        let request = try authorizedRequest(path: "api/native/v1/notify-prefs", method: "GET")
        let (status, data) = try await perform(request)
        try throwIfUnauthorized(status)
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        guard let decoded = try? JSONDecoder().decode(NotifyPrefsResponse.self, from: data),
              let notify = decoded.notify
        else { throw APIError.decoding }
        return notify
    }

    static func patchNotifyPrefs(_ patch: [String: Bool]) async throws -> NotifyPrefsDTO {
        let body = try JSONSerialization.data(withJSONObject: patch)
        let request = try authorizedRequest(path: "api/native/v1/notify-prefs", method: "PATCH", body: body)
        let (status, data) = try await perform(request)
        try throwIfUnauthorized(status)
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        guard let decoded = try? JSONDecoder().decode(NotifyPrefsResponse.self, from: data),
              let notify = decoded.notify
        else { throw APIError.decoding }
        return notify
    }

    static func exportAccount() async throws -> Data {
        let request = try authorizedRequest(path: "api/native/v1/account/export", method: "GET")
        let (status, data) = try await perform(request)
        try throwIfUnauthorized(status)
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    static func deleteAccount() async throws {
        let request = try authorizedRequest(path: "api/native/v1/account/delete", method: "POST")
        let (status, data) = try await perform(request)
        try throwIfUnauthorized(status)
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
    }

    // Phase 0 smoke helpers
    static func getNotes() async throws -> (status: Int, body: Data) {
        let request = try authorizedRequest(path: "api/native/v1/notes", method: "GET")
        return try await perform(request)
    }

    static func parseNotesCount(_ data: Data) -> Int? {
        guard let decoded = try? JSONDecoder().decode(NotesResponse.self, from: data) else { return nil }
        return decoded.notes?.count
    }

    // MARK: - Verses / bible (Phase 4)

    struct BibleBookDTO: Codable, Equatable {
        var id: String
        var testament: String
        var name: String
        var abbr: String
        var chapters: Int
        var verses: [Int]
    }

    struct BibleAppDTO: Codable, Equatable {
        var id: String
        var name: String
        var blurb: String?
        var hasWeb: Bool?
        var hasNative: Bool?
        var usesTranslation: Bool?
    }

    struct BibleTranslationDTO: Codable, Equatable {
        var id: String
        var locale: String?
        var abbr: String
        var name: String
    }

    struct PassageDTO: Codable, Equatable {
        var bookId: String
        var chapter: Int
        var verseStart: Int?
        var verseEnd: Int?

        var labelHint: String {
            BibleBookCatalog.formatPassage(
                bookId: bookId,
                chapter: chapter,
                verseStart: verseStart,
                verseEnd: verseEnd
            )
        }
    }

    struct LinkItemDTO: Codable, Equatable {
        var input: String?
        var label: String
        var url: String
        var markdown: String?
        var html: String?
        var plain: String?
    }

    struct ThemeCardDTO: Codable, Equatable {
        var id: String
        var name: String
        var count: Int?
        var snippet: String?
    }

    struct CategoryCardDTO: Codable, Equatable {
        var id: String
        var name: String
        var count: Int?
    }

    struct ThemePassageDTO: Codable, Equatable {
        var bookId: String
        var chapter: Int
        var verseStart: Int?
        var verseEnd: Int?
        var label: String?
        var snippet: String?

        var asPassage: PassageDTO {
            PassageDTO(bookId: bookId, chapter: chapter, verseStart: verseStart, verseEnd: verseEnd)
        }
    }

    struct UserCollectionDTO: Codable, Equatable {
        var id: String
        var title: String
        var slug: String?
        var visibility: String?
        var sourceId: String?
        var passages: [PassageDTO]?
        var updatedAt: String?
    }

    private struct BooksResponse: Decodable {
        let ok: Bool?
        let books: [BibleBookDTO]?
        let error: String?
    }

    private struct AppsResponse: Decodable {
        let ok: Bool?
        let apps: [BibleAppDTO]?
        let translations: [BibleTranslationDTO]?
        let error: String?
    }

    private struct LinkResponse: Decodable {
        let ok: Bool?
        let items: [LinkItemDTO]?
        let plain: String?
        let markdown: String?
        let error: String?
    }

    private struct ThemesIndexResponse: Decodable {
        let ok: Bool?
        let kind: String?
        let themeTotal: Int?
        let categories: [CategoryCardDTO]?
        let themes: [ThemeCardDTO]?
        let theme: ThemeCardDTO?
        let passages: [ThemePassageDTO]?
        let items: [LinkItemDTO]?
        let error: String?
    }

    private struct AppendVerseResponse: Decodable {
        let ok: Bool?
        let note: NoteDocument?
        let label: String?
        let error: String?
    }

    private struct CollectionsResponse: Decodable {
        let ok: Bool?
        let collections: [UserCollectionDTO]?
        let collection: UserCollectionDTO?
        let error: String?
    }

    private static func publicRequest(path: String, method: String = "GET", body: Data? = nil, query: [URLQueryItem] = []) throws -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw APIError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = KeychainStore.bearerToken(), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = body
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    static func fetchBibleBooks(locale: String = AppLocale.apiCode, force: Bool = false) async throws -> [BibleBookDTO] {
        // Permanent on-device catalog: memory → disk → bundled JSON.
        // Network only if missing/corrupt or `NativeSWR.bibleBooksBundleVersion` changed.
        // `force` re-reads disk/bundle; it does NOT trigger a daily/periodic refetch.
        if !force, let mem: [BibleBookDTO] = NativeSWR.cachedValue(.bibleBooks(locale)), !mem.isEmpty {
            return mem
        }
        if let cached = NativeSWR.loadBibleBooks(locale: locale) {
            NativeSWR.markFetched(.bibleBooks(locale), value: cached)
            return cached
        }
        if let bundled = NativeSWR.loadBundledBibleBooks(locale: locale) {
            NativeSWR.saveBibleBooks(bundled, locale: locale)
            NativeSWR.markFetched(.bibleBooks(locale), value: bundled)
            return bundled
        }
        return try await NativeSWR.fetch(
            key: .bibleBooks(locale),
            ttl: NativeSWR.TTL.bibleBooks,
            force: true,
            loadDisk: { NativeSWR.loadBibleBooks(locale: locale) },
            saveDisk: { NativeSWR.saveBibleBooks($0, locale: locale) },
            network: { try await fetchBibleBooksFromNetwork(locale: locale) }
        )
    }

    private static func fetchBibleBooksFromNetwork(locale: String) async throws -> [BibleBookDTO] {
        let request = try publicRequest(
            path: "api/native/v1/bible/books",
            query: [URLQueryItem(name: "locale", value: locale)]
        )
        let (status, data) = try await perform(request)
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        guard let decoded = try? JSONDecoder().decode(BooksResponse.self, from: data),
              let books = decoded.books, !books.isEmpty
        else { throw APIError.decoding }
        return books
    }

    static func fetchBibleApps(locale: String = AppLocale.apiCode) async throws -> (apps: [BibleAppDTO], translations: [BibleTranslationDTO]) {
        let request = try publicRequest(
            path: "api/native/v1/bible/apps",
            query: [URLQueryItem(name: "locale", value: locale)]
        )
        let (status, data) = try await perform(request)
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        guard let decoded = try? JSONDecoder().decode(AppsResponse.self, from: data),
              let apps = decoded.apps
        else { throw APIError.decoding }
        return (apps, decoded.translations ?? [])
    }

    static func resolveBibleLink(passage: PassageDTO, appId: String? = nil, translationId: String? = nil, preferNative: Bool? = nil) async throws -> LinkItemDTO {
        var payload: [String: Any] = [
            "ref": passage.labelHint.replacingOccurrences(of: "–", with: "-"),
            "locale": AppLocale.apiCode,
        ]
        // Prefer structured fields via refs that parse — also send book-style via label.
        if let appId { payload["app"] = appId }
        if let translationId { payload["translation"] = translationId }
        if let preferNative { payload["native"] = preferNative }
        // Use POST with bookId-style ref string João… Prefer building from ids:
        payload["refs"] = [formatRefForLink(passage)]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let request = try publicRequest(path: "api/native/v1/bible/link", method: "POST", body: body)
        let (status, data) = try await perform(request)
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        guard let decoded = try? JSONDecoder().decode(LinkResponse.self, from: data),
              let item = decoded.items?.first
        else { throw APIError.decoding }
        return item
    }

    static func formatRefForLink(_ passage: PassageDTO) -> String {
        // OSIS-ish English ids parse poorly for pt locale; send "JHN 3:16" which parseReference accepts.
        if let verseStart = passage.verseStart {
            if let verseEnd = passage.verseEnd, verseEnd != verseStart {
                return "\(passage.bookId) \(passage.chapter):\(verseStart)-\(verseEnd)"
            }
            return "\(passage.bookId) \(passage.chapter):\(verseStart)"
        }
        return "\(passage.bookId) \(passage.chapter)"
    }

    static func fetchThemes(
        categoryId: String? = nil,
        themeId: String? = nil,
        query: String? = nil,
        force: Bool = false
    ) async throws -> ThemesIndexResponseProxy {
        let isIndex = categoryId == nil && themeId == nil && (query == nil || query?.isEmpty == true)
        if isIndex, !force,
           let cached = NativeSWR.loadThemesPayload(),
           let decoded = try? JSONDecoder().decode(ThemesIndexResponse.self, from: cached)
        {
            NativeSWR.markFetched(.themesCatalog, value: true)
            return themesProxy(from: decoded)
        }
        var items: [URLQueryItem] = [URLQueryItem(name: "locale", value: AppLocale.apiCode)]
        if let categoryId { items.append(URLQueryItem(name: "category", value: categoryId)) }
        if let themeId { items.append(URLQueryItem(name: "id", value: themeId)) }
        if let query, !query.isEmpty { items.append(URLQueryItem(name: "q", value: query)) }
        let request = try publicRequest(path: "api/native/v1/bible/themes", query: items)
        let (status, data) = try await perform(request)
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        guard let decoded = try? JSONDecoder().decode(ThemesIndexResponse.self, from: data) else {
            throw APIError.decoding
        }
        if isIndex {
            NativeSWR.saveThemesPayload(data)
            NativeSWR.markFetched(.themesCatalog, value: true)
        }
        return themesProxy(from: decoded)
    }

    private static func themesProxy(from decoded: ThemesIndexResponse) -> ThemesIndexResponseProxy {
        ThemesIndexResponseProxy(
            kind: decoded.kind ?? "",
            themeTotal: decoded.themeTotal,
            categories: decoded.categories ?? [],
            themes: decoded.themes ?? [],
            theme: decoded.theme,
            passages: decoded.passages ?? [],
            items: decoded.items ?? []
        )
    }

    struct ThemesIndexResponseProxy {
        var kind: String
        var themeTotal: Int?
        var categories: [CategoryCardDTO]
        var themes: [ThemeCardDTO]
        var theme: ThemeCardDTO?
        var passages: [ThemePassageDTO]
        var items: [LinkItemDTO]
    }

    static func appendVerse(_ passage: PassageDTO, noteId: String? = nil) async throws -> (note: NoteDocument, label: String) {
        var payload: [String: Any] = [
            "bookId": passage.bookId,
            "chapter": passage.chapter,
        ]
        if let verseStart = passage.verseStart { payload["verseStart"] = verseStart }
        if let verseEnd = passage.verseEnd { payload["verseEnd"] = verseEnd }
        if let noteId { payload["noteId"] = noteId }
        let body = try JSONSerialization.data(withJSONObject: payload)
        let request = try authorizedRequest(path: "api/native/v1/verses/append", method: "POST", body: body)
        let (status, data) = try await perform(request)
        try throwIfUnauthorized(status)
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        guard let decoded = try? JSONDecoder().decode(AppendVerseResponse.self, from: data),
              let note = decoded.note
        else { throw APIError.decoding }
        LocalNoteCache.upsertNote(note)
        NotificationCenter.default.post(name: .nativeNoteDidChange, object: note.id)
        return (note, decoded.label ?? passage.labelHint)
    }

    static func listMyCollections() async throws -> [UserCollectionDTO] {
        let request = try authorizedRequest(path: "api/native/v1/my-collections", method: "GET")
        let (status, data) = try await perform(request)
        try throwIfUnauthorized(status)
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        guard let decoded = try? JSONDecoder().decode(CollectionsResponse.self, from: data),
              let collections = decoded.collections
        else { throw APIError.decoding }
        return collections
    }

    static func createMyCollection(title: String) async throws -> UserCollectionDTO {
        let body = try JSONSerialization.data(withJSONObject: ["title": title, "passages": []])
        let request = try authorizedRequest(path: "api/native/v1/my-collections", method: "POST", body: body)
        let (status, data) = try await perform(request)
        try throwIfUnauthorized(status)
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        guard let decoded = try? JSONDecoder().decode(CollectionsResponse.self, from: data),
              let collection = decoded.collection
        else { throw APIError.decoding }
        return collection
    }

    /// Idempotent upsert for legacy import / outbox — preserves client `id` when possible.
    static func upsertMyCollection(_ collection: UserCollectionDTO) async throws -> UserCollectionDTO {
        var payload: [String: Any] = [
            "id": collection.id,
            "title": collection.title,
            "passages": (collection.passages ?? []).map { passage -> [String: Any] in
                var row: [String: Any] = ["bookId": passage.bookId, "chapter": passage.chapter]
                if let verseStart = passage.verseStart { row["verseStart"] = verseStart }
                if let verseEnd = passage.verseEnd { row["verseEnd"] = verseEnd }
                return row
            },
        ]
        if let visibility = collection.visibility { payload["visibility"] = visibility }
        if let sourceId = collection.sourceId { payload["sourceId"] = sourceId }
        let body = try JSONSerialization.data(withJSONObject: payload)
        let request = try authorizedRequest(path: "api/native/v1/my-collections", method: "POST", body: body)
        let (status, data) = try await perform(request)
        try throwIfUnauthorized(status)
        guard status >= 200, status < 300 else {
            // If POST-with-id isn't understood by an older deploy, attempt PATCH then create.
            if !collection.id.isEmpty {
                let patchBody = try JSONSerialization.data(withJSONObject: payload)
                let patchReq = try authorizedRequest(
                    path: "api/native/v1/my-collections/\(collection.id)",
                    method: "PATCH",
                    body: patchBody
                )
                let (patchStatus, patchData) = try await perform(patchReq)
                try throwIfUnauthorized(patchStatus)
                if patchStatus >= 200, patchStatus < 300,
                   let decoded = try? JSONDecoder().decode(CollectionsResponse.self, from: patchData),
                   let saved = decoded.collection
                {
                    return saved
                }
            }
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        guard let decoded = try? JSONDecoder().decode(CollectionsResponse.self, from: data),
              let saved = decoded.collection
        else { throw APIError.decoding }
        return saved
    }

    static func savePassageToCollection(passage: PassageDTO, collectionId: String? = nil, title: String? = nil) async throws -> UserCollectionDTO {
        var passageObj: [String: Any] = [
            "bookId": passage.bookId,
            "chapter": passage.chapter,
        ]
        if let verseStart = passage.verseStart { passageObj["verseStart"] = verseStart }
        if let verseEnd = passage.verseEnd { passageObj["verseEnd"] = verseEnd }
        var payload: [String: Any] = ["passage": passageObj]
        if let collectionId { payload["collectionId"] = collectionId }
        if let title { payload["title"] = title }
        let body = try JSONSerialization.data(withJSONObject: payload)
        let request = try authorizedRequest(path: "api/native/v1/my-collections/save", method: "POST", body: body)
        let (status, data) = try await perform(request)
        try throwIfUnauthorized(status)
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        guard let decoded = try? JSONDecoder().decode(CollectionsResponse.self, from: data),
              let collection = decoded.collection
        else { throw APIError.decoding }
        return collection
    }

    // MARK: - APNs devices (Phase 5 — native, no Capacitor)

    static func saveApnsDevice(token: String, sandbox: Bool) async throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "token": token,
            "sandbox": sandbox,
        ])
        let request = try authorizedRequest(path: "api/native/v1/devices/apns", method: "POST", body: body)
        let (status, data) = try await perform(request)
        try throwIfUnauthorized(status)
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
    }

    static func dropApnsDevice(token: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["token": token])
        let request = try authorizedRequest(path: "api/native/v1/devices/apns", method: "DELETE", body: body)
        let (status, data) = try await perform(request)
        try throwIfUnauthorized(status)
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
    }

    // MARK: - Reading plans (Leitura)

    struct PlanCardDTO: Codable, Equatable {
        var id: String
        var name: String
        var days: Int
        var chapters: Int?
        var description: String?
        var categoryIds: [String]?
    }

    struct PlanCategoryDTO: Codable, Equatable {
        var id: String
        var name: String
        var count: Int?
    }

    struct PlanDayDTO: Codable, Equatable {
        var day: Int
        var labels: [String]
    }

    struct PlansIndexResponse: Decodable {
        let ok: Bool?
        let kind: String?
        let planTotal: Int?
        let categories: [PlanCategoryDTO]?
        let plans: [PlanCardDTO]?
        let plan: PlanCardDTO?
        let days: [PlanDayDTO]?
        let day: Int?
        let labels: [String]?
        let items: [LinkItemDTO]?
        let error: String?
    }

    struct PlansIndexProxy {
        var kind: String
        var planTotal: Int?
        var categories: [PlanCategoryDTO]
        var plans: [PlanCardDTO]
        var plan: PlanCardDTO?
        var days: [PlanDayDTO]
        var day: Int?
        var labels: [String]
        var items: [LinkItemDTO]
    }

    static func fetchReadingPlans(
        query: String? = nil,
        categoryId: String? = nil,
        planId: String? = nil,
        day: Int? = nil,
        force: Bool = false
    ) async throws -> PlansIndexProxy {
        let isIndex = categoryId == nil && planId == nil && day == nil && (query == nil || query?.isEmpty == true)
        if isIndex, !force,
           let cached = NativeSWR.loadReadingPayload(),
           let decoded = try? JSONDecoder().decode(PlansIndexResponse.self, from: cached)
        {
            NativeSWR.markFetched(.readingCatalog, value: true)
            return plansProxy(from: decoded)
        }
        var items: [URLQueryItem] = [URLQueryItem(name: "locale", value: AppLocale.apiCode)]
        if let query, !query.isEmpty { items.append(URLQueryItem(name: "q", value: query)) }
        if let categoryId { items.append(URLQueryItem(name: "category", value: categoryId)) }
        if let planId { items.append(URLQueryItem(name: "id", value: planId)) }
        if let day { items.append(URLQueryItem(name: "day", value: String(day))) }
        let request = try publicRequest(path: "api/native/v1/plans", query: items)
        let (status, data) = try await perform(request)
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        guard let decoded = try? JSONDecoder().decode(PlansIndexResponse.self, from: data) else {
            throw APIError.decoding
        }
        if isIndex {
            NativeSWR.saveReadingPayload(data)
            NativeSWR.markFetched(.readingCatalog, value: true)
        }
        return plansProxy(from: decoded)
    }

    private static func plansProxy(from decoded: PlansIndexResponse) -> PlansIndexProxy {
        PlansIndexProxy(
            kind: decoded.kind ?? "",
            planTotal: decoded.planTotal,
            categories: decoded.categories ?? [],
            plans: decoded.plans ?? [],
            plan: decoded.plan,
            days: decoded.days ?? [],
            day: decoded.day,
            labels: decoded.labels ?? [],
            items: decoded.items ?? []
        )
    }

    struct CatalogVersionsDTO: Decodable {
        var bibleBooks: String?
        var themes: String?
        var reading: String?
    }

    static func fetchCatalogVersions() async throws -> CatalogVersionsDTO {
        let request = try publicRequest(path: "api/native/v1/catalog/versions")
        let (status, data) = try await perform(request)
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        guard let decoded = try? JSONDecoder().decode(CatalogVersionsDTO.self, from: data) else {
            throw APIError.decoding
        }
        return decoded
    }

    static func startReadingPlan(_ planId: String) async throws -> PrefsDTO {
        let body = try JSONSerialization.data(withJSONObject: ["planId": planId])
        let request = try authorizedRequest(path: "api/native/v1/plans/start", method: "POST", body: body)
        let (status, data) = try await perform(request)
        try throwIfUnauthorized(status)
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        struct Resp: Decodable { let ok: Bool?; let prefs: PrefsDTO? }
        guard let decoded = try? JSONDecoder().decode(Resp.self, from: data), let prefs = decoded.prefs else {
            throw APIError.decoding
        }
        return prefs
    }

    static func stopReadingPlan(_ planId: String) async throws -> PrefsDTO {
        let body = try JSONSerialization.data(withJSONObject: ["planId": planId])
        let request = try authorizedRequest(path: "api/native/v1/plans/stop", method: "POST", body: body)
        let (status, data) = try await perform(request)
        try throwIfUnauthorized(status)
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        struct Resp: Decodable { let ok: Bool?; let prefs: PrefsDTO? }
        guard let decoded = try? JSONDecoder().decode(Resp.self, from: data), let prefs = decoded.prefs else {
            throw APIError.decoding
        }
        return prefs
    }

    static func markReadingPlanDay(planId: String, day: Int, on: Bool) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["planId": planId, "day": day, "on": on])
        let request = try authorizedRequest(path: "api/native/v1/plans/mark", method: "POST", body: body)
        let (status, data) = try await perform(request)
        try throwIfUnauthorized(status)
        if status == 429 {
            throw APIError.http(429, String(localized: "Limite de 2 marcações por dia."))
        }
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
    }

    static func resetReadingPlanMarks(planId: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["planId": planId])
        let request = try authorizedRequest(path: "api/native/v1/plans/reset", method: "POST", body: body)
        let (status, data) = try await perform(request)
        try throwIfUnauthorized(status)
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
    }

    static func createReadingPlanInvite(planId: String) async throws -> String {
        let body = try JSONSerialization.data(withJSONObject: ["planId": planId])
        let request = try authorizedRequest(path: "api/native/v1/plans/invite", method: "POST", body: body)
        let (status, data) = try await perform(request)
        try throwIfUnauthorized(status)
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        struct Resp: Decodable { let ok: Bool?; let id: String? }
        guard let decoded = try? JSONDecoder().decode(Resp.self, from: data), let id = decoded.id else {
            throw APIError.decoding
        }
        return id
    }

    static func joinReadingPlanGroup(groupId: String) async throws -> String {
        let body = try JSONSerialization.data(withJSONObject: ["id": groupId])
        let request = try authorizedRequest(path: "api/native/v1/plans/join", method: "POST", body: body)
        let (status, data) = try await perform(request)
        try throwIfUnauthorized(status)
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        struct Resp: Decodable { let ok: Bool?; let planId: String? }
        guard let decoded = try? JSONDecoder().decode(Resp.self, from: data), let planId = decoded.planId else {
            throw APIError.decoding
        }
        return planId
    }

}

