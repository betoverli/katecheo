import XCTest
@testable import App

@MainActor
final class NoteDocumentCodecTests: XCTestCase {
    func testEmptyNoteProducesStyledAttributeRuns() {
        let note = NativeAPIClient.emptyNote()
        let attributed = NoteDocumentCodec.attributedString(from: note)
        XCTAssertGreaterThan(attributed.length, 0, "Empty notes must keep real attribute runs for typingAttributes")

        let titleAttrs = attributed.attributes(at: 0, effectiveRange: nil)
        XCTAssertEqual(titleAttrs[NoteDocumentCodec.blockTypeKey] as? String, "heading")
        XCTAssertEqual(titleAttrs[NoteDocumentCodec.blockIdKey] as? String, "title")
        XCTAssertNotNil(titleAttrs[.font] as? UIFont)
        XCTAssertNotNil(titleAttrs[.paragraphStyle] as? NSParagraphStyle)
        XCTAssertEqual(titleAttrs[.foregroundColor] as? UIColor, .label)

        let style = titleAttrs[.paragraphStyle] as! NSParagraphStyle
        XCTAssertEqual(
            style.paragraphSpacing,
            NoteDocumentCodec.titleTagsReservedSpacing,
            accuracy: 0.1,
            "title reserves space for the tags strip"
        )
    }

    @MainActor
    func testListHangIndent_matchesMeasuredMarkerWidth() {
        let font = UIFont.preferredFont(forTextStyle: .body)
        let bulletW = NoteDocumentCodec.listMarkerWidth(type: "bullet", checked: nil, number: 1, font: font)
        let attrs = NoteDocumentCodec.baseAttributesPublic(
            type: "bullet",
            id: "b1",
            checked: nil,
            speakerId: nil,
            speakers: [:]
        )
        let style = attrs[.paragraphStyle] as! NSParagraphStyle
        XCTAssertEqual(style.firstLineHeadIndent, 0, accuracy: 0.5)
        XCTAssertEqual(style.headIndent, bulletW, accuracy: 0.5)

        let insetAttrs = NoteDocumentCodec.applyingSpeakerSectionInset(attrs)
        let insetStyle = insetAttrs[.paragraphStyle] as! NSParagraphStyle
        let inset = NoteDocumentCodec.speakerSectionContentInset
        XCTAssertEqual(insetStyle.firstLineHeadIndent, inset, accuracy: 0.5)
        XCTAssertEqual(insetStyle.headIndent, inset + bulletW, accuracy: 0.5)
    }

    func testPreview_stripsBibleRefs() {
        var note = NativeAPIClient.emptyNote()
        note.title = "Culto"
        note.body.blocks = [
            NativeAPIClient.LineBlock(
                id: "p1",
                type: "paragraph",
                spans: [
                    .init(type: "bibleRef", text: "Lc 14:26", marks: nil, bookId: "LUK", chapter: 14, verseStart: 26, verseEnd: nil, href: nil),
                    .init(type: "text", text: " amar a Deus", marks: nil, bookId: nil, chapter: nil, verseStart: nil, verseEnd: nil, href: nil),
                ],
                speakerId: nil,
                title: nil,
                collapsed: nil,
                checked: nil,
                blocks: nil
            ),
        ]
        XCTAssertEqual(note.preview, "amar a Deus")
        XCTAssertFalse(note.preview.contains("LUK"))
        XCTAssertFalse(note.preview.contains("14:26"))
    }

