import Foundation
import os.log

/// Persistent offline outbox for native `/api/native/v1` mutations.
/// Jobs survive relaunch; flush uses exponential backoff and never deletes server rows
/// for jobs that fail — failed jobs stay queued for retry.
enum NativeOutbox {
    private static let log = Logger(subsystem: "app.katecheo", category: "NativeOutbox")

    enum JobType: String, Codable {
        case noteUpsert
        case noteDelete
        case speakerUpsert
        case speakerDelete
        case prefsPatch
        case collectionUpsert
    }

    struct Job: Codable, Equatable {
        var id: String
        var type: JobType
        var payload: Data
        var attempts: Int
        var nextAttemptAt: Date
        var createdAt: Date
        /// Account that enqueued the job. Nil on legacy jobs decoded from disk.
        var accountId: String? = nil
    }

    /// Wire envelope for note upserts so `publishGroupId` survives flush after relaunch.
    /// Legacy jobs encoded a bare `NoteDocument` — decode both shapes.
    struct NoteUpsertEnvelope: Codable, Equatable {
        var note: NativeAPIClient.NoteDocument
        var publishGroupId: String?
    }

    private static let fileName = "native-outbox-v1.json"
    private static let maxAttemptsVisible = 12
    private static var flushing = false

    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("NativeNotes", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(fileName)
    }

    static func load() -> [Job] {
        guard let data = try? Data(contentsOf: fileURL),
              let jobs = try? JSONDecoder().decode([Job].self, from: data)
        else { return [] }
        return jobs
    }

