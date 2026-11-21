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
        XCTAssertTrue(NativeAPIClient.hasBearer, "outbox flush requires bearer")
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
        // Ordinary interpolation — ## raw strings need \#\#() and are easy to get wrong.
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

        let staleListRow = NativeAPIClient.emptyNote(id: "n1")
        let opened = LocalNoteCache.preferredNote(over: staleListRow)
        XCTAssertEqual(opened.title, "Do not clobber")

        let beforeJobs = NativeOutbox.load()
        XCTAssertEqual(beforeJobs.count, 1)
        let (beforePayload, _) = try NativeOutbox.decodeNoteUpsert(beforeJobs[0].payload)

        let afterJobs = NativeOutbox.load()
        XCTAssertEqual(afterJobs.count, 1)
        let (afterPayload, _) = try NativeOutbox.decodeNoteUpsert(afterJobs[0].payload)
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
        XCTAssertEqual(
            LocalNoteCache.syncMeta(for: "n1")?.serverBackup?.title,
            "Server newer",
            "raw server copy must be stored as backup on the single merge pass"
        )

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
        XCTAssertEqual(NativeOutbox.pendingCount, 1)

        // Server ack echoes the edited payload (including edit-time updatedAt with fractional seconds).
        let ackNote = noteJSON(
            title: "Synced",
            bodyText: "new body",
            updatedAt: edited.updatedAt
        )
        MockNativeURLProtocol.upsertNoteJSON = "{\"ok\":true,\"note\":\(ackNote),\"speakers\":[],\"via\":\"owned\"}"
        MockNativeURLProtocol.forceTransportError = false
        // Ensure the outbox session is the mock (same as NativeAPIClient.session).
        NativeAPIClient.session = MockNativeURLProtocol.makeSession()

        let completed = await NativeOutbox.flushIfPossible()
        XCTAssertFalse(MockNativeURLProtocol.requestBodies().isEmpty, "outbox upsert must hit the mock POST /notes")
        XCTAssertEqual(completed, 1, "flush should complete the noteUpsert job")
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
        let firstRevision = try XCTUnwrap(LocalNoteCache.syncMeta(for: "n1")?.localRevision)
        NativeOutbox.enqueueNoteUpsert(first)

        // Same wall-clock second would collide without fractional seconds / revision.
        let second = editLocally(
            title: "Second",
            bodyText: "v2",
            editedAt: t0.addingTimeInterval(0.001)
        )
        let secondRevision = try XCTUnwrap(LocalNoteCache.syncMeta(for: "n1")?.localRevision)
        XCTAssertGreaterThan(secondRevision, firstRevision)
        XCTAssertTrue(LocalNoteCache.isUpdatedAt(second.updatedAt, newerThan: first.updatedAt))

        // Upsert path clears only when the synced revision covers the latest local edit.
        LocalNoteCache.clearDirtyIfNotNewer(
            id: "n1",
            syncedUpdatedAt: first.updatedAt,
            syncedRevision: firstRevision
        )
        XCTAssertTrue(LocalNoteCache.isDirtyOrPending("n1"))
        XCTAssertEqual(LocalNoteCache.note(id: "n1")?.title, "Second")
    }

    // MARK: - updatedAt stamped at edit time travels through outbox

    func testUpdatedAt_stampedAtEditTime_carriedInOutbox() throws {
        let edited = editLocally(title: "Stamp", bodyText: "x")
        let metaAt = LocalNoteCache.syncMeta(for: "n1")?.localUpdatedAt
        XCTAssertEqual(edited.updatedAt, metaAt)
        XCTAssertNotNil(LocalNoteCache.parseUpdatedAt(edited.updatedAt), "fractional ISO8601 must parse")
        NativeOutbox.enqueueNoteUpsert(edited)
        let job = try XCTUnwrap(NativeOutbox.load().first)
        let (payload, _) = try NativeOutbox.decodeNoteUpsert(job.payload)
        XCTAssertEqual(payload.updatedAt, edited.updatedAt)
    }

    func testParseUpdatedAt_acceptsFractionalAndBasic() {
        XCTAssertNotNil(LocalNoteCache.parseUpdatedAt("2026-01-01T00:00:00.123Z"))
        XCTAssertNotNil(LocalNoteCache.parseUpdatedAt("2026-01-01T00:00:00Z"))
        XCTAssertTrue(
            LocalNoteCache.isUpdatedAt("2026-01-01T00:00:00.200Z", newerThan: "2026-01-01T00:00:00.100Z")
        )
    }

    // MARK: - Offline create (local-first)

    func testCreateOffline_opensFromDiskAndSurvivesReload() throws {
        let draft = NativeAPIClient.emptyNote()
        let created = LocalNoteCache.recordLocalEdit(draft, awaitingFirstSync: true)
        XCTAssertEqual(created.id, draft.id)
        XCTAssertTrue(LocalNoteCache.isAwaitingFirstSync(created.id))
        XCTAssertTrue(LocalNoteCache.isDirtyOrPending(created.id))
        XCTAssertEqual(LocalNoteCache.note(id: created.id)?.id, created.id)

        // Simulated relaunch: prefer disk over a stale list row with the same id.
        let stale = NativeAPIClient.emptyNote(id: created.id)
        let reopened = LocalNoteCache.preferredNote(over: stale)
        XCTAssertEqual(reopened.id, created.id)
        XCTAssertEqual(reopened.updatedAt, created.updatedAt)
        XCTAssertTrue(LocalNoteCache.isAwaitingFirstSync(reopened.id))
    }

    func testCreateOffline_thenOnline_singleUpsertNoDuplicate() async throws {
        let draft = NativeAPIClient.emptyNote()
        let created = LocalNoteCache.recordLocalEdit(draft, awaitingFirstSync: true)
        NativeOutbox.enqueueNoteUpsert(created)
        XCTAssertEqual(NativeOutbox.pendingCount, 1)

        let ack = noteJSON(
            id: created.id,
            title: created.title,
            bodyText: "",
            updatedAt: created.updatedAt
        )
        MockNativeURLProtocol.upsertNoteJSON = "{\"ok\":true,\"note\":\(ack),\"speakers\":[],\"via\":\"owned\"}"
        MockNativeURLProtocol.notesJSON = "{\"ok\":true,\"notes\":[\(ack)]}"
        MockNativeURLProtocol.forceTransportError = false

        let completed = await NativeOutbox.flushIfPossible()
        XCTAssertEqual(completed, 1)
        XCTAssertEqual(NativeOutbox.pendingCount, 0)
        XCTAssertEqual(MockNativeURLProtocol.requestBodies().count, 1)
        XCTAssertEqual(MockNativeURLProtocol.requestBodies().first?["id"] as? String, created.id)
        XCTAssertFalse(LocalNoteCache.isAwaitingFirstSync(created.id))
        XCTAssertFalse(LocalNoteCache.isDirtyOrPending(created.id))

        // List merge must not resurrect a duplicate id.
        let listed = try await NativeAPIClient.listNotes(force: true)
        XCTAssertEqual(listed.filter { $0.id == created.id }.count, 1)
    }

    func testDeleteBeforeSync_dropsUpsertAndDoesNotResurrect() async throws {
        let created = LocalNoteCache.recordLocalEdit(
            NativeAPIClient.emptyNote(),
            awaitingFirstSync: true
        )
        NativeOutbox.enqueueNoteUpsert(created)
        XCTAssertEqual(NativeOutbox.pendingCount, 1)

        // While still awaiting first sync: DELETE must drop the upsert and not enqueue.
        NativeOutbox.enqueueNoteDelete(id: created.id)
        XCTAssertEqual(NativeOutbox.pendingCount, 0)
        XCTAssertTrue(LocalNoteCache.isAwaitingFirstSync(created.id))

        NativeAPIClient.discardLocalOnlyNote(id: created.id)
        XCTAssertNil(LocalNoteCache.note(id: created.id))
        XCTAssertEqual(NativeOutbox.pendingCount, 0)
        XCTAssertFalse(LocalNoteCache.isAwaitingFirstSync(created.id))

        MockNativeURLProtocol.notesJSON = "{\"ok\":true,\"notes\":[]}"
        let listed = try await NativeAPIClient.listNotes(force: true)
        XCTAssertFalse(listed.contains { $0.id == created.id })
    }

    func testDeleteOutbox_treats404AsSuccess() async throws {
        let id = "never-on-server"
        NativeOutbox.enqueueNoteDelete(id: id)
        XCTAssertEqual(NativeOutbox.pendingCount, 1)
        // Mock DELETE /notes/{id} with no fixture → 404.
        MockNativeURLProtocol.forceTransportError = false
        let completed = await NativeOutbox.flushIfPossible()
        XCTAssertEqual(completed, 1)
        XCTAssertEqual(NativeOutbox.pendingCount, 0)
    }

    func testCreateInGroup_survivesListRefreshAndPublishesOnFlush() async throws {
        let userId = "acct-offline-create"
        let groupId = "g-offline-1"
        LocalSessionCache.saveMe(
            NativeAPIClient.MeDTO(
                id: userId,
                email: "a@b.c",
                displayName: "Ana",
                prefs: NativeAPIClient.PrefsDTO(
                    locale: "pt", copyLocale: "pt", appId: "youversion", translationId: "nvi-pt",
                    preferNative: true, copyFormat: "default", citeBook: "abbr", citeSep: ":",
                    booksCompact: false, theme: "system", activePlans: nil, planProgress: nil,
                    avatarId: "", avatarUrl: "", handle: "ana", firstName: "Ana", lastName: "", profileEmail: "a@b.c"
                ),
                notify: NativeAPIClient.NotifyPrefsDTO(
                    reading: true, friends: true, shares: true, groups: true, apnsDevices: 0
                )
            )
        )

        let created = LocalNoteCache.recordLocalEdit(
            NativeAPIClient.emptyNote(),
            publishGroupId: groupId,
            awaitingFirstSync: true
        )
        NativeAPIClient.rememberPublishedNote(created, inGroupId: groupId)
        NativeOutbox.enqueueNoteUpsert(created, publishToGroupId: groupId)
        XCTAssertEqual(LocalNoteCache.publishGroupId(for: created.id), groupId)

        // Full remote list without the local note must still keep it.
        MockNativeURLProtocol.groupNotesJSON = ##"{"ok":true,"notes":[],"incremental":false}"##
        MockNativeURLProtocol.groupNotesStatus = 200
        let cards = try await NativeAPIClient.listGroupNotes(groupId: groupId, force: true)
        XCTAssertTrue(cards.contains { $0.note.id == created.id })

        let ack = noteJSON(
            id: created.id,
            title: created.title,
            bodyText: "",
            updatedAt: created.updatedAt
        )
        MockNativeURLProtocol.upsertNoteJSON = "{\"ok\":true,\"note\":\(ack),\"speakers\":[],\"via\":\"owned\"}"
        MockNativeURLProtocol.publishGroupNoteJSON = ##"{"ok":true}"##
        MockNativeURLProtocol.forceTransportError = false
        let completed = await NativeOutbox.flushIfPossible()
        XCTAssertEqual(completed, 1)
        XCTAssertEqual(NativeOutbox.pendingCount, 0)
        let bodies = MockNativeURLProtocol.requestBodies()
        XCTAssertTrue(bodies.contains { ($0["id"] as? String) == created.id && ($0["groupId"] as? String) == groupId })
        XCTAssertFalse(LocalNoteCache.isAwaitingFirstSync(created.id))
    }

    func testCreatePersistsAcrossCacheReload() throws {
        let created = LocalNoteCache.recordLocalEdit(
            NativeAPIClient.emptyNote(),
            publishGroupId: "g1",
            awaitingFirstSync: true
        )
        let id = created.id
        // Re-read meta/notes from disk without going through in-memory helpers' assumptions.
        let disk = try XCTUnwrap(LocalNoteCache.note(id: id))
        let meta = try XCTUnwrap(LocalNoteCache.syncMeta(for: id))
        XCTAssertEqual(disk.id, id)
        XCTAssertTrue(meta.awaitingFirstSync)
        XCTAssertEqual(meta.publishGroupId, "g1")
        XCTAssertTrue(meta.dirty)
        XCTAssertTrue(meta.pendingSync)
    }

    func testSyncLimit409_keepsLocalAndStopsRetries() async throws {
        let created = LocalNoteCache.recordLocalEdit(
            NativeAPIClient.emptyNote(),
            awaitingFirstSync: true
        )
        NativeOutbox.enqueueNoteUpsert(created)
        XCTAssertEqual(NativeOutbox.pendingCount, 1)
        MockNativeURLProtocol.upsertNoteStatus = 409
        MockNativeURLProtocol.upsertNoteJSON = ##"{"ok":false,"error":"note_limit"}"##
        MockNativeURLProtocol.forceTransportError = false

        let completed = await NativeOutbox.flushIfPossible()
        XCTAssertEqual(completed, 1, "409 completes the job so it does not retry forever")
        XCTAssertEqual(NativeOutbox.pendingCount, 0)
        XCTAssertTrue(LocalNoteCache.isSyncLimitReached(created.id))
        XCTAssertNotNil(LocalNoteCache.note(id: created.id), "note stays local after 409")
        NativeOutbox.enqueueNoteUpsert(created)
        XCTAssertEqual(NativeOutbox.pendingCount, 0, "sync-limit notes must not re-enqueue")
    }

    func testGetNote404_fallsBackToDirtyDisk() async throws {
        let created = LocalNoteCache.recordLocalEdit(
            NativeAPIClient.emptyNote(),
            awaitingFirstSync: true
        )
        MockNativeURLProtocol.noteByIdJSON = nil // GET → 404
        let packed = try await NativeAPIClient.getNote(id: created.id, force: true)
        XCTAssertEqual(packed.note.id, created.id)
        XCTAssertEqual(packed.via, "owned")
    }

    // MARK: - Caderno list flicker: mergeServerNote must not truncate siblings

    private func makeNote(
        id: String,
        title: String,
        happenedAt: String,
        updatedAt: String,
        bodyText: String = "body"
    ) -> NativeAPIClient.NoteDocument {
        var note = NativeAPIClient.emptyNote(id: id)
        note.title = title
        note.happenedAt = happenedAt
        note.updatedAt = updatedAt
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
        return note
    }

    private func seedThreeNotesOnDisk() -> [NativeAPIClient.NoteDocument] {
        let notes = [
            makeNote(id: "n1", title: "One", happenedAt: "2026-01-03", updatedAt: "2026-01-03T10:00:00Z"),
            makeNote(id: "n2", title: "Two", happenedAt: "2026-01-02", updatedAt: "2026-01-02T10:00:00Z"),
            makeNote(id: "n3", title: "Three", happenedAt: "2026-01-01", updatedAt: "2026-01-01T10:00:00Z"),
        ]
        LocalNoteCache.saveNotes(notes)
        NativeSWR.markFetched(.notes, value: notes)
        return notes
    }

    func testMergeServerNote_keepsSiblingNotesOnDisk() {
        _ = seedThreeNotesOnDisk()
        let server = makeNote(
            id: "n2",
            title: "Two from server",
            happenedAt: "2026-01-02",
            updatedAt: "2026-01-02T12:00:00Z"
        )
        let merged = LocalNoteCache.mergeServerNote(server)
        XCTAssertEqual(merged.title, "Two from server")
        let disk = LocalNoteCache.loadNotes()
        XCTAssertEqual(disk.count, 3)
        XCTAssertEqual(Set(disk.map(\.id)), Set(["n1", "n2", "n3"]))
        XCTAssertEqual(disk.first(where: { $0.id == "n2" })?.title, "Two from server")
        XCTAssertEqual(disk.first(where: { $0.id == "n1" })?.title, "One")
        XCTAssertEqual(disk.first(where: { $0.id == "n3" })?.title, "Three")
    }

    func testGetNote_doesNotTruncateSiblingCache() async throws {
        _ = seedThreeNotesOnDisk()
        let n2 = noteJSON(
            id: "n2",
            title: "Two network",
            bodyText: "from get",
            updatedAt: "2026-01-02T12:00:00Z"
        )
        MockNativeURLProtocol.noteByIdJSON =
            "{\"ok\":true,\"note\":\(n2),\"speakers\":[],\"via\":\"owned\"}"
        NativeSWR.invalidate(.note("n2"))

        let packed = try await NativeAPIClient.getNote(id: "n2", force: true)
        XCTAssertEqual(packed.note.title, "Two network")

        let disk = LocalNoteCache.loadNotes()
        XCTAssertEqual(disk.count, 3, "getNote must not rewrite notes-v1.json to a single row")
        XCTAssertEqual(Set(disk.map(\.id)), Set(["n1", "n2", "n3"]))
    }

    func testListNotes_afterDirtyGetNote_returnsAllThree() async throws {
        _ = seedThreeNotesOnDisk()
        var dirty = makeNote(
            id: "n2",
            title: "Two dirty",
            happenedAt: "2026-01-02",
            updatedAt: "2026-01-02T10:00:00Z"
        )
        dirty = LocalNoteCache.recordLocalEdit(dirty)
        NativeOutbox.enqueueNoteUpsert(dirty)
        LocalNoteCache.markPendingSync(id: "n2")

        let serverN2 = noteJSON(
            id: "n2",
            title: "Two server",
            bodyText: "server",
            updatedAt: "2026-01-02T11:00:00Z"
        )
        MockNativeURLProtocol.noteByIdJSON =
            "{\"ok\":true,\"note\":\(serverN2),\"speakers\":[],\"via\":\"owned\"}"
        NativeSWR.invalidate(.note("n2"))
        _ = try await NativeAPIClient.getNote(id: "n2", force: true)
        XCTAssertEqual(LocalNoteCache.loadNotes().count, 3)

        let listPayload = [
            noteJSON(id: "n1", title: "One", bodyText: "body", updatedAt: "2026-01-03T10:00:00Z"),
            noteJSON(id: "n2", title: "Two server", bodyText: "server", updatedAt: "2026-01-02T11:00:00Z"),
            noteJSON(id: "n3", title: "Three", bodyText: "body", updatedAt: "2026-01-01T10:00:00Z"),
        ].joined(separator: ",")
        MockNativeURLProtocol.notesJSON = "{\"ok\":true,\"notes\":[\(listPayload)]}"
        NativeSWR.invalidate(.notes)

        let listed = try await NativeAPIClient.listNotes(force: true)
        XCTAssertEqual(listed.count, 3)
        XCTAssertEqual(listed.first(where: { $0.id == "n2" })?.title, "Two dirty")
        XCTAssertEqual(Set(listed.map(\.id)), Set(["n1", "n2", "n3"]))
    }

    func testUpsert_afterGetNote_doesNotPersistOneNoteCache() async throws {
        _ = seedThreeNotesOnDisk()
        let n1 = noteJSON(
            id: "n1",
            title: "One network",
            bodyText: "get",
            updatedAt: "2026-01-03T11:00:00Z"
        )
        MockNativeURLProtocol.noteByIdJSON =
            "{\"ok\":true,\"note\":\(n1),\"speakers\":[],\"via\":\"owned\"}"
        NativeSWR.invalidate(.note("n1"))
        _ = try await NativeAPIClient.getNote(id: "n1", force: true)
        XCTAssertEqual(LocalNoteCache.loadNotes().count, 3)

        let edited = editLocally(id: "n1", title: "One edited", bodyText: "local")
        let ack = noteJSON(
            id: "n1",
            title: "One edited",
            bodyText: "local",
            updatedAt: edited.updatedAt
        )
        MockNativeURLProtocol.upsertNoteJSON =
            "{\"ok\":true,\"note\":\(ack),\"speakers\":[],\"via\":\"owned\"}"
        _ = try await NativeAPIClient.upsertNote(edited)

        let disk = LocalNoteCache.loadNotes()
        XCTAssertEqual(disk.count, 3, "upsert after getNote must not leave a 1-note cache")
        XCTAssertEqual(Set(disk.map(\.id)), Set(["n1", "n2", "n3"]))
        let mem: [NativeAPIClient.NoteDocument]? = NativeSWR.cachedValue(.notes)
        XCTAssertEqual(mem?.count, 3)
        XCTAssertTrue(NativeSWR.isFresh(.notes, ttl: NativeSWR.TTL.lists))
    }

    func testNoteSort_differingUpdatedAtAndHappenedAtFormats_stableAmongSiblings() {
        let a = makeNote(
            id: "a",
            title: "A",
            happenedAt: "2026-01-02",
            updatedAt: "2026-01-02T10:00:00.500Z"
        )
        let b = makeNote(
            id: "b",
            title: "B",
            happenedAt: "2026-01-02T00:00:00Z",
            updatedAt: "2026-01-02T10:00:00Z"
        )
        let c = makeNote(
            id: "c",
            title: "C",
            happenedAt: "2026-01-01",
            updatedAt: "2026-01-01T09:00:00.123Z"
        )
        // Same civil day for A/B; fractional updatedAt keeps A above B; C is older day.
        let sorted = [c, b, a].sorted(by: LocalNoteCache.compareNotesForList)
        XCTAssertEqual(sorted.map(\.id), ["a", "b", "c"])

        // Server ack format (no fractional seconds) must not reorder A below B when
        // local edit stamp is retained via effectiveUpdatedAt / maxUpdatedAt.
        var aAck = a
        aAck.updatedAt = "2026-01-02T10:00:00Z"
        LocalNoteCache.saveNotes([aAck, b, c])
        // Simulate lingering local stamp while dirty (or kept edit stamp after upsert).
        _ = LocalNoteCache.recordLocalEdit(a, editedAt: LocalNoteCache.parseUpdatedAt("2026-01-02T10:00:00.500Z")!)
        let after = LocalNoteCache.loadNotes().sorted(by: LocalNoteCache.compareNotesForList)
        XCTAssertEqual(after.first?.id, "a")
        let ids = Set(after.map(\.id))
        XCTAssertEqual(ids, Set(["a", "b", "c"]))
    }

    func testParseHappenedAt_acceptsDayAndISO() {
        let day = LocalNoteCache.parseHappenedAt("2026-01-02")
        let iso = LocalNoteCache.parseHappenedAt("2026-01-02T15:30:00Z")
        XCTAssertNotNil(day)
        XCTAssertNotNil(iso)
        XCTAssertEqual(day, iso, "ISO datetime should bucket to the same UTC civil day")
    }

    @MainActor
    func testReloadGeneration_onlyLatestApplies() {
        let vc = NotebookListViewController()
        let first = vc.testing_beginReloadGeneration()
        XCTAssertTrue(vc.testing_shouldApplyReload(generation: first))
        let second = vc.testing_beginReloadGeneration()
        XCTAssertFalse(vc.testing_shouldApplyReload(generation: first))
        XCTAssertTrue(vc.testing_shouldApplyReload(generation: second))
        XCTAssertEqual(vc.testing_reloadGeneration, second)
    }
}
