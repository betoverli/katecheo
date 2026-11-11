import Foundation

/// On-device mirror of group note cards, keyed by account + group id.
/// Stale-while-revalidate: paint last known list immediately, refresh in background.
enum LocalGroupNotesCache {
    struct Entry: Codable, Equatable {
        var notes: [NativeAPIClient.GroupNoteCardDTO]
        var etag: String?
        var fetchedAt: Date
    }

    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("NativeGroupNotes", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        return dir
    }

    private static func fileURL(userId: String, groupId: String) -> URL {
        let safeUser = sanitize(userId)
        let safeGroup = sanitize(groupId)
        return directory.appendingPathComponent("\(safeUser)_\(safeGroup)-v1.json")
    }

    private static func sanitize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: ".", with: "_")
    }

    private static func writeProtected(_ data: Data, to url: URL) {
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func save(
        userId: String,
        groupId: String,
        notes: [NativeAPIClient.GroupNoteCardDTO],
        etag: String?,
        fetchedAt: Date = Date()
    ) {
        guard !userId.isEmpty, !groupId.isEmpty else { return }
        let entry = Entry(notes: notes, etag: etag, fetchedAt: fetchedAt)
        guard let data = try? JSONEncoder().encode(entry) else { return }
        writeProtected(data, to: fileURL(userId: userId, groupId: groupId))
    }

    static func loadEntry(userId: String, groupId: String) -> Entry? {
        guard !userId.isEmpty, !groupId.isEmpty else { return nil }
        guard let data = try? Data(contentsOf: fileURL(userId: userId, groupId: groupId)),
              let entry = try? JSONDecoder().decode(Entry.self, from: data)
        else { return nil }
        return entry
    }

    static func load(userId: String, groupId: String) -> [NativeAPIClient.GroupNoteCardDTO]? {
        loadEntry(userId: userId, groupId: groupId)?.notes
    }

    static func etag(userId: String, groupId: String) -> String? {
        loadEntry(userId: userId, groupId: groupId)?.etag
    }

    /// Newest `note.updatedAt` in the cached list — used as `updatedSince` for conditional GETs.
    static func maxUpdatedAt(userId: String, groupId: String) -> String? {
        guard let notes = load(userId: userId, groupId: groupId), !notes.isEmpty else { return nil }
        return notes.map(\.note.updatedAt).max()
    }

    static func clear(userId: String, groupId: String) {
        try? FileManager.default.removeItem(at: fileURL(userId: userId, groupId: groupId))
    }

    /// Account switch / logout — must not leak another user's group notes.
    static func clearAll() {
        try? FileManager.default.removeItem(at: directory)
    }
}
