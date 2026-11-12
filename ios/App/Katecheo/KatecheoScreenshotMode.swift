import Foundation
import UIKit

/// App Store marketing screenshot fixture mode.
///
/// **Activation:** only via the process launch argument `-KatecheoScreenshotMode`.
/// Production installs never pass that argument, so this path cannot arm itself
/// from UserDefaults, deep links, or remote config.
enum KatecheoScreenshotMode {
    static let launchArgument = "-KatecheoScreenshotMode"
    static let sceneLaunchArgument = "-KatecheoScreenshotScene"

    /// Stable demo note opened for the Editor scene.
    static let editorNoteId = "screenshot-note-editor"

    enum Scene: String, CaseIterable {
        case notebook
        case editor
        case lists
        case groups
        case profile

        var accessibilityIdentifier: String { "screenshot.root.\(rawValue)" }

        var fileStem: String {
            switch self {
            case .notebook: return "01-caderno"
            case .editor: return "02-editor"
            case .lists: return "03-listas"
            case .groups: return "04-grupos"
            case .profile: return "05-perfil"
            }
        }
    }

    /// True only when the current process was started with `-KatecheoScreenshotMode`.
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    static var requestedScene: Scene {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: sceneLaunchArgument),
              args.index(after: idx) < args.endIndex,
              let scene = Scene(rawValue: args[args.index(after: idx)])
        else {
            return .notebook
        }
        return scene
    }

    private static var didPrepare = false
    private static var didPresent = false

    // MARK: - Bootstrap

    /// Call once at launch (AppDelegate). Seeds offline fixtures and a fake local session.
    static func prepareIfNeeded() {
        guard isEnabled, !didPrepare else { return }
        didPrepare = true

        OnboardingStore.markSeen()
        LocalSessionCache.showOfflineHint = false
        KCActivityStore.clearAccount("screenshot-user")

        NativeAPIClient.testAuthToken = "screenshot-local-fixture-token"

        let me = makeMe()
        let notes = makeNotes()
        let speakers = makeSpeakers()
        let groups = makeGroups()

        LocalSessionCache.saveMe(me)
        LocalSessionCache.saveGroups(groups)
        LocalNoteCache.saveNotes(notes)
        LocalNoteCache.saveSpeakers(speakers)

        NativeSWR.markFetched(.me, value: me)
        NativeSWR.markFetched(.prefs, value: me.prefs)
        NativeSWR.markFetched(.notes, value: notes)
        NativeSWR.markFetched(.speakers, value: speakers)
        NativeSWR.markFetched(.groups, value: groups)
        NativeSWR.markFetched(.granted, value: [NativeAPIClient.NoteDocument]())
        if let editor = notes.first(where: { $0.id == editorNoteId }) {
            NativeSWR.markFetched(
                .note(editorNoteId),
                value: NativeAPIClient.NotePack(note: editor, speakers: speakers, via: "owned")
            )
        }

        AppAppearance.sync(from: me.prefs)
    }

    /// After the window root is the tab shell, jump to the requested marketing scene.
    @MainActor
    static func presentSceneIfNeeded(in window: UIWindow?) {
        guard isEnabled, !didPresent else { return }
        didPresent = true
        guard let window else { return }

        // Ensure tabs (never onboarding) without animation flashes.
        if !(window.rootViewController is NativeRootTabBarController) {
            OnboardingStore.markSeen()
            window.rootViewController = AppRoot.makeMainShell()
        }
        guard let tabs = window.rootViewController as? NativeRootTabBarController else { return }

        // Let first layout settle, then navigate.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            apply(scene: requestedScene, tabs: tabs)
        }
    }

    @MainActor
    private static func apply(scene: Scene, tabs: NativeRootTabBarController) {
        switch scene {
        case .notebook:
            tabs.selectedIndex = 0
            if let nav = tabs.selectedViewController as? UINavigationController {
                nav.popToRootViewController(animated: false)
                nav.topViewController?.view.accessibilityIdentifier = scene.accessibilityIdentifier
            }
        case .editor:
            tabs.selectedIndex = 0
            guard let nav = tabs.selectedViewController as? UINavigationController else { return }
            nav.popToRootViewController(animated: false)
            let notes = LocalNoteCache.loadNotes()
            let note = notes.first(where: { $0.id == editorNoteId }) ?? notes.first
            guard let note else { return }
            let detail = NoteDetailViewController(
                noteId: note.id,
                initial: note,
                grantedReadOnly: false
            )
            detail.view.accessibilityIdentifier = scene.accessibilityIdentifier
            nav.pushViewController(detail, animated: false)
        case .lists:
            tabs.selectedIndex = 2
            if let nav = tabs.selectedViewController as? UINavigationController,
               let home = nav.viewControllers.first as? VersesHomeViewController
            {
                home.selectHomeFilter("lists")
                home.view.accessibilityIdentifier = scene.accessibilityIdentifier
            }
        case .groups:
            tabs.selectedIndex = 1
            if let nav = tabs.selectedViewController as? UINavigationController {
                nav.popToRootViewController(animated: false)
                nav.topViewController?.view.accessibilityIdentifier = scene.accessibilityIdentifier
            }
        case .profile:
            tabs.selectedIndex = 3
            if let nav = tabs.selectedViewController as? UINavigationController {
                nav.popToRootViewController(animated: false)
                nav.topViewController?.view.accessibilityIdentifier = scene.accessibilityIdentifier
            }
        }
    }

    // MARK: - Network short-circuit

    /// Serve fixture JSON for every native API hit while screenshot mode is on.
    /// Never touches the network.
    static func fixtureResponse(for request: URLRequest) throws -> (Int, Data, HTTPURLResponse?) {
        let path = request.url?.path ?? ""
        let method = (request.httpMethod ?? "GET").uppercased()
        let payload: [String: Any]

        if path.hasSuffix("/api/native/v1/me") && method == "GET" {
            payload = ["ok": true, "me": encodeJSONObject(makeMe())]
        } else if path.hasSuffix("/api/native/v1/prefs") && method == "GET" {
            payload = ["ok": true, "prefs": encodeJSONObject(makeMe().prefs)]
        } else if path.hasSuffix("/api/native/v1/notify-prefs") || path.contains("/notify-prefs") {
            payload = ["ok": true, "notify": encodeJSONObject(makeMe().notify)]
        } else if path.hasSuffix("/api/native/v1/notes/granted") {
            payload = ["ok": true, "notes": []]
        } else if path.hasSuffix("/api/native/v1/notes") && method == "GET" {
            payload = ["ok": true, "notes": encodeJSONObject(makeNotes())]
        } else if path.contains("/api/native/v1/notes/") && method == "GET" {
            let id = path.split(separator: "/").last.map(String.init) ?? editorNoteId
            let note = makeNotes().first(where: { $0.id == id }) ?? makeNotes()[0]
            payload = [
                "ok": true,
                "note": encodeJSONObject(note),
                "speakers": encodeJSONObject(makeSpeakers()),
                "via": "owned",
            ]
        } else if path.hasSuffix("/api/native/v1/speakers") {
            payload = ["ok": true, "speakers": encodeJSONObject(makeSpeakers())]
        } else if path.hasSuffix("/api/native/v1/groups") && method == "GET" {
            payload = ["ok": true, "groups": encodeJSONObject(makeGroups())]
        } else if path.contains("/api/native/v1/groups/") && path.hasSuffix("/members") {
            payload = ["ok": true, "members": encodeJSONObject(makeMembers())]
        } else if path.contains("/api/native/v1/groups/") && path.hasSuffix("/notes") {
            payload = ["ok": true, "notes": [], "incremental": false]
        } else if path.contains("/api/native/v1/groups/") {
            let group = makeGroups()[0]
            payload = ["ok": true, "group": encodeJSONObject(group)]
        } else if path.hasSuffix("/api/native/v1/my-collections") {
            payload = ["ok": true, "collections": encodeJSONObject(makeCollections())]
        } else if path.hasSuffix("/api/native/v1/session") {
            payload = ["ok": true, "user": ["id": "screenshot-user", "email": "ana@katecheo.app"]]
        } else if path.contains("/api/native/v1/notifications") || path.contains("/api/native/v1/inbox") {
            payload = ["ok": true, "items": [], "unread": 0, "byKind": [:]]
        } else if path.contains("/api/native/v1/links") {
            payload = ["ok": true, "friends": [], "incoming": [], "outgoing": []]
        } else if path.contains("/api/native/v1/auth/providers") {
            payload = ["ok": true, "providers": ["google", "apple", "email"]]
        } else {
            // Harmless empty success — keeps chrome from error alerts.
            payload = ["ok": true]
        }

        let data = try JSONSerialization.data(withJSONObject: payload)
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://katecheo.app/")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )
        return (200, data, response)
    }

    // MARK: - Fixtures (localized pastoral sample data)

    private static func makeMe() -> NativeAPIClient.MeDTO {
        let locale = AppLocale.apiCode
        let prefs = NativeAPIClient.PrefsDTO(
            locale: locale,
            copyLocale: locale,
            appId: "youversion",
            translationId: locale == "en" ? "niv" : (locale == "es" ? "nvi" : "nvi-pt"),
            preferNative: true,
            copyFormat: "plain",
            citeBook: "abbr",
            citeSep: ".",
            booksCompact: false,
            theme: "system",
            activePlans: nil,
            planProgress: nil,
            avatarId: "",
            avatarUrl: "",
            handle: "anaribeiro",
            firstName: String(localized: "screenshot.profile.firstName"),
            lastName: String(localized: "screenshot.profile.lastName"),
            profileEmail: "ana@katecheo.app"
        )
        return NativeAPIClient.MeDTO(
            id: "screenshot-user",
            email: "ana@katecheo.app",
            displayName: prefs.displayName,
            prefs: prefs,
            notify: NativeAPIClient.NotifyPrefsDTO(
                reading: true,
                friends: true,
                shares: true,
                groups: true,
                apnsDevices: 1
            )
        )
    }

    private static func makeSpeakers() -> [NativeAPIClient.SpeakerDTO] {
        [
            NativeAPIClient.SpeakerDTO(
                id: "spk-pastor",
                name: String(localized: "screenshot.speaker.pastor"),
                color: "#5B6C4A",
                updatedAt: isoNow()
            ),
            NativeAPIClient.SpeakerDTO(
                id: "spk-self",
                name: String(localized: "screenshot.speaker.self"),
                color: "#8B6B4A",
                updatedAt: isoNow()
            ),
        ]
    }

    private static func makeNotes() -> [NativeAPIClient.NoteDocument] {
        let editor = NativeAPIClient.NoteDocument(
            schemaVersion: 1,
            id: editorNoteId,
            title: String(localized: "screenshot.note.editor.title"),
            happenedAt: "2026-03-08",
            tags: [
                String(localized: "screenshot.tag.sermon"),
                String(localized: "screenshot.tag.prep"),
            ],
            noteSpeakerId: "spk-pastor",
            visibility: "private",
            updatedAt: isoNow(),
            body: NativeAPIClient.NoteBody(blocks: [
                block("h1", type: "heading", text: String(localized: "screenshot.note.editor.h1")),
                block(
                    "p1",
                    type: "paragraph",
                    spans: [
                        textSpan(String(localized: "screenshot.note.editor.intro") + " "),
                        refSpan(bookId: "JHN", chapter: 15, verseStart: 1, verseEnd: 8),
                    ]
                ),
                block("h2", type: "heading", text: String(localized: "screenshot.note.editor.h2")),
                block("b1", type: "bullet", text: String(localized: "screenshot.note.editor.b1")),
                block("b2", type: "bullet", text: String(localized: "screenshot.note.editor.b2")),
                block(
                    "b3",
                    type: "bullet",
                    spans: [
                        textSpan(String(localized: "screenshot.note.editor.b3") + " "),
                        refSpan(bookId: "JHN", chapter: 15, verseStart: 5, verseEnd: nil),
                    ]
                ),
                block("h3", type: "heading", text: String(localized: "screenshot.note.editor.h3")),
                block(
                    "p2",
                    type: "paragraph",
                    spans: [
                        textSpan(String(localized: "screenshot.note.editor.close") + " "),
                        refSpan(bookId: "GAL", chapter: 5, verseStart: 22, verseEnd: 23),
                    ]
                ),
            ])
        )

        let sermon = NativeAPIClient.NoteDocument(
            schemaVersion: 1,
            id: "screenshot-note-sermon",
            title: String(localized: "screenshot.note.sermon.title"),
            happenedAt: "2026-03-01",
            tags: [
                String(localized: "screenshot.tag.sermon"),
                String(localized: "screenshot.tag.sunday"),
            ],
            noteSpeakerId: "spk-pastor",
            visibility: "private",
            updatedAt: isoNow(),
            body: NativeAPIClient.NoteBody(blocks: [
                block(
                    "s1",
                    type: "paragraph",
                    spans: [
                        textSpan(String(localized: "screenshot.note.sermon.body") + " "),
                        refSpan(bookId: "PHP", chapter: 4, verseStart: 6, verseEnd: 7),
                    ]
                ),
            ])
        )

        let devotion = NativeAPIClient.NoteDocument(
            schemaVersion: 1,
            id: "screenshot-note-devotion",
            title: String(localized: "screenshot.note.devotion.title"),
            happenedAt: "2026-03-05",
            tags: [String(localized: "screenshot.tag.devotion")],
            noteSpeakerId: nil,
            visibility: "private",
            updatedAt: isoNow(),
            body: NativeAPIClient.NoteBody(blocks: [
                block(
                    "d1",
                    type: "paragraph",
                    spans: [
                        textSpan(String(localized: "screenshot.note.devotion.body") + " "),
                        refSpan(bookId: "PSA", chapter: 23, verseStart: 1, verseEnd: 3),
                    ]
                ),
            ])
        )

        let groupStudy = NativeAPIClient.NoteDocument(
            schemaVersion: 1,
            id: "screenshot-note-group",
            title: String(localized: "screenshot.note.group.title"),
            happenedAt: "2026-02-26",
            tags: [
                String(localized: "screenshot.tag.group"),
                String(localized: "screenshot.tag.study"),
            ],
            noteSpeakerId: "spk-self",
            visibility: "friends",
            updatedAt: isoNow(),
            body: NativeAPIClient.NoteBody(blocks: [
                block(
                    "g1",
                    type: "paragraph",
                    spans: [
                        textSpan(String(localized: "screenshot.note.group.body") + " "),
                        refSpan(bookId: "ACT", chapter: 2, verseStart: 42, verseEnd: 47),
                    ]
                ),
            ])
        )

        // Newest first for Caderno polish.
        return [editor, devotion, sermon, groupStudy]
    }

    private static func makeGroups() -> [NativeAPIClient.GroupDTO] {
        [
            NativeAPIClient.GroupDTO(
                id: "screenshot-group-cell",
                name: String(localized: "screenshot.group.cell.name"),
                description: String(localized: "screenshot.group.cell.desc"),
                visibility: "private",
                postPolicy: "members",
                createdBy: "screenshot-user",
                memberCount: 8,
                myRole: "admin",
                myStatus: "accepted",
                updatedAt: isoNow(),
                published: true
            ),
            NativeAPIClient.GroupDTO(
                id: "screenshot-group-leaders",
                name: String(localized: "screenshot.group.leaders.name"),
                description: String(localized: "screenshot.group.leaders.desc"),
                visibility: "private",
                postPolicy: "admins",
                createdBy: "screenshot-user",
                memberCount: 5,
                myRole: "member",
                myStatus: "accepted",
                updatedAt: isoNow(),
                published: true
            ),
        ]
    }

    private static func makeMembers() -> [NativeAPIClient.GroupMemberDTO] {
        [
            member("screenshot-user", "anaribeiro", String(localized: "screenshot.profile.firstName"), String(localized: "screenshot.profile.lastName"), role: "admin"),
            member("u2", "pedro.m", String(localized: "screenshot.member.2.first"), String(localized: "screenshot.member.2.last"), role: "member"),
            member("u3", "sofia.l", String(localized: "screenshot.member.3.first"), String(localized: "screenshot.member.3.last"), role: "member"),
            member("u4", "lucas.a", String(localized: "screenshot.member.4.first"), String(localized: "screenshot.member.4.last"), role: "member"),
        ]
    }

    private static func makeCollections() -> [NativeAPIClient.UserCollectionDTO] {
        [
            NativeAPIClient.UserCollectionDTO(
                id: "screenshot-list-psalms",
                title: String(localized: "screenshot.list.psalms"),
                slug: "psalms",
                visibility: "private",
                sourceId: nil,
                passages: [
                    NativeAPIClient.PassageDTO(bookId: "PSA", chapter: 23, verseStart: 1, verseEnd: 6),
                    NativeAPIClient.PassageDTO(bookId: "PSA", chapter: 91, verseStart: 1, verseEnd: 4),
                    NativeAPIClient.PassageDTO(bookId: "PSA", chapter: 121, verseStart: 1, verseEnd: 8),
                ],
                updatedAt: isoNow()
            ),
            NativeAPIClient.UserCollectionDTO(
                id: "screenshot-list-sermon",
                title: String(localized: "screenshot.list.sermon"),
                slug: "sermon-refs",
                visibility: "private",
                sourceId: nil,
                passages: [
                    NativeAPIClient.PassageDTO(bookId: "JHN", chapter: 15, verseStart: 1, verseEnd: 8),
                    NativeAPIClient.PassageDTO(bookId: "GAL", chapter: 5, verseStart: 22, verseEnd: 23),
                    NativeAPIClient.PassageDTO(bookId: "PHP", chapter: 4, verseStart: 6, verseEnd: 7),
                ],
                updatedAt: isoNow()
            ),
            NativeAPIClient.UserCollectionDTO(
                id: "screenshot-list-quarter",
                title: String(localized: "screenshot.list.quarter"),
                slug: "quarter",
                visibility: "private",
                sourceId: nil,
                passages: [
                    NativeAPIClient.PassageDTO(bookId: "ACT", chapter: 2, verseStart: 42, verseEnd: 47),
                    NativeAPIClient.PassageDTO(bookId: "ROM", chapter: 12, verseStart: 1, verseEnd: 2),
                ],
                updatedAt: isoNow()
            ),
        ]
    }

    // MARK: - Block helpers

    private static func block(
        _ id: String,
        type: String,
        text: String
    ) -> NativeAPIClient.LineBlock {
        block(id, type: type, spans: [textSpan(text)])
    }

    private static func block(
        _ id: String,
        type: String,
        spans: [NativeAPIClient.TextSpan]
    ) -> NativeAPIClient.LineBlock {
        NativeAPIClient.LineBlock(
            id: id,
            type: type,
            spans: spans,
            speakerId: nil,
            title: nil,
            collapsed: nil,
            checked: nil,
            blocks: nil
        )
    }

    private static func textSpan(_ text: String) -> NativeAPIClient.TextSpan {
        NativeAPIClient.TextSpan(
            type: "text",
            text: text,
            marks: nil,
            bookId: nil,
            chapter: nil,
            verseStart: nil,
            verseEnd: nil,
            href: nil
        )
    }

    private static func refSpan(
        bookId: String,
        chapter: Int,
        verseStart: Int?,
        verseEnd: Int?
    ) -> NativeAPIClient.TextSpan {
        // References only — never embed verse text.
        NativeAPIClient.TextSpan(
            type: "bibleRef",
            text: nil,
            marks: nil,
            bookId: bookId,
            chapter: chapter,
            verseStart: verseStart,
            verseEnd: verseEnd,
            href: nil
        )
    }

    private static func member(
        _ userId: String,
        _ handle: String,
        _ first: String,
        _ last: String,
        role: String
    ) -> NativeAPIClient.GroupMemberDTO {
        NativeAPIClient.GroupMemberDTO(
            userId: userId,
            handle: handle,
            firstName: first,
            lastName: last,
            avatarId: "",
            avatarUrl: "",
            role: role,
            status: "accepted"
        )
    }

    private static func isoNow() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private static func encodeJSONObject<T: Encodable>(_ value: T) -> Any {
        let data = (try? JSONEncoder().encode(value)) ?? Data("{}".utf8)
        return (try? JSONSerialization.jsonObject(with: data)) ?? [:]
    }
}
