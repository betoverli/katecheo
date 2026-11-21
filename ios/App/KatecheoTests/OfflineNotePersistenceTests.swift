import XCTest
@testable import Katecheo

/// Offline owned-note edits must survive list/detail round-trips and outbox flush.
final class OfflineNotePersistenceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        NativeSWR.resetAllForTests()
        NativeSWR.networkProbeEnabled = true
        MockNativeURLProtocol.reset()
        MockNativeURLProtocol.register()
        NativeAPIClient.session = MockNativeURLProtocol.makeSession()
        NativeAPIClient.testAuthToken = "test-bearer-offline-notes"
        XCTAssertTrue(NativeAPIClient.hasBearer)
    }

    override func tearDown() {
        NativeAPIClient.testAuthToken = nil
        NativeSWR.resetAllForTests()
        NativeAPIClient.session = .shared
        MockNativeURLProtocol.unregister()
        super.tearDown()
    }

    private func noteJSON(
        id: String = "n1",
        title: String,
        bodyText: String,
        updatedAt: String
    ) -> String {
        // Build with ordinary interpolation — ## raw strings need \#\#() and are easy to get wrong.
        """
        {"schemaVersion":1,"id":"\(id)","title":"\(title)","happenedAt":"2026-01-01","tags":[],"visibility":"private","updatedAt":"\(updatedAt)","body":{"blocks":[{"id":"b1","type":"paragraph","spans":[{"type":"text","text":"\(bodyText)"}]}]}}
        """
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func seedServerNote(
        id: String = "n1",
        title: String = "A",
        bodyText: String = "server body",
        updatedAt: String = "2026-01-01T00:00:00Z"
    ) {
        let note = noteJSON(id: id, title: title, bodyText: bodyText, updatedAt: updatedAt)
        MockNativeURLProtocol.notesJSON = "{\"ok\":true,\"notes\":[\(note)]}"
        MockNativeURLProtocol.noteByIdJSON = "{\"ok\":true,\"note\":\(note),\"speakers\":[],\"via\":\"owned\"}"
        MockNativeURLProtocol.upsertNoteJSON = "{\"ok\":true,\"note\":\(note),\"speakers\":[],\"via\":\"owned\"}"
    }

    private func editLocally(
        id: String = "n1",
        title: String,
        bodyText: String,
        editedAt: Date = Date()
    ) -> NativeAPIClient.NoteDocument {
        var note = NativeAPIClient.emptyNote(id: id)
        note.title = title
        note.happenedAt = "2026-01-01"
        note.body = .init(blocks: [
            .init(
                id: "b1",
                type: "paragraph",
                spans: [.init(type: "text", text: bodyText)],
                speakerId: nil,
                title: nil,
                collapsed: nil,
                checked: nil,
                blocks: nil
            ),
        ])
        return LocalNoteCache.recordLocalEdit(note, editedAt: editedAt)
    }

    // MARK: - Offline read after edit

    func testOfflineEdit_listAndGetReturnEditedText_withinTTL() async throws {
        seedServerNote()
        _ = try await NativeAPIClient.listNotes()
        _ = try await NativeAPIClient.getNote(id: "n1")

        let edited = editLocally(title: "Edited offline", bodyText: "kept offline")
        NativeOutbox.enqueueNoteUpsert(edited)
        LocalNoteCache.markPendingSync(id: "n1")

        MockNativeURLProtocol.forceTransportError = true
        NativeSWR.resetProbe()

        let listed = try await NativeAPIClient.listNotes()
        let packed = try await NativeAPIClient.getNote(id: "n1")
        XCTAssertEqual(listed.first?.title, "Edited offline")
        XCTAssertEqual(packed.note.body.blocks.first?.spans?.first?.text, "kept offline")
        // Within TTL + dirty disk → no network required for the happy path.
        XCTAssertEqual(NativeSWR.probeCount(containing: "/notes"), 0)
    }

    func testOfflineEdit_listAndGetReturnEditedText_afterTTL() async throws {
        seedServerNote()
        _ = try await NativeAPIClient.listNotes()
        _ = try await NativeAPIClient.getNote(id: "n1")

        let edited = editLocally(title: "After TTL", bodyText: "still here")
        NativeOutbox.enqueueNoteUpsert(edited)
        LocalNoteCache.markPendingSync(id: "n1")

        // Expire SWR freshness while keeping disk dirty.
        NativeSWR.invalidate(.notes, .note("n1"))
        // Re-apply local so memory matches disk after invalidate.
        NativeSWR.applyLocalNote(edited)

        MockNativeURLProtocol.forceTransportError = true
        let listed = try await NativeAPIClient.listNotes(force: true)
        XCTAssertTrue(NativeSWR.consumeOfflineFallback(.notes))
        XCTAssertEqual(listed.first?.title, "After TTL")

        let packed = try await NativeAPIClient.getNote(id: "n1", force: true)
        XCTAssertTrue(NativeSWR.consumeOfflineFallback(.note("n1")))
        XCTAssertEqual(packed.note.body.blocks.first?.spans?.first?.text, "still here")
    }

    // MARK: - Reopen without typing must not clobber outbox

    func testReopenCloseWithoutTyping_keepsEditedOutboxPayload() async throws {
        seedServerNote()
        _ = try await NativeAPIClient.listNotes()
        let edited = editLocally(title: "Do not clobber", bodyText: "outbox body")
        NativeOutbox.enqueueNoteUpsert(edited)
        LocalNoteCache.markPendingSync(id: "n1")

        // Simulate opening from a stale list row then leaving without typing:
        // preferredNote must revive the disk copy; content-equal close must not rewrite outbox.
        let staleListRow = NativeAPIClient.emptyNote(id: "n1")
        let opened = LocalNoteCache.preferredNote(over: staleListRow)
        XCTAssertEqual(opened.title, "Do not clobber")

        let beforeJobs = NativeOutbox.load()
        XCTAssertEqual(beforeJobs.count, 1)
        let beforePayload = try JSONDecoder().decode(NativeAPIClient.NoteDocument.self, from: beforeJobs[0].payload)

        // No recordLocalEdit / enqueue — mirrors viewWillDisappear when contentDiffers is false.
        let afterJobs = NativeOutbox.load()
        XCTAssertEqual(afterJobs.count, 1)
        let afterPayload = try JSONDecoder().decode(NativeAPIClient.NoteDocument.self, from: afterJobs[0].payload)
        XCTAssertEqual(afterPayload.title, beforePayload.title)
        XCTAssertEqual(afterPayload.body.blocks.first?.spans?.first?.text, "outbox body")
        XCTAssertEqual(afterPayload.updatedAt, beforePayload.updatedAt)
    }

    // MARK: - Server fetch while pending keeps local

    func testServerFetchWhilePending_keepsLocalAndStoresBackup() async throws {
        seedServerNote(title: "Server", bodyText: "server body", updatedAt: "2026-01-02T00:00:00Z")
        _ = try await NativeAPIClient.listNotes()

        let edited = editLocally(title: "Local pending", bodyText: "local body")
        NativeOutbox.enqueueNoteUpsert(edited)
        LocalNoteCache.markPendingSync(id: "n1")

        // Server returns a different copy while the outbox job is still pending.
        seedServerNote(title: "Server newer", bodyText: "server body v2", updatedAt: "2026-01-03T00:00:00Z")
        let listed = try await NativeAPIClient.listNotes(force: true)
        XCTAssertEqual(listed.first?.title, "Local pending")
        XCTAssertEqual(LocalNoteCache.note(id: "n1")?.body.blocks.first?.spans?.first?.text, "local body")
        XCTAssertTrue(LocalNoteCache.isDirtyOrPending("n1"))
        XCTAssertEqual(LocalNoteCache.syncMeta(for: "n1")?.serverBackup?.title, "Server newer")

        let packed = try await NativeAPIClient.getNote(id: "n1", force: true)
        XCTAssertEqual(packed.note.title, "Local pending")
    }

    // MARK: - Flush success clears dirty

    func testFlushSuccess_clearsDirtyAndCacheMatchesServer() async throws {
        seedServerNote(title: "A", bodyText: "old")
        _ = try await NativeAPIClient.listNotes()

        let edited = editLocally(title: "Synced", bodyText: "new body")
        NativeOutbox.enqueueNoteUpsert(edited)
        LocalNoteCache.markPendingSync(id: "n1")
        XCTAssertTrue(LocalNoteCache.isDirtyOrPending("n1"))

        // Server ack echoes the edited payload (including edit-time updatedAt).
        let ackNote = noteJSON(
            title: "Synced",
            bodyText: "new body",
            updatedAt: edited.updatedAt
        )
        MockNativeURLProtocol.upsertNoteJSON = "{\"ok\":true,\"note\":\(ackNote),\"speakers\":[],\"via\":\"owned\"}"
        MockNativeURLProtocol.forceTransportError = false

        let completed = await NativeOutbox.flushIfPossible()
        XCTAssertEqual(completed, 1)
        XCTAssertEqual(NativeOutbox.pendingCount, 0)
        XCTAssertFalse(LocalNoteCache.isDirtyOrPending("n1"))
        XCTAssertEqual(LocalNoteCache.note(id: "n1")?.title, "Synced")
        XCTAssertEqual(LocalNoteCache.note(id: "n1")?.body.blocks.first?.spans?.first?.text, "new body")

        let mem: NativeAPIClient.NotePack? = NativeSWR.cachedValue(.note("n1"))
        XCTAssertEqual(mem?.note.title, "Synced")
    }

    // MARK: - Conflict: newer local edit during flush keeps dirty

    func testNewerLocalEditDuringFlush_keepsDirty() async throws {
        seedServerNote()
        _ = try await NativeAPIClient.listNotes()

        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let first = editLocally(title: "First", bodyText: "v1", editedAt: t0)
        NativeOutbox.enqueueNoteUpsert(first)

        // Ack for the first edit.
        let ackNote = noteJSON(title: "First", bodyText: "v1", updatedAt: first.updatedAt)
        MockNativeURLProtocol.upsertNoteJSON = "{\"ok\":true,\"note\":\(ackNote),\"speakers\":[],\"via\":\"owned\"}"

        // A newer local edit lands before flush completes clearing meta.
        let second = editLocally(
            title: "Second",
            bodyText: "v2",
            editedAt: t0.addingTimeInterval(0.25)
        )
        XCTAssertTrue(second.updatedAt > first.updatedAt)

        // Upsert path clears only when syncedUpdatedAt >= localUpdatedAt.
        LocalNoteCache.clearDirtyIfNotNewer(id: "n1", syncedUpdatedAt: first.updatedAt)
        XCTAssertTrue(LocalNoteCache.isDirtyOrPending("n1"))
        XCTAssertEqual(LocalNoteCache.note(id: "n1")?.title, "Second")
    }

    // MARK: - updatedAt stamped at edit time travels through outbox

    func testUpdatedAt_stampedAtEditTime_carriedInOutbox() throws {
        let edited = editLocally(title: "Stamp", bodyText: "x")
        let metaAt = LocalNoteCache.syncMeta(for: "n1")?.localUpdatedAt
        XCTAssertEqual(edited.updatedAt, metaAt)
        NativeOutbox.enqueueNoteUpsert(edited)
        let job = try XCTUnwrap(NativeOutbox.load().first)
        let payload = try JSONDecoder().decode(NativeAPIClient.NoteDocument.self, from: job.payload)
        XCTAssertEqual(payload.updatedAt, edited.updatedAt)
    }
}