    func testRoundTripPreservesParagraphTextAndTypes() {
        var note = NativeAPIClient.emptyNote()
        note.title = "Culto domingo"
        note.body.blocks = [
            NativeAPIClient.LineBlock(
                id: "p1",
                type: "paragraph",
                spans: [.init(type: "text", text: "Olá mundo", marks: ["bold"], bookId: nil, chapter: nil, verseStart: nil, verseEnd: nil, href: nil)],
                speakerId: nil,
                title: nil,
                collapsed: nil,
                checked: nil,
                blocks: nil
            ),
            NativeAPIClient.LineBlock(
                id: "s1",
                type: "speakerSection",
                spans: nil,
                speakerId: "sp1",
                title: "João",
                collapsed: nil,
                checked: nil,
                blocks: [
                    NativeAPIClient.LineBlock(
                        id: "c1",
                        type: "paragraph",
                        spans: [.init(type: "text", text: "Dentro", marks: nil, bookId: nil, chapter: nil, verseStart: nil, verseEnd: nil, href: nil)],
                        speakerId: nil,
                        title: nil,
                        collapsed: nil,
                        checked: nil,
                        blocks: nil
                    ),
                ]
            ),
            NativeAPIClient.LineBlock(
                id: "p2",
                type: "paragraph",
                spans: [.init(type: "text", text: "Depois", marks: nil, bookId: nil, chapter: nil, verseStart: nil, verseEnd: nil, href: nil)],
                speakerId: nil,
                title: nil,
                collapsed: nil,
                checked: nil,
                blocks: nil
            ),
        ]

        let attributed = NoteDocumentCodec.attributedString(from: note)
        let roundTrip = NoteDocumentCodec.document(from: attributed, base: note)

        XCTAssertEqual(roundTrip.title, "Culto domingo")
        XCTAssertEqual(roundTrip.body.blocks.count, 3)
        XCTAssertEqual(roundTrip.body.blocks[0].type, "paragraph")
        XCTAssertEqual(roundTrip.body.blocks[0].spans?.first?.text, "Olá mundo")
        XCTAssertEqual(roundTrip.body.blocks[1].type, "speakerSection")
        XCTAssertEqual(roundTrip.body.blocks[1].title, "João")
        XCTAssertEqual(roundTrip.body.blocks[1].blocks?.count, 1)
        XCTAssertEqual(roundTrip.body.blocks[1].blocks?.first?.spans?.first?.text, "Dentro")
        XCTAssertEqual(roundTrip.body.blocks[2].type, "paragraph")
        XCTAssertEqual(roundTrip.body.blocks[2].spans?.first?.text, "Depois")

        // Second round-trip must stay stable (idempotent content).
        let again = NoteDocumentCodec.document(
            from: NoteDocumentCodec.attributedString(from: roundTrip),
            base: roundTrip
        )
        XCTAssertEqual(again.title, roundTrip.title)
        XCTAssertEqual(again.body.blocks.count, roundTrip.body.blocks.count)
        XCTAssertEqual(again.body.blocks[1].blocks?.first?.spans?.first?.text, "Dentro")
        XCTAssertEqual(again.body.blocks[2].spans?.first?.text, "Depois")
    }

    func testSpeakerBodyKeyMarksSectionChildrenOnly() {
        var note = NativeAPIClient.emptyNote()
        note.title = "T"
        note.body.blocks = [
            NativeAPIClient.LineBlock(
                id: "s1",
                type: "speakerSection",
                spans: nil,
                speakerId: nil,
                title: "Ana",
                collapsed: nil,
                checked: nil,
                blocks: [
                    NativeAPIClient.LineBlock(
                        id: "c1",
                        type: "paragraph",
                        spans: [.init(type: "text", text: "Linha", marks: nil, bookId: nil, chapter: nil, verseStart: nil, verseEnd: nil, href: nil)],
                        speakerId: nil,
                        title: nil,
                        collapsed: nil,
                        checked: nil,
                        blocks: nil
                    ),
                ]
            ),
        ]
        let attributed = NoteDocumentCodec.attributedString(from: note)
        let ns = attributed.string as NSString
        var foundBody = false
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byParagraphs) { _, range, _, _ in
            guard range.length > 0 else { return }
            let attrs = attributed.attributes(at: range.location, effectiveRange: nil)
            let type = attrs[NoteDocumentCodec.blockTypeKey] as? String
            if type == "paragraph", (attrs[NoteDocumentCodec.speakerBodyKey] as? Bool) == true {
                foundBody = true
            }
        }
        XCTAssertTrue(foundBody)
    }
}
