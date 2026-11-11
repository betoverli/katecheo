import XCTest
@testable import Katecheo

/// Group detail notes: disk cache paint, ~30s throttle, 304 / incremental merge.
@MainActor
final class GroupNotesCacheTests: XCTestCase {
    private let userId = "acct-group-notes"
    private let groupId = "g-cache-1"

    override func setUp() {
        super.setUp()
        NativeSWR.resetAllForTests()
        NativeSWR.networkProbeEnabled = true
        MockNativeURLProtocol.reset()
        MockNativeURLProtocol.register()
        NativeAPIClient.session = MockNativeURLProtocol.makeSession()
        NativeAPIClient.testAuthToken = "test-bearer-group-notes"
        LocalSessionCache.saveMe(seedMe(id: userId))
        LocalGroupNotesCache.clearAll()
    }

    override func tearDown() {
        LocalGroupNotesCache.clearAll()
        NativeAPIClient.testAuthToken = nil
        NativeAPIClient.session = .shared
        MockNativeURLProtocol.unregister()
        NativeSWR.resetAllForTests()
        super.tearDown()
    }

    private func seedMe(id: String) -> NativeAPIClient.MeDTO {
        NativeAPIClient.MeDTO(
            id: id,
            email: "a@b.c",
            displayName: "Ana",
            prefs: NativeAPIClient.PrefsDTO(
                locale: "pt", copyLocale: "pt", appId: "youversion", translationId: "nvi-pt",
                preferNative: true, copyFormat: "default", citeBook: "abbr", citeSep: ":",
                booksCompact: false, theme: "system", activePlans: nil, planProgress: nil,
                avatarId: "", avatarUrl: "", handle: "ana", firstName: "Ana", lastName: "", profileEmail: "a@b.c"
            ),
            notify: NativeAPIClient.NotifyPrefsDTO(reading: true, friends: true, shares: true, groups: true, apnsDevices: 0)
        )
    }

    private func sampleCard(
        id: String = "n1",
        title: String = "Culto",
        updatedAt: String = "2026-11-10T12:00:00Z"
    ) -> NativeAPIClient.GroupNoteCardDTO {
        NativeAPIClient.GroupNoteCardDTO(
            note: .init(id: id, title: title, happenedAt: "2026-11-10", updatedAt: updatedAt),
            author: .init(userId: userId, handle: "ana", firstName: "Ana", lastName: ""),
            owned: true,
            document: nil
        )
    }

    // MARK: - Disk cache

    func testDiskCache_keyedByUserAndGroup_clearsOnSignOut() {
        let cards = [sampleCard()]
        LocalGroupNotesCache.save(userId: userId, groupId: groupId, notes: cards, etag: "W/\"gnotes-1\"")
        XCTAssertEqual(LocalGroupNotesCache.load(userId: userId, groupId: groupId)?.count, 1)
        XCTAssertEqual(LocalGroupNotesCache.etag(userId: userId, groupId: groupId), "W/\"gnotes-1\"")
        XCTAssertNil(LocalGroupNotesCache.load(userId: "other", groupId: groupId))

        LocalGroupNotesCache.clearAll()
        XCTAssertNil(LocalGroupNotesCache.load(userId: userId, groupId: groupId))
    }

    func testGroupList_cacheHitRendersImmediatelyWithoutNetwork() {
        let cards = [sampleCard(title: "Cached note")]
        LocalGroupNotesCache.save(userId: userId, groupId: groupId, notes: cards, etag: "W/\"cached\"")
        NativeSWR.markFetched(.groupNotes(groupId), value: cards)

        let group = NativeAPIClient.GroupDTO(
            id: groupId,
            name: "Célula",
            description: "",
            visibility: "private",
            postPolicy: "members",
            createdBy: userId,
            memberCount: 2,
            myRole: "member",
            myStatus: "accepted",
            updatedAt: "2026-11-10T00:00:00Z",
            published: true
        )
        MockNativeURLProtocol.groupNotesJSON = nil // would 404 if network were hit
        MockNativeURLProtocol.groupJSON = nil

        let vc = NotebookListViewController(group: group)
        vc.loadViewIfNeeded()
        // Cache should paint before any network.
        XCTAssertEqual(vc.testing_groupCardsCount, 1)
        XCTAssertEqual(vc.testing_firstGroupNoteTitle, "Cached note")
        XCTAssertEqual(MockNativeURLProtocol.groupNotesHits, 0)
    }

    // MARK: - Throttle + 304

    func testListGroupNotes_throttlesWithin30s() async throws {
        MockNativeURLProtocol.groupNotesJSON = Self.fullPayload
        MockNativeURLProtocol.groupNotesETag = "W/\"gnotes-abc\""

        let first = try await NativeAPIClient.listGroupNotes(groupId: groupId, force: true)
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(MockNativeURLProtocol.groupNotesHits, 1)

        NativeSWR.resetProbe()
        let second = try await NativeAPIClient.listGroupNotes(groupId: groupId, force: false)
        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(MockNativeURLProtocol.groupNotesHits, 1, "TTL ~30s must skip network")
        XCTAssertEqual(NativeSWR.probeCount(containing: "/groups/\(groupId)/notes"), 0)
    }

