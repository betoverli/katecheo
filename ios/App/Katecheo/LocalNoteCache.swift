import Foundation
import os.log

/// On-device mirror of `NoteDocumentV1` lists for offline read / quick paint.
/// Disk is the source of truth for owned notes while dirty or pending sync.
enum LocalNoteCache {
    private static let log = Logger(subsystem: "app.katecheo", category: "LocalNoteCache")

    /// Per-note sync metadata — not part of the wire `NoteDocument`.
    struct NoteSyncMeta: Codable, Equatable {
        var dirty: Bool
        var pendingSync: Bool
        /// ISO-8601 edit time (fractional seconds) stamped when the user changed the note locally.
        var localUpdatedAt: String
        /// Monotonic local edit counter — survives same-millisecond stamps and string-compare pitfalls.
        var localRevision: Int
        /// Last raw server copy kept when a dirty local note wins a conflict (last-write-wins).
        var serverBackup: NativeAPIClient.NoteDocument?
        /// Notebook group to publish into on the next successful upsert / outbox flush.
        var publishGroupId: String?
        /// True until the first successful server upsert (offline-created notes).
        var awaitingFirstSync: Bool
        /// Server rejected sync with the 200-note limit (HTTP 409) — keep local, stop retrying.
        var syncLimitReached: Bool

        enum CodingKeys: String, CodingKey {
            case dirty, pendingSync, localUpdatedAt, localRevision, serverBackup
            case publishGroupId, awaitingFirstSync, syncLimitReached
        }

        init(
            dirty: Bool,
            pendingSync: Bool,
            localUpdatedAt: String,
            localRevision: Int,
            serverBackup: NativeAPIClient.NoteDocument?,
            publishGroupId: String? = nil,
            awaitingFirstSync: Bool = false,
            syncLimitReached: Bool = false
        ) {
            self.dirty = dirty
            self.pendingSync = pendingSync
            self.localUpdatedAt = localUpdatedAt
            self.localRevision = localRevision
            self.serverBackup = serverBackup
            self.publishGroupId = publishGroupId
            self.awaitingFirstSync = awaitingFirstSync
            self.syncLimitReached = syncLimitReached
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            dirty = try c.decode(Bool.self, forKey: .dirty)
            pendingSync = try c.decode(Bool.self, forKey: .pendingSync)
            localUpdatedAt = try c.decode(String.self, forKey: .localUpdatedAt)
            localRevision = try c.decodeIfPresent(Int.self, forKey: .localRevision) ?? 1
            serverBackup = try c.decodeIfPresent(NativeAPIClient.NoteDocument.self, forKey: .serverBackup)
            publishGroupId = try c.decodeIfPresent(String.self, forKey: .publishGroupId)
            awaitingFirstSync = try c.decodeIfPresent(Bool.self, forKey: .awaitingFirstSync) ?? false
            syncLimitReached = try c.decodeIfPresent(Bool.self, forKey: .syncLimitReached) ?? false
        }
    }

    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("NativeNotes", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        return dir
    }

    private static var notesURL: URL { directory.appendingPathComponent("notes-v1.json") }
    private static var speakersURL: URL { directory.appendingPathComponent("speakers-v1.json") }
    private static var metaURL: URL { directory.appendingPathComponent("notes-meta-v1.json") }

