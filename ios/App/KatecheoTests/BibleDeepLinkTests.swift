import XCTest
@testable import Katecheo

@MainActor
final class BibleDeepLinkTests: XCTestCase {
    override func tearDown() async throws {
        BibleDeepLink.testOpenHandler = nil
        BibleDeepLink.testCanOpenURL = nil
        NativeAPIClient.session = .shared
        NativeAPIClient.testAuthToken = nil
        NativeSWR.resetAllForTests()
        try await super.tearDown()
    }

    // MARK: - URL building (parity with apps.ts)

    func testYouVersion_john316_preferNativeTrueAndFalse() {
        let passage = BibleDeepLink.Passage(bookId: "JHN", chapter: 3, verseStart: 16, verseEnd: nil)
        XCTAssertEqual(
            BibleDeepLink.buildDeepLink(
                appId: "youversion",
                passage: passage,
                translationId: "niv",
                preferNative: true,
                locale: "en"
            ),
            "youversion://bible?reference=JHN.3.16"
        )
        XCTAssertEqual(
            BibleDeepLink.buildDeepLink(
                appId: "youversion",
                passage: passage,
                translationId: "nvi-pt",
                preferNative: false,
                locale: "pt"
            ),
            "https://www.bible.com/bible/129/JHN.3.16"
        )
        XCTAssertEqual(
            BibleDeepLink.buildDeepLink(
                appId: "youversion",
                passage: passage,
                translationId: "niv",
                preferNative: false,
                locale: "en"
            ),
            "https://www.bible.com/bible/111/JHN.3.16"
        )
    }

    func testTecarta_john316_preferNativeTrueAndFalse() {
        let passage = BibleDeepLink.Passage(bookId: "JHN", chapter: 3, verseStart: 16, verseEnd: nil)
        XCTAssertEqual(
            BibleDeepLink.buildDeepLink(
                appId: "tecarta",
                passage: passage,
                translationId: "niv",
                preferNative: true,
                locale: "en"
            ),
            "bible://John%203:16"
        )
        XCTAssertEqual(
            BibleDeepLink.buildDeepLink(
                appId: "tecarta",
                passage: passage,
                translationId: "niv",
                preferNative: false,
                locale: "en"
            ),
            "https://tecartabible.com/bible/John+3:16"
        )
    }

    func testYouVersion_verseRange_matchesAppsTs() {
        let passage = BibleDeepLink.Passage(bookId: "JHN", chapter: 3, verseStart: 16, verseEnd: 18)
        XCTAssertEqual(
            BibleDeepLink.buildDeepLink(
                appId: "youversion",
                passage: passage,
                translationId: "niv",
                preferNative: true,
                locale: "en"
            ),
            "youversion://bible?reference=JHN.3.16-18"
        )
        XCTAssertEqual(
            BibleDeepLink.buildDeepLink(
                appId: "youversion",
                passage: passage,
                translationId: "niv",
                preferNative: false,
                locale: "en"
            ),
            "https://www.bible.com/bible/111/JHN.3.16-18"
        )
    }

    func testOliveTreeAndJwLibrary_parity() {
        let single = BibleDeepLink.Passage(bookId: "JHN", chapter: 3, verseStart: 16, verseEnd: nil)
        let range = BibleDeepLink.Passage(bookId: "JHN", chapter: 3, verseStart: 16, verseEnd: 18)
        XCTAssertEqual(
            BibleDeepLink.buildDeepLink(
                appId: "olive-tree",
                passage: single,
                translationId: "niv",
                preferNative: true,
                locale: "en"
            ),
            "olivetree://bible/43.3.16"
        )
        XCTAssertEqual(
            BibleDeepLink.buildDeepLink(
                appId: "jw-library",
                passage: range,
                translationId: "niv",
                preferNative: true,
                locale: "en"
            ),
            "jwlibrary:///finder?bible=43003016-43003018"
        )
        XCTAssertEqual(
            BibleDeepLink.buildDeepLink(
                appId: "logos",
                passage: single,
                translationId: "niv",
                preferNative: false,
                locale: "en"
            ),
            "https://ref.ly/Jn3.16"
        )
    }

