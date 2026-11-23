import Foundation

/// Seeds Caderno + Grupos notes for iPad XCUITests (`-katecheoUITestSeedNotes`).
/// Production launches never pass the argument; network GETs short-circuit to disk while active
/// so a fake bearer cannot 401-wipe the seed.
enum UITestSeed {
    static let launchArgument = "-katecheoUITestSeedNotes"

    static let userId = "uitest-user"
    static let groupId = "uitest-group"
    static let groupName = "Grupo UITest"

    static let cadernoNoteId = "uitestcadernonote00000000000001"
    static let cadernoTitle = "Nota UITest Caderno"
    static let cadernoBody = "Corpo da nota no Caderno."

    static let groupNoteId = "uitestgroupnote0000000000000001"
    static let groupNoteTitle = "Nota UITest Grupo"
    static let groupNoteBody = "Corpo publicado no grupo."

    private static var applied = false
    private(set) static var isActive = false

    /// Call once at process start (before the root VC loads lists).
    static func applyIfNeeded(arguments: [String] = ProcessInfo.processInfo.arguments) {
        guard !applied else { return }
        applied = true
        guard arguments.contains(launchArgument) else { return }
        isActive = true

        // Soft-sign-in for GroupsList / hasBearer without a real Keychain entitlement.
        NativeAPIClient.testAuthToken = "uitest-seed-token"

        let me = NativeAPIClient.MeDTO(
            id: userId,
            email: "uitest@katecheo.app",
            displayName: "UITest",
            prefs: NativeAPIClient.PrefsDTO(
                locale: "pt",
                copyLocale: "pt",
                appId: "youversion",
                translationId: "nvi-pt",
                preferNative: true,
                copyFormat: "default",
                citeBook: "abbr",
                citeSep: ":",
                booksCompact: false,
                theme: "system",
                activePlans: nil,
                planProgress: nil,
                avatarId: "",
                avatarUrl: "",
                handle: "uitest",
                firstName: "UI",
                lastName: "Test",
                profileEmail: "uitest@katecheo.app"
            ),
            notify: NativeAPIClient.NotifyPrefsDTO(
                reading: true,
                friends: true,
                shares: true,
                groups: true,
                apnsDevices: 0
            )
        )
        LocalSessionCache.saveMe(me)

        let caderno = makeNote(id: cadernoNoteId, title: cadernoTitle, body: cadernoBody)
        let groupNote = makeNote(id: groupNoteId, title: groupNoteTitle, body: groupNoteBody)
        LocalNoteCache.saveNotes([caderno, groupNote])

        let group = NativeAPIClient.GroupDTO(
            id: groupId,
            name: groupName,
            description: "Seed XCUITest",
            visibility: "private",
            postPolicy: "members",
            createdBy: userId,
            memberCount: 1,
            myRole: "admin",
            myStatus: "accepted",
            updatedAt: groupNote.updatedAt,
            published: true
        )
        LocalSessionCache.saveGroups([group])

        let card = NativeAPIClient.GroupNoteCardDTO(
            note: .init(
                id: groupNote.id,
                title: groupNote.title,
                happenedAt: groupNote.happenedAt,
                updatedAt: groupNote.updatedAt
            ),
            author: .init(userId: userId, handle: "uitest", firstName: "UI", lastName: "Test"),
            owned: true,
            document: groupNote
        )
        LocalGroupNotesCache.save(userId: userId, groupId: groupId, notes: [card], etag: "W/\"uitest\"")

        // Keep SWR warm so list/detail paint from memory without network.
        NativeSWR.markFetched(.me, value: me)
        NativeSWR.markFetched(.notes, value: [caderno, groupNote])
        NativeSWR.markFetched(.groups, value: [group])
        NativeSWR.markFetched(.groupNotes(groupId), value: [card])
        NativeSWR.markFetched(
            .note(cadernoNoteId),
            value: NativeAPIClient.NotePack(note: caderno, speakers: [], via: "owned")
        )
        NativeSWR.markFetched(
            .note(groupNoteId),
            value: NativeAPIClient.NotePack(note: groupNote, speakers: [], via: "owned")
        )
    }

    private static func makeNote(id: String, title: String, body: String) -> NativeAPIClient.NoteDocument {
        var note = NativeAPIClient.emptyNote(id: id)
        note.title = title
        note.body = NativeAPIClient.NoteBody(blocks: [
            NativeAPIClient.LineBlock(
                id: UUID().uuidString.replacingOccurrences(of: "-", with: ""),
                type: "paragraph",
                spans: [
                    .init(
                        type: "text",
                        text: body,
                        marks: nil,
                        bookId: nil,
                        chapter: nil,
                        verseStart: nil,
                        verseEnd: nil,
                        href: nil
                    ),
                ],
                speakerId: nil,
                title: nil,
                collapsed: nil,
                checked: nil,
                blocks: nil
            ),
        ])
        return note
    }
}