    private static func writeProtected(_ data: Data, to url: URL) {
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    // MARK: - Timestamp helpers (Date compares, not string lexicographic)

    private static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoBasic: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func editTimestamp(from date: Date = Date()) -> String {
        isoFractional.string(from: date)
    }

    /// Parse wire/local `updatedAt` values that may or may not include fractional seconds.
    static func parseUpdatedAt(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let date = isoFractional.date(from: trimmed) { return date }
        if let date = isoBasic.date(from: trimmed) { return date }
        return nil
    }

    static func isUpdatedAt(_ lhs: String, newerThanOrEqual rhs: String) -> Bool {
        switch (parseUpdatedAt(lhs), parseUpdatedAt(rhs)) {
        case let (l?, r?): return l >= r
        default: return lhs >= rhs
        }
    }

    static func isUpdatedAt(_ lhs: String, newerThan rhs: String) -> Bool {
        switch (parseUpdatedAt(lhs), parseUpdatedAt(rhs)) {
        case let (l?, r?): return l > r
        default: return lhs > rhs
        }
    }

    static func maxUpdatedAt(_ a: String, _ b: String) -> String {
        isUpdatedAt(a, newerThanOrEqual: b) ? a : b
    }

    static func saveNotes(_ notes: [NativeAPIClient.NoteDocument]) {
        guard let data = try? JSONEncoder().encode(notes) else { return }
        writeProtected(data, to: notesURL)
    }

    static func loadNotes() -> [NativeAPIClient.NoteDocument] {
        guard let data = try? Data(contentsOf: notesURL),
              let notes = try? JSONDecoder().decode([NativeAPIClient.NoteDocument].self, from: data)
        else { return [] }
        return notes
    }

    static func note(id: String) -> NativeAPIClient.NoteDocument? {
        loadNotes().first(where: { $0.id == id })
    }

    static func upsertNote(_ note: NativeAPIClient.NoteDocument) {
        var notes = loadNotes()
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes[index] = note
        } else {
            notes.insert(note, at: 0)
        }
        notes.sort(by: noteSort)
        saveNotes(notes)
    }

    private static func noteSort(_ lhs: NativeAPIClient.NoteDocument, _ rhs: NativeAPIClient.NoteDocument) -> Bool {
        if lhs.happenedAt != rhs.happenedAt { return lhs.happenedAt > rhs.happenedAt }
        return isUpdatedAt(lhs.updatedAt, newerThan: rhs.updatedAt)
    }

    static func removeNote(id: String) {
        var notes = loadNotes()
        notes.removeAll { $0.id == id }
        saveNotes(notes)
        var meta = loadMeta()
        meta.removeValue(forKey: id)
        saveMeta(meta)
    }

    // MARK: - Sync metadata (dirty / pending)

    static func loadMeta() -> [String: NoteSyncMeta] {
        guard let data = try? Data(contentsOf: metaURL),
              let meta = try? JSONDecoder().decode([String: NoteSyncMeta].self, from: data)
        else { return [:] }
        return meta
    }

    private static func saveMeta(_ meta: [String: NoteSyncMeta]) {
        guard let data = try? JSONEncoder().encode(meta) else { return }
        writeProtected(data, to: metaURL)
    }

    static func syncMeta(for id: String) -> NoteSyncMeta? {
        loadMeta()[id]
    }

    static func isDirtyOrPending(_ id: String) -> Bool {
        guard let meta = loadMeta()[id] else { return false }
        return meta.dirty || meta.pendingSync
    }

    static func hasPendingSync(_ id: String) -> Bool {
        loadMeta()[id]?.pendingSync == true
    }

    /// Note was created locally and has never successfully reached the server.
    static func isAwaitingFirstSync(_ id: String) -> Bool {
        loadMeta()[id]?.awaitingFirstSync == true
    }

    static func publishGroupId(for id: String) -> String? {
        let raw = loadMeta()[id]?.publishGroupId?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw, !raw.isEmpty else { return nil }
        return raw
    }

    static func setPublishGroupId(id: String, groupId: String?) {
        var meta = loadMeta()
        var entry = meta[id] ?? NoteSyncMeta(
            dirty: true,
            pendingSync: true,
            localUpdatedAt: editTimestamp(),
            localRevision: 1,
            serverBackup: nil
        )
        let trimmed = groupId?.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.publishGroupId = (trimmed?.isEmpty == false) ? trimmed : nil
        meta[id] = entry
        saveMeta(meta)
    }

    static func isSyncLimitReached(_ id: String) -> Bool {
        loadMeta()[id]?.syncLimitReached == true
    }

