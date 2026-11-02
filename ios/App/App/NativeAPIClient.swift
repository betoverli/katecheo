import Foundation

/// URLSession client for `/api/native/v1` using the Keychain bearer.
/// Payloads are **NoteDocumentV1** (never HTML).
enum NativeAPIClient {
    static var baseURL: URL {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "Verse2NoteAPIBase") as? String,
           let url = URL(string: raw), !raw.isEmpty
        {
            return url
        }
        return URL(string: "https://verse2note.com")!
    }

    enum APIError: Error, LocalizedError {
        case unauthorized
        case http(Int, String)
        case decoding
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .unauthorized: return "Sessão necessária."
            case .http(let code, let body): return "HTTP \(code): \(body)"
            case .decoding: return "Resposta inválida."
            case .invalidResponse: return "Sem resposta."
            }
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
            return text.isEmpty ? "Sem texto" : text
        }

        private func spanText(_ spans: [TextSpan]?) -> String {
            (spans ?? []).map { span in
                if span.type == "bibleRef" {
                    let book = span.bookId ?? "?"
                    let ch = span.chapter.map(String.init) ?? "?"
                    if let v = span.verseStart { return "\(book) \(ch):\(v)" }
                    return "\(book) \(ch)"
                }
                return span.text ?? ""
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
        let error: String?
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
            return "Membro"
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

    private static func authorizedRequest(path: String, method: String, body: Data? = nil) throws -> URLRequest {
        guard let token = KeychainStore.bearerToken(), !token.isEmpty else {
            throw APIError.unauthorized
        }
        var url = baseURL
        for part in path.split(separator: "/") {
            url = url.appendingPathComponent(String(part))
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
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (status, data)
    }

    static var hasBearer: Bool {
        !(KeychainStore.bearerToken() ?? "").isEmpty
    }

    static func getSession() async throws -> SessionUser {
        let request = try authorizedRequest(path: "api/native/v1/session", method: "GET")
        let (status, data) = try await perform(request)
        if status == 401 { throw APIError.unauthorized }
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        guard let decoded = try? JSONDecoder().decode(SessionResponse.self, from: data),
              let user = decoded.user
        else { throw APIError.decoding }
        return user
    }

    static func listNotes() async throws -> [NoteDocument] {
        let request = try authorizedRequest(path: "api/native/v1/notes", method: "GET")
        let (status, data) = try await perform(request)
        if status == 401 { throw APIError.unauthorized }
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        guard let decoded = try? JSONDecoder().decode(NotesResponse.self, from: data),
              let notes = decoded.notes
        else { throw APIError.decoding }
        LocalNoteCache.saveNotes(notes)
        return notes
    }

    static func getNote(id: String) async throws -> (note: NoteDocument, speakers: [SpeakerDTO]) {
        let request = try authorizedRequest(path: "api/native/v1/notes/\(id)", method: "GET")
        let (status, data) = try await perform(request)
        if status == 401 { throw APIError.unauthorized }
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        guard let decoded = try? JSONDecoder().decode(NoteResponse.self, from: data),
              let note = decoded.note
        else { throw APIError.decoding }
        LocalNoteCache.upsertNote(note)
        return (note, decoded.speakers ?? [])
    }

    static func upsertNote(_ note: NoteDocument) async throws -> NoteDocument {
        var payload = note
        payload.schemaVersion = 1
        payload.updatedAt = ISO8601DateFormatter().string(from: Date())
        let body = try JSONEncoder().encode(payload)
        let request = try authorizedRequest(path: "api/native/v1/notes", method: "POST", body: body)
        let (status, data) = try await perform(request)
        if status == 401 { throw APIError.unauthorized }
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        guard let decoded = try? JSONDecoder().decode(NoteResponse.self, from: data),
              let saved = decoded.note
        else { throw APIError.decoding }
        LocalNoteCache.upsertNote(saved)
        return saved
    }

    static func deleteNote(id: String) async throws {
        let request = try authorizedRequest(path: "api/native/v1/notes/\(id)", method: "DELETE")
        let (status, data) = try await perform(request)
        if status == 401 { throw APIError.unauthorized }
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        LocalNoteCache.removeNote(id: id)
    }

    static func listSpeakers() async throws -> [SpeakerDTO] {
        let request = try authorizedRequest(path: "api/native/v1/speakers", method: "GET")
        let (status, data) = try await perform(request)
        if status == 401 { throw APIError.unauthorized }
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
        if status == 401 { throw APIError.unauthorized }
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
    }

    static func deleteSpeaker(id: String) async throws {
        let request = try authorizedRequest(path: "api/native/v1/speakers/\(id)", method: "DELETE")
        let (status, data) = try await perform(request)
        if status == 401 { throw APIError.unauthorized }
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
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
                LineBlock(id: UUID().uuidString.replacingOccurrences(of: "-", with: ""), type: "paragraph", spans: [], speakerId: nil, title: nil, collapsed: nil, blocks: nil),
            ])
        )
    }

    // MARK: - Groups (Phase 2)

    static func listGroups() async throws -> [GroupDTO] {
        let request = try authorizedRequest(path: "api/native/v1/groups", method: "GET")
        let (status, data) = try await perform(request)
        if status == 401 { throw APIError.unauthorized }
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        guard let decoded = try? JSONDecoder().decode(GroupsResponse.self, from: data),
              let groups = decoded.groups
        else { throw APIError.decoding }
        return groups
    }

    static func getGroup(id: String) async throws -> GroupDTO {
        let request = try authorizedRequest(path: "api/native/v1/groups/\(id)", method: "GET")
        let (status, data) = try await perform(request)
        if status == 401 { throw APIError.unauthorized }
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
        if status == 401 { throw APIError.unauthorized }
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        guard let decoded = try? JSONDecoder().decode(GroupResponse.self, from: data),
              let group = decoded.group
        else { throw APIError.decoding }
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
        if status == 401 { throw APIError.unauthorized }
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        guard let decoded = try? JSONDecoder().decode(GroupResponse.self, from: data),
              let group = decoded.group
        else { throw APIError.decoding }
        return group
    }

    static func deleteGroup(id: String) async throws {
        let request = try authorizedRequest(path: "api/native/v1/groups/\(id)", method: "DELETE")
        let (status, data) = try await perform(request)
        if status == 401 { throw APIError.unauthorized }
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
    }

    static func listGroupNotes(groupId: String) async throws -> [GroupNoteCardDTO] {
        let request = try authorizedRequest(path: "api/native/v1/groups/\(groupId)/notes", method: "GET")
        let (status, data) = try await perform(request)
        if status == 401 { throw APIError.unauthorized }
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        guard let decoded = try? JSONDecoder().decode(GroupNotesResponse.self, from: data),
              let notes = decoded.notes
        else { throw APIError.decoding }
        return notes
    }

    static func publishNote(noteId: String, toGroupId groupId: String) async throws {
        struct Body: Encodable { let noteId: String }
        let body = try JSONEncoder().encode(Body(noteId: noteId))
        let request = try authorizedRequest(path: "api/native/v1/groups/\(groupId)/notes", method: "POST", body: body)
        let (status, data) = try await perform(request)
        if status == 401 { throw APIError.unauthorized }
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
    }

    static func unpublishNote(noteId: String, fromGroupId groupId: String) async throws {
        let request = try authorizedRequest(path: "api/native/v1/groups/\(groupId)/notes/\(noteId)", method: "DELETE")
        let (status, data) = try await perform(request)
        if status == 401 { throw APIError.unauthorized }
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
    }

    static func listGroupsForNote(noteId: String) async throws -> [GroupDTO] {
        let request = try authorizedRequest(path: "api/native/v1/notes/\(noteId)/groups", method: "GET")
        let (status, data) = try await perform(request)
        if status == 401 { throw APIError.unauthorized }
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        guard let decoded = try? JSONDecoder().decode(GroupsResponse.self, from: data),
              let groups = decoded.groups
        else { throw APIError.decoding }
        return groups
    }

    // MARK: - Profile (Phase 3)

    static func getMe() async throws -> MeDTO {
        let request = try authorizedRequest(path: "api/native/v1/me", method: "GET")
        let (status, data) = try await perform(request)
        if status == 401 { throw APIError.unauthorized }
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        guard let decoded = try? JSONDecoder().decode(MeResponse.self, from: data),
              let me = decoded.me
        else { throw APIError.decoding }
        return me
    }

    static func patchMe(_ patch: [String: Any]) async throws -> MeDTO {
        let body = try JSONSerialization.data(withJSONObject: patch)
        let request = try authorizedRequest(path: "api/native/v1/me", method: "PATCH", body: body)
        let (status, data) = try await perform(request)
        if status == 401 { throw APIError.unauthorized }
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        guard let decoded = try? JSONDecoder().decode(MeResponse.self, from: data),
              let me = decoded.me
        else { throw APIError.decoding }
        return me
    }

    static func getPrefs() async throws -> PrefsDTO {
        let request = try authorizedRequest(path: "api/native/v1/prefs", method: "GET")
        let (status, data) = try await perform(request)
        if status == 401 { throw APIError.unauthorized }
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        guard let decoded = try? JSONDecoder().decode(PrefsResponse.self, from: data),
              let prefs = decoded.prefs
        else { throw APIError.decoding }
        return prefs
    }

    static func patchPrefs(_ patch: [String: Any]) async throws -> PrefsDTO {
        let body = try JSONSerialization.data(withJSONObject: patch)
        let request = try authorizedRequest(path: "api/native/v1/prefs", method: "PATCH", body: body)
        let (status, data) = try await perform(request)
        if status == 401 { throw APIError.unauthorized }
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        guard let decoded = try? JSONDecoder().decode(PrefsResponse.self, from: data),
              let prefs = decoded.prefs
        else { throw APIError.decoding }
        return prefs
    }

    static func getNotifyPrefs() async throws -> NotifyPrefsDTO {
        let request = try authorizedRequest(path: "api/native/v1/notify-prefs", method: "GET")
        let (status, data) = try await perform(request)
        if status == 401 { throw APIError.unauthorized }
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
        if status == 401 { throw APIError.unauthorized }
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
        if status == 401 { throw APIError.unauthorized }
        guard status >= 200, status < 300 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    static func deleteAccount() async throws {
        let request = try authorizedRequest(path: "api/native/v1/account/delete", method: "POST")
        let (status, data) = try await perform(request)
        if status == 401 { throw APIError.unauthorized }
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
}
