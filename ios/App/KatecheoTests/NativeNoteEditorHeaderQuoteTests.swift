import XCTest
@testable import Katecheo

/// Header divider + quote block chrome (italic, single rounded fill, codec round-trip).
@MainActor
final class NativeNoteEditorHeaderQuoteTests: XCTestCase {
    private var editor: NativeNoteEditorView!

    override func setUp() async throws {
        try await super.setUp()
        editor = NativeNoteEditorView(frame: CGRect(x: 0, y: 0, width: 390, height: 720))
        editor.testing_prepare(size: CGSize(width: 390, height: 720))
    }

    override func tearDown() async throws {
        editor = nil
        try await super.tearDown()
    }

    private func blankNote(title: String, tags: [String] = []) -> NativeAPIClient.NoteDocument {
        var note = NativeAPIClient.emptyNote(id: "note-header-quote")
        note.title = title
        note.tags = tags
        note.body.blocks = [
            NativeAPIClient.LineBlock(
                id: "p1",
                type: "paragraph",
                spans: [],
                speakerId: nil,
                title: nil,
                collapsed: nil,
                checked: nil,
                blocks: nil
            ),
        ]
        return note
    }

    // MARK: - Header divider

    func testHeaderDivider_sitsBetweenTagsRowAndBody() {
        editor.pushNote(blankNote(title: "Culto", tags: ["manhã"]), speakers: [])
        editor.layoutIfNeeded()

        let tags = editor.testing_tagsStripFrame()
        let body = editor.testing_bodyPlaceholderFrame()
        let divider = editor.testing_headerDividerFrame()
        let leading = editor.testing_textContentLeading()

        XCTAssertEqual(divider.minX, leading, accuracy: 0.5)
        XCTAssertEqual(divider.width, tags.width, accuracy: 0.5)
        let expectedHeight: CGFloat = editor.effectiveEditorInterfaceStyle() == .dark
            ? 1
            : 1 / max(UIScreen.main.scale, 1)
        XCTAssertEqual(divider.height, expectedHeight, accuracy: 0.02)
        // Color token: dark is stronger than generic separator; light matches separator.
        let style = editor.effectiveEditorInterfaceStyle()
        let traits = UITraitCollection(userInterfaceStyle: style == .dark ? .dark : .light)
        let resolvedDivider = KCDesign.headerDivider.resolvedColor(with: traits)
        let resolvedSeparator = KCDesign.separator.resolvedColor(with: traits)
        var dr: CGFloat = 0, dg: CGFloat = 0, db: CGFloat = 0, da: CGFloat = 0
        var sr: CGFloat = 0, sg: CGFloat = 0, sb: CGFloat = 0, sa: CGFloat = 0
        XCTAssertTrue(resolvedDivider.getWhite(&dr, alpha: &da) || resolvedDivider.getRed(&dr, green: &dg, blue: &db, alpha: &da))
        XCTAssertTrue(resolvedSeparator.getWhite(&sr, alpha: &sa) || resolvedSeparator.getRed(&sr, green: &sg, blue: &sb, alpha: &sa))
        if style == .dark {
            XCTAssertEqual(da, 0.22, accuracy: 0.02)
            XCTAssertGreaterThan(da, sa)
        } else {
            XCTAssertEqual(da, sa, accuracy: 0.02)
        }
        XCTAssertGreaterThan(divider.minY, tags.maxY - 0.5, "divider below tags row")
        XCTAssertLessThan(divider.maxY, body.minY + 0.5, "divider above body caret/placeholder")
        // Balanced breathing room above/below inside the 48pt title band.
        let above = divider.minY - tags.maxY
        let below = body.minY - divider.maxY
        XCTAssertGreaterThan(above, 1)
        XCTAssertGreaterThan(below, 1)
        XCTAssertEqual(above, below, accuracy: 6)
    }