    private static func save(_ jobs: [Job]) {
        guard let data = try? JSONEncoder().encode(jobs) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    static var pendingCount: Int { load().count }

    /// Drop queued jobs on logout / account switch so we never flush another user's mutations.
    static func clearAll() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Enqueue (deduped)

    static func enqueueNoteUpsert(
        _ note: NativeAPIClient.NoteDocument,
        publishToGroupId: String? = nil
    ) {
        if LocalNoteCache.isSyncLimitReached(note.id) { return }
        let groupId = publishToGroupId ?? LocalNoteCache.publishGroupId(for: note.id)
        if let groupId {
            LocalNoteCache.setPublishGroupId(id: note.id, groupId: groupId)
        }
        let envelope = NoteUpsertEnvelope(note: note, publishGroupId: groupId)
        guard let payload = try? JSONEncoder().encode(envelope) else { return }
        mutate { jobs in
            jobs.removeAll {
                ($0.type == .noteUpsert || $0.type == .noteDelete) && noteId(in: $0) == note.id
            }
            jobs.append(makeJob(type: .noteUpsert, payload: payload))
        }
    }

    static func enqueueNoteDelete(id: String) {
        // Never-synced local notes must not enqueue DELETE (server 404 would retry forever).
        if LocalNoteCache.isAwaitingFirstSync(id) {
            dropJobs(forNoteId: id)
            return
        }
        let payload = Data(id.utf8)
        mutate { jobs in
            jobs.removeAll {
                ($0.type == .noteUpsert || $0.type == .noteDelete) && noteId(in: $0) == id
            }
            jobs.append(makeJob(type: .noteDelete, payload: payload))
        }
    }

    /// Drop pending upsert/delete jobs for a note (local-only discard, sync-limit, etc.).
    static func dropJobs(forNoteId id: String) {
        mutate { jobs in
            jobs.removeAll {
                ($0.type == .noteUpsert || $0.type == .noteDelete) && noteId(in: $0) == id
            }
        }
    }

    static func enqueueSpeakerUpsert(_ speaker: NativeAPIClient.SpeakerDTO) {
        guard let payload = try? JSONEncoder().encode(speaker) else { return }
        mutate { jobs in
            jobs.removeAll {
                ($0.type == .speakerUpsert || $0.type == .speakerDelete) && speakerId(in: $0) == speaker.id
            }
            jobs.append(makeJob(type: .speakerUpsert, payload: payload))
        }
    }

    static func enqueueSpeakerDelete(id: String) {
        let payload = Data(id.utf8)
        mutate { jobs in
            jobs.removeAll {
                ($0.type == .speakerUpsert || $0.type == .speakerDelete) && speakerId(in: $0) == id
            }
            jobs.append(makeJob(type: .speakerDelete, payload: payload))
        }
    }

    static func enqueuePrefsPatch(_ patch: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(patch),
              let payload = try? JSONSerialization.data(withJSONObject: patch)
        else { return }
        mutate { jobs in
            jobs.removeAll { $0.type == .prefsPatch }
            jobs.append(makeJob(type: .prefsPatch, payload: payload))
        }
    }

    static func enqueueCollectionUpsert(_ collection: NativeAPIClient.UserCollectionDTO) {
        guard let payload = try? JSONEncoder().encode(collection) else { return }
        mutate { jobs in
            jobs.removeAll {
                $0.type == .collectionUpsert && collectionId(in: $0) == collection.id
            }
            jobs.append(makeJob(type: .collectionUpsert, payload: payload))
        }
    }

    /// Import path: enqueue without coalescing deletes (import never enqueues deletes).
    static func enqueueImported(jobs incoming: [Job]) {
        guard !incoming.isEmpty else { return }
        mutate { jobs in
            for job in incoming {
                switch job.type {
                case .noteUpsert:
                    if let id = noteId(in: job) {
                        jobs.removeAll { ($0.type == .noteUpsert || $0.type == .noteDelete) && noteId(in: $0) == id }
                    }
                case .speakerUpsert:
                    if let id = speakerId(in: job) {
                        jobs.removeAll { ($0.type == .speakerUpsert || $0.type == .speakerDelete) && speakerId(in: $0) == id }
                    }
                case .prefsPatch:
                    jobs.removeAll { $0.type == .prefsPatch }
                case .collectionUpsert:
                    if let id = collectionId(in: job) {
                        jobs.removeAll { $0.type == .collectionUpsert && collectionId(in: $0) == id }
                    }
                case .noteDelete, .speakerDelete:
                    continue // import never queues deletes
                }
                if job.type != .noteDelete && job.type != .speakerDelete {
                    jobs.append(job)
                }
            }
            if jobs.count > 120 {
                jobs = Array(jobs.suffix(120))
            }
        }
    }

    static func makeJob(type: JobType, payload: Data, id: String = UUID().uuidString) -> Job {
        Job(
            id: id,
            type: type,
            payload: payload,
            attempts: 0,
            nextAttemptAt: Date(),
            createdAt: Date(),
            accountId: LocalSessionCache.loadMe()?.id
        )
    }

    // MARK: - Flush

    @discardableResult
    static func flushIfPossible() async -> Int {
        guard !flushing else { return 0 }
        guard NativeAPIClient.hasBearer else { return 0 }
        flushing = true
        defer { flushing = false }

        var jobs = load()
        guard !jobs.isEmpty else { return 0 }

        // Drop jobs stamped for another account (or stamped while we have no me cache).
        // Legacy nil-accountId jobs still flush under the current bearer session.
        let currentAccountId = LocalSessionCache.loadMe()?.id
        let beforeFilter = jobs.count
        jobs = jobs.filter { job in
            guard let jobAccountId = job.accountId else { return true }
            guard let currentAccountId else { return false }
            return jobAccountId == currentAccountId
        }
        if jobs.count != beforeFilter {
            save(jobs)
        }
        guard !jobs.isEmpty else { return 0 }

        let now = Date()
        var remaining: [Job] = []
        var completed = 0
        var index = 0

        while index < jobs.count {
            var job = jobs[index]
            index += 1
            if job.nextAttemptAt > now {
                remaining.append(job)
                continue
            }
            do {
                try await perform(job)
                completed += 1
            } catch NativeAPIClient.APIError.unauthorized {
                NativeAPIClient.handleUnauthorized()
                remaining.append(job)
                if index < jobs.count {
                    remaining.append(contentsOf: jobs[index...])
                }
                break
            } catch {
                job.attempts += 1
                let exp = min(job.attempts, 6)
                let delay = pow(2.0, Double(exp)) // 2…64s
                let jitter = Double.random(in: 0...0.35) * delay
                job.nextAttemptAt = Date().addingTimeInterval(delay + jitter)
                if job.attempts >= maxAttemptsVisible {
                    // Keep retrying on a longer cadence rather than dropping user data.
                    job.nextAttemptAt = Date().addingTimeInterval(900)
                }
                remaining.append(job)
            }
        }
        save(remaining)
        if completed > 0 {
            NotificationCenter.default.post(name: .nativeOutboxDidFlush, object: completed)
        }
        return completed
    }

    private static func perform(_ job: Job) async throws {
        switch job.type {
        case .noteUpsert:
            let (note, envelopeGroupId) = try decodeNoteUpsert(job.payload)
            let groupId = envelopeGroupId ?? LocalNoteCache.publishGroupId(for: note.id)
            do {
                _ = try await NativeAPIClient.upsertNote(note, publishToGroupId: groupId)
            } catch NativeAPIClient.APIError.http(let code, _) where code == 409 {
                // 200-note limit — keep local, do not retry forever.
                LocalNoteCache.markSyncLimitReached(id: note.id)
                log.error("Outbox noteUpsert \(note.id, privacy: .public) stopped after HTTP 409")
            }
        case .noteDelete:
            let id = String(decoding: job.payload, as: UTF8.self)
            do {
                try await NativeAPIClient.deleteNote(id: id)
            } catch NativeAPIClient.APIError.http(let code, _) where code == 404 {
                // Already gone on the server — treat as success so we don't retry forever.
                LocalNoteCache.removeNote(id: id)
                NativeSWR.invalidateNotesSubtree(noteId: id)
            }
        case .speakerUpsert:
            let speaker = try JSONDecoder().decode(NativeAPIClient.SpeakerDTO.self, from: job.payload)
            try await NativeAPIClient.upsertSpeaker(speaker)
        case .speakerDelete:
            let id = String(decoding: job.payload, as: UTF8.self)
            try await NativeAPIClient.deleteSpeaker(id: id)
        case .prefsPatch:
            let obj = try JSONSerialization.jsonObject(with: job.payload)
            guard let patch = obj as? [String: Any] else { throw NativeAPIClient.APIError.decoding }
            _ = try await NativeAPIClient.patchPrefs(patch)
        case .collectionUpsert:
            let collection = try JSONDecoder().decode(NativeAPIClient.UserCollectionDTO.self, from: job.payload)
            _ = try await NativeAPIClient.upsertMyCollection(collection)
        }
    }

    // MARK: - Helpers

    private static func mutate(_ body: (inout [Job]) -> Void) {
        var jobs = load()
        body(&jobs)
        if jobs.count > 120 { jobs = Array(jobs.suffix(120)) }
        save(jobs)
    }

    static func decodeNoteUpsert(_ data: Data) throws -> (NativeAPIClient.NoteDocument, String?) {
        if let envelope = try? JSONDecoder().decode(NoteUpsertEnvelope.self, from: data) {
            return (envelope.note, envelope.publishGroupId)
        }
        let note = try JSONDecoder().decode(NativeAPIClient.NoteDocument.self, from: data)
        return (note, nil)
    }

    private static func noteId(in job: Job) -> String? {
        if job.type == .noteDelete { return String(decoding: job.payload, as: UTF8.self) }
        if let (note, _) = try? decodeNoteUpsert(job.payload) { return note.id }
        return nil
    }

    private static func speakerId(in job: Job) -> String? {
        if job.type == .speakerDelete { return String(decoding: job.payload, as: UTF8.self) }
        guard let speaker = try? JSONDecoder().decode(NativeAPIClient.SpeakerDTO.self, from: job.payload) else { return nil }
        return speaker.id
    }

    private static func collectionId(in job: Job) -> String? {
        guard let collection = try? JSONDecoder().decode(NativeAPIClient.UserCollectionDTO.self, from: job.payload) else { return nil }
        return collection.id
    }
}

extension Notification.Name {
    static let nativeOutboxDidFlush = Notification.Name("katecheo.nativeOutboxDidFlush")
    static let nativeSessionDidExpire = Notification.Name("katecheo.nativeSessionDidExpire")
}