    func testProfileBibleCatalog_youVersionNumericInvert() {
        XCTAssertEqual(ProfileBibleCatalog.youVersionNumericId(for: "nvi-pt"), 129)
        XCTAssertEqual(ProfileBibleCatalog.youVersionNumericId(for: "111", locale: "en"), 111)
        XCTAssertEqual(ProfileBibleCatalog.youVersionNumericId(for: "niv"), 111)
    }

    func testUrlForOpening_prefersInstalledNativeEvenWhenPreferNativeFalse() {
        BibleDeepLink.testCanOpenURL = { url in
            url.scheme == "youversion"
        }
        let passage = BibleDeepLink.Passage(bookId: "JHN", chapter: 3, verseStart: 16, verseEnd: nil)
        let url = BibleDeepLink.urlForOpening(
            appId: "youversion",
            passage: passage,
            translationId: "nvi-pt",
            preferNative: false,
            locale: "pt"
        )
        XCTAssertEqual(url?.absoluteString, "youversion://bible?reference=JHN.3.16")
    }

    func testUrlForOpening_fallsBackToHttpsWhenNativeNotInstalled() {
        BibleDeepLink.testCanOpenURL = { _ in false }
        let passage = BibleDeepLink.Passage(bookId: "JHN", chapter: 3, verseStart: 16, verseEnd: nil)
        let url = BibleDeepLink.urlForOpening(
            appId: "youversion",
            passage: passage,
            translationId: "nvi-pt",
            preferNative: false,
            locale: "pt"
        )
        XCTAssertEqual(url?.absoluteString, "https://www.bible.com/bible/129/JHN.3.16")
    }

    // MARK: - Note pill opener (no /prefs or /bible/link)

    func testNotePillTap_opensLocalURLWithoutNetwork() {
        NativeSWR.resetAllForTests()
        NativeAPIClient.session = MockNativeURLProtocol.makeSession()
        MockNativeURLProtocol.reset()
        // Any hit to prefs / bible/link would be recorded — assert zero.
        NativeSWR.networkProbeEnabled = true
        NativeSWR.resetProbe()

        let prefs = NativeAPIClient.PrefsDTO(
            locale: "pt",
            copyLocale: "pt",
            appId: "youversion",
            translationId: "nvi-pt",
            preferNative: false,
            copyFormat: "default",
            citeBook: "abbr",
            citeSep: ":",
            booksCompact: false,
            theme: "system",
            activePlans: nil,
            planProgress: nil,
            avatarId: "",
            avatarUrl: "",
            handle: "",
            firstName: "",
            lastName: "",
            profileEmail: ""
        )
        NativeSWR.savePrefs(prefs)

        var opened: URL?
        BibleDeepLink.testOpenHandler = { opened = $0 }
        BibleDeepLink.testCanOpenURL = { _ in false }

        var note = NativeAPIClient.emptyNote(id: "bible-pill-open")
        note.title = "Test"
        note.body.blocks = [
            .init(
                id: "p1",
                type: "paragraph",
                spans: [
                    .init(
                        type: "bibleRef",
                        text: nil,
                        marks: nil,
                        bookId: "JHN",
                        chapter: 3,
                        verseStart: 16,
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
        ]
        let vc = NoteDetailViewController(noteId: note.id, initial: note)
        vc.loadViewIfNeeded()
        vc.openBibleRef(
            NoteDocumentCodec.BibleRefPayload(
                bookId: "JHN",
                chapter: 3,
                verseStart: 16,
                verseEnd: nil,
                text: nil
            )
        )

        XCTAssertEqual(opened?.absoluteString, "https://www.bible.com/bible/129/JHN.3.16")
        XCTAssertEqual(NativeSWR.probeCount(containing: "/prefs"), 0)
        XCTAssertEqual(NativeSWR.probeCount(containing: "/bible/link"), 0)
        XCTAssertEqual(MockNativeURLProtocol.readBodies.count, 0)
        XCTAssertEqual(MockNativeURLProtocol.postBodies.count, 0)
    }

    func testPillTapGesture_doesNotWaitForDoubleTap() {
        let editor = NativeNoteEditorView(frame: CGRect(x: 0, y: 0, width: 390, height: 720))
        editor.testing_prepare(size: CGSize(width: 390, height: 720))
        XCTAssertFalse(editor.testing_pillTapShouldRequireFailureOfDoubleTap())
        XCTAssertTrue(editor.testing_doubleTapShouldWaitForPillTap())
    }
}