    func testHeaderDivider_staysBetweenHeaderAndBody_whenTagsCleared() {
        editor.pushNote(blankNote(title: "Culto", tags: ["a", "b"]), speakers: [])
        editor.layoutIfNeeded()
        editor.testing_setTags([])
        editor.layoutIfNeeded()

        let tags = editor.testing_tagsStripFrame()
        let body = editor.testing_bodyPlaceholderFrame()
        let divider = editor.testing_headerDividerFrame()

        // No chips → divider still under the title+tags header band, above the body.
        XCTAssertGreaterThanOrEqual(divider.minY, tags.minY - 1)
        XCTAssertLessThan(divider.maxY, body.minY + 0.5)
        XCTAssertEqual(NoteDocumentCodec.titleTagsReservedSpacing, 48, accuracy: 0.1)
    }

    // MARK: - Quote style

    func testQuoteAttributes_areItalicWithoutTextBackground() {
        let attrs = NoteDocumentCodec.baseAttributesPublic(
            type: "quote",
            id: "q1",
            checked: nil,
            speakerId: nil,
            speakers: [:]
        )
        let font = attrs[.font] as? UIFont
        XCTAssertNotNil(font)
        XCTAssertTrue(
            font!.fontDescriptor.symbolicTraits.contains(.traitItalic),
            "quote text must be italic"
        )
        XCTAssertNil(
            attrs[.backgroundColor],
            "quote must NOT set text-run backgroundColor — fill is layout-manager chrome only"
        )

        let style = attrs[.paragraphStyle] as? NSParagraphStyle
        XCTAssertNotNil(style)
        XCTAssertEqual(style!.firstLineHeadIndent, NoteDocumentCodec.quoteContentInset, accuracy: 0.5)
        XCTAssertEqual(style!.headIndent, NoteDocumentCodec.quoteContentInset, accuracy: 0.5)
    }