    /// HTTP 409 (200-note limit): keep the local note, stop outbox retries.
    static func markSyncLimitReached(id: String) {
        var meta = loadMeta()
        var entry = meta[id] ?? NoteSyncMeta(
            dirty: true,
            pendingSync: true,
            localUpdatedAt: editTimestamp(),
            localRevision: 1,
            serverBackup: nil
        )
        entry.dirty = true
        entry.pendingSync = true
        entry.syncLimitReached = true
        meta[id] = entry
        saveMeta(meta)
        NativeOutbox.dropJobs(forNoteId: id)
        log.error("Note \(id, privacy: .public) hit 200-note limit (409); kept local, stopped sync retries")
    }

    /// Stamp edit time, bump local revision, mark dirty+pending, write disk, refresh NativeSWR.
    /// Pass `awaitingFirstSync` / `publishGroupId` on local-first create; omit to preserve prior meta.
    @discardableResult
    static func recordLocalEdit(
        _ note: NativeAPIClient.NoteDocument,
        editedAt: Date = Date(),
        publishGroupId: String? = nil,
        awaitingFirstSync: Bool? = nil
    ) -> NativeAPIClient.NoteDocument {
        var next = note
        next.schemaVersion = 1
        let stamp = editTimestamp(from: editedAt)
        next.updatedAt = stamp
        upsertNote(next)
        var meta = loadMeta()
        let previous = meta[next.id]
        let revision = (previous?.localRevision ?? 0) + 1
        let trimmedGroup = (publishGroupId ?? previous?.publishGroupId)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        meta[next.id] = NoteSyncMeta(
            dirty: true,
            pendingSync: true,
            localUpdatedAt: stamp,
            localRevision: revision,
            serverBackup: previous?.serverBackup,
            publishGroupId: (trimmedGroup?.isEmpty == false) ? trimmedGroup : nil,
            awaitingFirstSync: awaitingFirstSync ?? previous?.awaitingFirstSync ?? false,
            syncLimitReached: previous?.syncLimitReached ?? false
        )
        saveMeta(meta)
        NativeSWR.applyLocalNote(next)
        return next
    }

    /// Mark a note as waiting for outbox flush without changing content / updatedAt / revision.
    static func markPendingSync(id: String) {
        var meta = loadMeta()
        var entry = meta[id] ?? NoteSyncMeta(
            dirty: true,
            pendingSync: true,
            localUpdatedAt: editTimestamp(),
            localRevision: 1,
            serverBackup: nil
        )
        entry.pendingSync = true
        entry.dirty = true
        meta[id] = entry
        saveMeta(meta)
    }

    /// Clear dirty/pending after a successful server upsert, but only if no newer local edit landed.
    /// Prefer revision when the caller knows which edit was synced; fall back to Date compare.
    /// Any successful upsert clears `awaitingFirstSync` (the id now exists on the server).
    static func clearDirtyIfNotNewer(
        id: String,
        syncedUpdatedAt: String,
        syncedRevision: Int? = nil
    ) {
        var meta = loadMeta()
        guard var entry = meta[id] else { return }
        entry.awaitingFirstSync = false
        let keepDirty: Bool = {
            if let syncedRevision {
                return entry.localRevision > syncedRevision
            }
            return isUpdatedAt(entry.localUpdatedAt, newerThan: syncedUpdatedAt)
        }()
        if keepDirty {
            entry.pendingSync = true
            entry.dirty = true
            meta[id] = entry
            saveMeta(meta)
            return
        }
        meta.removeValue(forKey: id)
        saveMeta(meta)
    }

    /// Prefer the on-disk owned note when it is dirty/pending or newer than the list/memory row.
    static func preferredNote(over candidate: NativeAPIClient.NoteDocument) -> NativeAPIClient.NoteDocument {
        guard let disk = note(id: candidate.id) else { return candidate }
        if isDirtyOrPending(candidate.id) { return disk }
        if isUpdatedAt(disk.updatedAt, newerThanOrEqual: candidate.updatedAt) { return disk }
        return candidate
    }

