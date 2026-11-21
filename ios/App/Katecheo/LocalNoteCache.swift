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
        /// ISO-8601 edit time stamped when the user changed the note locally.
        var localUpdatedAt: String
        /// Last server copy kept when a dirty local note wins a conflict (last-write-wins).
        var serverBackup: NativeAPIClient.NoteDocument?
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
        notes.sort { lhs, rhs in
            if lhs.happenedAt != rhs.happenedAt { return lhs.happenedAt > rhs.happenedAt }
            return lhs.updatedAt > rhs.updatedAt
        }
        saveNotes(notes)
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

    /// Stamp edit time, mark dirty+pending, write disk, and refresh NativeSWR memory.
    @discardableResult
    static func recordLocalEdit(_ note: NativeAPIClient.NoteDocument, editedAt: Date = Date()) -> NativeAPIClient.NoteDocument {
        var next = note
        next.schemaVersion = 1
        let stamp = ISO8601DateFormatter().string(from: editedAt)
        next.updatedAt = stamp
        upsertNote(next)
        var meta = loadMeta()
        var entry = meta[next.id] ?? NoteSyncMeta(
            dirty: true,
            pendingSync: true,
            localUpdatedAt: stamp,
            serverBackup: nil
        )
        entry.dirty = true
        entry.pendingSync = true
        entry.localUpdatedAt = stamp
        meta[next.id] = entry
        saveMeta(meta)
        NativeSWR.applyLocalNote(next)
        return next
    }

    /// Mark a note as waiting for outbox flush without changing content / updatedAt.
    static func markPendingSync(id: String) {
        var meta = loadMeta()
        var entry = meta[id] ?? NoteSyncMeta(
            dirty: true,
            pendingSync: true,
            localUpdatedAt: ISO8601DateFormatter().string(from: Date()),
            serverBackup: nil
        )
        entry.pendingSync = true
        entry.dirty = true
        meta[id] = entry
        saveMeta(meta)
    }

    /// Clear dirty/pending after a successful server upsert, but only if no newer local edit landed.
    static func clearDirtyIfNotNewer(id: String, syncedUpdatedAt: String) {
        var meta = loadMeta()
        guard var entry = meta[id] else { return }
        if entry.localUpdatedAt > syncedUpdatedAt {
            // A newer local edit arrived while the upsert was in flight — keep dirty.
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
        if disk.updatedAt >= candidate.updatedAt { return disk }
        return candidate
    }

    // MARK: - Server merge (never clobber dirty/pending)

    /// Merge a server list into disk: dirty/pending locals win; otherwise newer `updatedAt` wins.
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
                if let server = byId[local.id], server != local {
                    // Last write wins by edit time — keep local, stash server as hidden backup.
                    if local.updatedAt >= server.updatedAt {
                        var next = entry ?? NoteSyncMeta(
                            dirty: true,
                            pendingSync: true,
                            localUpdatedAt: local.updatedAt,
                            serverBackup: nil
                        )
                        next.serverBackup = server
                        meta[local.id] = next
                        log.info("Keeping dirty local note \(local.id, privacy: .public); server copy stored as backup")
                    } else {
                        // Server is newer than local edit stamp — still keep dirty local per product rule
                        // (local edits must not be silently discarded while pending).
                        var next = entry ?? NoteSyncMeta(
                            dirty: true,
                            pendingSync: true,
                            localUpdatedAt: local.updatedAt,
                            serverBackup: nil
                        )
                        next.serverBackup = server
                        meta[local.id] = next
                        log.info("Conflict: keeping dirty local \(local.id, privacy: .public) over newer server")
                    }
                }
                byId[local.id] = local
            } else if let server = byId[local.id] {
                if local.updatedAt > server.updatedAt {
                    byId[local.id] = local
                }
            } else if entry?.pendingSync == true || entry?.dirty == true {
                byId[local.id] = local
            }
            // Local-only notes without dirty/pending that vanished from the server are dropped.
        }

        // Preserve dirty locals that were never on the server list.
        for local in localNotes where byId[local.id] == nil {
            if meta[local.id]?.dirty == true || meta[local.id]?.pendingSync == true {
                byId[local.id] = local
            }
        }

        let merged = byId.values.sorted { lhs, rhs in
            if lhs.happenedAt != rhs.happenedAt { return lhs.happenedAt > rhs.happenedAt }
            return lhs.updatedAt > rhs.updatedAt
        }
        saveNotes(merged)
        saveMeta(meta)
        return merged
    }

    /// Merge a single server note; returns the document that should be served to callers.
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