    func testQuoteBlock_appliesInEditorAndMergesConsecutiveLines() {
        editor.pushNote(blankNote(title: "Culto"), speakers: [])
        let storage = editor.testing_textStorage()
        editor.testing_setSelectedRange(NSRange(location: storage.length, length: 0))
        editor.testing_insertText("primeira")
        editor.testing_applyBlockTypeHook("quote")
        editor.testing_insertText("\n")
        editor.testing_insertText("segunda")

        XCTAssertEqual(editor.testing_paragraphBlockType(), "quote")
        let loc = max(0, editor.testing_selectedRange().location - 1)
        let attrs = editor.testing_textStorage().attributes(at: loc, effectiveRange: nil)
        let font = attrs[.font] as? UIFont
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.traitItalic) == true)
        XCTAssertNil(
            attrs[.backgroundColor],
            "editor quote text must not carry a second highlight behind the rounded block"
        )

        let blocks = editor.testing_quoteBlockRanges()
        XCTAssertFalse(blocks.isEmpty, "layout manager must track quote chrome ranges")
        XCTAssertEqual(blocks.count, 1, "consecutive quote lines form one continuous block")
    }

    func testQuote_roundTripsThroughCodec() {
        var note = blankNote(title: "Culto")
        note.body.blocks = [
            NativeAPIClient.LineBlock(
                id: "q1",
                type: "quote",
                spans: [
                    .init(
                        type: "text",
                        text: "Bem-aventurados os mansos",
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
            NativeAPIClient.LineBlock(
                id: "q2",
                type: "quote",
                spans: [
                    .init(
                        type: "text",
                        text: "porque eles herdarão a terra",
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
        ]

        let attributed = NoteDocumentCodec.attributedString(from: note)
        let specs = NoteDocumentCodec.quoteBlockSpecs(in: attributed)
        XCTAssertEqual(specs.count, 1, "adjacent quotes merge for chrome")

        let roundTrip = NoteDocumentCodec.document(from: attributed, base: note)
        XCTAssertEqual(roundTrip.body.blocks.count, 2)
        XCTAssertEqual(roundTrip.body.blocks[0].type, "quote")
        XCTAssertEqual(roundTrip.body.blocks[0].spans?.first?.text, "Bem-aventurados os mansos")
        XCTAssertEqual(roundTrip.body.blocks[1].type, "quote")
        XCTAssertEqual(roundTrip.body.blocks[1].spans?.first?.text, "porque eles herdarão a terra")

        // Loaded attrs keep italic + padding; fill is chrome-only (no text-run bg).
        let ns = attributed.string as NSString
        let quoteRange = ns.range(of: "Bem-aventurados")
        XCTAssertNotEqual(quoteRange.location, NSNotFound)
        let attrs = attributed.attributes(at: quoteRange.location, effectiveRange: nil)
        let font = attrs[.font] as? UIFont
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.traitItalic) == true)
        XCTAssertNil(attrs[.backgroundColor])
        let style = attrs[.paragraphStyle] as? NSParagraphStyle
        XCTAssertNotNil(style)
        XCTAssertEqual(style!.firstLineHeadIndent, NoteDocumentCodec.quoteContentInset, accuracy: 0.5)
    }

    func testQuoteBackground_resolvesForLightAndDark() {
        let light = UITraitCollection(userInterfaceStyle: .light)
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        let lightColor = NoteDocumentCodec.quoteBackgroundColor.resolvedColor(with: light)
        let darkColor = NoteDocumentCodec.quoteBackgroundColor.resolvedColor(with: dark)
        var lr: CGFloat = 0, lg: CGFloat = 0, lb: CGFloat = 0, la: CGFloat = 0
        var dr: CGFloat = 0, dg: CGFloat = 0, db: CGFloat = 0, da: CGFloat = 0
        XCTAssertTrue(lightColor.getRed(&lr, green: &lg, blue: &lb, alpha: &la))
        XCTAssertTrue(darkColor.getRed(&dr, green: &dg, blue: &db, alpha: &da))
        XCTAssertGreaterThan(la, 0.05)
        XCTAssertGreaterThan(da, 0.05)
        // Distinct resolutions — not a once-baked static color.
        XCTAssertFalse(
            abs(lr - dr) < 0.001 && abs(lg - dg) < 0.001 && abs(lb - db) < 0.001 && abs(la - da) < 0.001
        )
    }

    func testQuote_stripsTextBackgroundOnTraitRefresh() {
        var note = blankNote(title: "Culto")
        note.body.blocks = [
            NativeAPIClient.LineBlock(
                id: "q1",
                type: "quote",
                spans: [
                    .init(
                        type: "text",
                        text: "citação",
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
        ]
        editor.pushNote(note, speakers: [])
        editor.layoutIfNeeded()

        let storage = editor.testing_textStorage()
        let ns = storage.string as NSString
        let range = ns.range(of: "citação")
        XCTAssertNotEqual(range.location, NSNotFound)
        // Simulate a legacy bake that stamped a text-run highlight inside the block.
        storage.addAttribute(.backgroundColor, value: NoteDocumentCodec.quoteBackgroundColor, range: range)
        XCTAssertNotNil(storage.attribute(.backgroundColor, at: range.location, effectiveRange: nil))

        editor.overrideUserInterfaceStyle = .dark
        editor.testing_refreshAppearanceForCurrentTraits()
        XCTAssertNil(
            storage.attribute(.backgroundColor, at: range.location, effectiveRange: nil),
            "trait refresh must strip quote text-run background so only the rounded chrome remains"
        )
        XCTAssertEqual(editor.testing_quoteBlockRanges().count, 1)

        editor.overrideUserInterfaceStyle = .light
        editor.testing_refreshAppearanceForCurrentTraits()
        XCTAssertNil(storage.attribute(.backgroundColor, at: range.location, effectiveRange: nil))
        XCTAssertEqual(editor.testing_quoteBlockRanges().count, 1)
    }
}