    // MARK: - Server merge (never clobber dirty/pending)

    /// Merge a **raw** server list into disk once. Dirty/pending locals win; otherwise newer `updatedAt` wins.
    /// When a dirty local wins, the raw server copy is stored as `serverBackup`.
    @discardableResult
    static func mergeServerNotes(_ serverNotes: [NativeAPIClient.NoteDocument]) -> [NativeAPIClient.NoteDocument] {
        let localNotes = loadNotes()
        var meta = loadMeta()
        var byId: [String: NativeAPIClient.NoteDocument] = [:]
        for note in serverNotes { byId[note.id] = note }

        for local in localNotes {
            let entry = meta[local.id]
            let dirty = entry?.dirty == true || entry?.pendingSync == true
            if dirty {
                if let server = byId[local.id] {
                    // Always keep the raw server payload as a hidden backup while local is dirty.
                    var next = entry ?? NoteSyncMeta(
                        dirty: true,
                        pendingSync: true,
                        localUpdatedAt: local.updatedAt,
                        localRevision: 1,
                        serverBackup: nil,
                        publishGroupId: nil,
                        awaitingFirstSync: true,
                        syncLimitReached: false
                    )
                    if server != local {
                        next.serverBackup = server
                        log.info("Keeping dirty local note \(local.id, privacy: .public); server copy stored as backup")
                    }
                    meta[local.id] = next
                }
                byId[local.id] = local
            } else if let server = byId[local.id] {
                if isUpdatedAt(local.updatedAt, newerThan: server.updatedAt) {
                    byId[local.id] = local
                }
            }
            // Clean local-only notes that vanished from the server are dropped (not in byId).
        }

        // Preserve dirty locals that were never on the server list.
        for local in localNotes where byId[local.id] == nil {
            if meta[local.id]?.dirty == true || meta[local.id]?.pendingSync == true {
                byId[local.id] = local
            }
        }

        let merged = byId.values.sorted(by: noteSort)
        saveNotes(merged)
        saveMeta(meta)
        return merged
    }

    /// Merge a single **raw** server note; returns the document that should be served to callers.
    @discardableResult
    static func mergeServerNote(_ server: NativeAPIClient.NoteDocument) -> NativeAPIClient.NoteDocument {
        let merged = mergeServerNotes([server])
        return note(id: server.id) ?? merged.first(where: { $0.id == server.id }) ?? server
    }

    static func saveSpeakers(_ speakers: [NativeAPIClient.SpeakerDTO]) {
        guard let data = try? JSONEncoder().encode(speakers) else { return }
        writeProtected(data, to: speakersURL)
    }

    /// Merge into the on-device catalog without wiping unrelated speakers.
    /// `getNote` returns only speakers used by that note — replacing the cache
    /// with that subset emptied the picker (TF200 #3).
    @discardableResult
    static func mergeSpeakers(_ speakers: [NativeAPIClient.SpeakerDTO]) -> [NativeAPIClient.SpeakerDTO] {
        var byId: [String: NativeAPIClient.SpeakerDTO] = [:]
        for speaker in loadSpeakers() { byId[speaker.id] = speaker }
        for speaker in speakers { byId[speaker.id] = speaker }
        let merged = byId.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        saveSpeakers(merged)
        return merged
    }

    static func removeSpeaker(id: String) {
        var speakers = loadSpeakers()
        speakers.removeAll { $0.id == id }
        saveSpeakers(speakers)
    }

    static func loadSpeakers() -> [NativeAPIClient.SpeakerDTO] {
        guard let data = try? Data(contentsOf: speakersURL),
              let speakers = try? JSONDecoder().decode([NativeAPIClient.SpeakerDTO].self, from: data)
        else { return [] }
        return speakers
    }

    /// Account switch / logout — owned notes+speakers must not leak across users.
    static func clearAll() {
        try? FileManager.default.removeItem(at: notesURL)
        try? FileManager.default.removeItem(at: speakersURL)
        try? FileManager.default.removeItem(at: metaURL)
    }
}