    func testListGroupNotes_forceBypassesThrottle() async throws {
        MockNativeURLProtocol.groupNotesJSON = Self.fullPayload
        MockNativeURLProtocol.groupNotesETag = "W/\"gnotes-abc\""
        _ = try await NativeAPIClient.listGroupNotes(groupId: groupId, force: true)
        XCTAssertEqual(MockNativeURLProtocol.groupNotesHits, 1)

        MockNativeURLProtocol.groupNotesJSON = Self.fullPayloadUpdated
        _ = try await NativeAPIClient.listGroupNotes(groupId: groupId, force: true)
        XCTAssertEqual(MockNativeURLProtocol.groupNotesHits, 2)
        XCTAssertEqual(LocalGroupNotesCache.load(userId: userId, groupId: groupId)?.first?.note.title, "Updated")
    }

    func testListGroupNotes_304KeepsCache() async throws {
        MockNativeURLProtocol.groupNotesJSON = Self.fullPayload
        MockNativeURLProtocol.groupNotesETag = "W/\"gnotes-same\""
        _ = try await NativeAPIClient.listGroupNotes(groupId: groupId, force: true)
        XCTAssertEqual(LocalGroupNotesCache.etag(userId: userId, groupId: groupId), "W/\"gnotes-same\"")

        // Expire SWR freshness so the next call hits the network with If-None-Match.
        NativeSWR.invalidate(.groupNotes(groupId))
        MockNativeURLProtocol.groupNotesStatus = 304
        MockNativeURLProtocol.groupNotesJSON = nil

        let notes = try await NativeAPIClient.listGroupNotes(groupId: groupId, force: false)
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes.first?.note.title, "Culto")
        XCTAssertEqual(MockNativeURLProtocol.lastIfNoneMatch, "W/\"gnotes-same\"")
        XCTAssertEqual(MockNativeURLProtocol.groupNotesHits, 2)
    }

    func testListGroupNotes_incrementalMerge() async throws {
        MockNativeURLProtocol.groupNotesJSON = Self.fullPayload
        MockNativeURLProtocol.groupNotesETag = "W/\"v1\""
        _ = try await NativeAPIClient.listGroupNotes(groupId: groupId, force: true)

        NativeSWR.invalidate(.groupNotes(groupId))
        MockNativeURLProtocol.groupNotesStatus = 200
        MockNativeURLProtocol.groupNotesJSON = Self.incrementalPayload
        MockNativeURLProtocol.groupNotesETag = "W/\"v2\""

        let notes = try await NativeAPIClient.listGroupNotes(groupId: groupId, force: false)
        XCTAssertEqual(notes.map(\.note.id).sorted(), ["n1", "n2"])
        XCTAssertNotNil(MockNativeURLProtocol.lastUpdatedSince)
        XCTAssertEqual(notes.first(where: { $0.note.id == "n1" })?.note.title, "Culto")
        XCTAssertEqual(notes.first(where: { $0.note.id == "n2" })?.note.title, "Nova")
    }

    func testMergeGroupNotes_replacesById() {
        let prior = [sampleCard(id: "n1", title: "Old", updatedAt: "2026-11-01T00:00:00Z")]
        let delta = [
            sampleCard(id: "n1", title: "New", updatedAt: "2026-11-11T00:00:00Z"),
            sampleCard(id: "n2", title: "Extra", updatedAt: "2026-11-11T01:00:00Z"),
        ]
        let merged = NativeAPIClient.mergeGroupNotes(prior: prior, delta: delta)
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged.first(where: { $0.note.id == "n1" })?.note.title, "New")
    }

    func testEmptyStateIcon_stopsSpinningAfterLoading() {
        let empty = KCEmptyStateView()
        empty.showLoading(message: String(localized: "Carregando…"))
        XCTAssertTrue(empty.testing_isIconSpinning)
        empty.show(
            symbol: "bell.slash",
            title: String(localized: "Nenhum aviso ainda"),
            message: "x"
        )
        XCTAssertFalse(empty.testing_isIconSpinning, "empty/error icon must be static")
    }

    // MARK: - Fixtures

    private static let fullPayload = ##"""
    {"ok":true,"notes":[
      {"note":{"id":"n1","title":"Culto","happenedAt":"2026-11-10","updatedAt":"2026-11-10T12:00:00Z"},
       "author":{"userId":"acct-group-notes","handle":"ana","firstName":"Ana","lastName":""},
       "owned":true,"document":null}
    ],"incremental":false}
    """##

    private static let fullPayloadUpdated = ##"""
    {"ok":true,"notes":[
      {"note":{"id":"n1","title":"Updated","happenedAt":"2026-11-10","updatedAt":"2026-11-11T12:00:00Z"},
       "author":{"userId":"acct-group-notes","handle":"ana","firstName":"Ana","lastName":""},
       "owned":true,"document":null}
    ],"incremental":false}
    """##

    private static let incrementalPayload = ##"""
    {"ok":true,"notes":[
      {"note":{"id":"n2","title":"Nova","happenedAt":"2026-11-11","updatedAt":"2026-11-11T15:00:00Z"},
       "author":{"userId":"acct-group-notes","handle":"ana","firstName":"Ana","lastName":""},
       "owned":true,"document":null}
    ],"incremental":true}
    """##
}
