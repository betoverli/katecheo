import XCTest
@testable import App

@MainActor
final class SpeakerSectionEditingTests: XCTestCase {
    func testInsertSpeakerBlock_bareNote_noBlankBeforeHeader() {
        var note = NativeAPIClient.emptyNote()
        note.title = "Nota"
        note.body.blocks = [
            NativeAPIClient.LineBlock(
                id: "p0",
                type: "paragraph",
                spans: [],
                speakerId: nil,
                title: nil,
                collapsed: nil,
                checked: nil,
                blocks: nil
            ),
        ]
        let result = SpeakerSectionEditing.insertSpeakerBlock(
            into: note,
            speakerId: "sp1",
            speakerName: "Beto",
            afterBlockId: "p0"
        )
        XCTAssertEqual(result.document.body.blocks.first?.type, "speakerSection")
        XCTAssertEqual(result.document.body.blocks.first?.blocks?.count, 1)
        XCTAssertEqual(result.document.body.blocks.count, 2, "section + trailing empty line")
        XCTAssertEqual(result.document.body.blocks[1].type, "paragraph")
    }

    func testInsertSpeakerBlock_afterNormalLine_keepsThatLine() {
        var note = NativeAPIClient.emptyNote()
        note.title = "Nota"
        note.body.blocks = [
            NativeAPIClient.LineBlock(
                id: "p1",
                type: "paragraph",
                spans: [.init(type: "text", text: "linha", marks: nil, bookId: nil, chapter: nil, verseStart: nil, verseEnd: nil, href: nil)],
                speakerId: nil,
                title: nil,
                collapsed: nil,
                checked: nil,
                blocks: nil
            ),
        ]
        let result = SpeakerSectionEditing.insertSpeakerBlock(
            into: note,
            speakerId: "sp1",
            speakerName: "Ana",
            afterBlockId: "p1"
        )
        XCTAssertEqual(result.document.body.blocks[0].type, "paragraph")
        XCTAssertEqual(result.document.body.blocks[0].spans?.first?.text, "linha")
        XCTAssertEqual(result.document.body.blocks[1].type, "speakerSection")
        XCTAssertFalse(
            result.document.body.blocks.contains { $0.type == "speakerSection" && $0.title == "Speaker" && ($0.blocks ?? []).isEmpty },
            "must not invent phantom blank speaker sections"
        )
    }

    func testContinueEnter_createsExactlyOneBodyParagraph() {
        var note = NativeAPIClient.emptyNote()
        note.title = "Nota"
        note.body.blocks = [
            NativeAPIClient.LineBlock(
                id: "s1",
                type: "speakerSection",
                spans: nil,
                speakerId: "sp1",
                title: "Beto",
                collapsed: nil,
                checked: nil,
                blocks: [
                    NativeAPIClient.LineBlock(
                        id: "c1",
                        type: "paragraph",
                        spans: [.init(type: "text", text: "um", marks: nil, bookId: nil, chapter: nil, verseStart: nil, verseEnd: nil, href: nil)],
                        speakerId: nil,
                        title: nil,
                        collapsed: nil,
                        checked: nil,
                        blocks: nil
                    ),
                ]
            ),
            // Trailing outside line — Enter must not glue the new body ZWSP onto this.
            NativeAPIClient.LineBlock(
                id: "p-after",
                type: "paragraph",
                spans: [],
                speakerId: nil,
                title: nil,
                collapsed: nil,
                checked: nil,
                blocks: nil
            ),
        ]
        let storage = NSMutableAttributedString(attributedString: NoteDocumentCodec.attributedString(from: note))
        // Caret at end of "um" (on/before the paragraph terminator).
        guard let header = SpeakerSectionEditing.findSpeakerHeaderRange(in: storage) else {
            return XCTFail("missing header")
        }
        let bodyStart = NSMaxRange(header)
        let bodyPara = SpeakerSectionEditing.paragraphRange(in: storage, at: bodyStart)
        let bodyText = (storage.string as NSString).substring(with: bodyPara)
        let caret = NSMaxRange(bodyPara) - (bodyText.hasSuffix("\n") ? 1 : 0)
        let beforeParas = paragraphCount(storage)
        _ = SpeakerSectionEditing.insertContinuingBodyParagraph(in: storage, at: caret)
        let afterParas = paragraphCount(storage)
        XCTAssertEqual(afterParas, beforeParas + 1, "one Enter must add exactly one paragraph")
        let doc = NoteDocumentCodec.document(from: storage, base: note)
        let bodyTexts = (doc.body.blocks.first(where: { $0.type == "speakerSection" })?.blocks ?? [])
            .map { ($0.spans ?? []).compactMap(\.text).joined() }
            .map { $0.replacingOccurrences(of: "\u{200B}", with: "") }
        XCTAssertEqual(bodyTexts.filter { !$0.isEmpty }, ["um"])
        XCTAssertGreaterThanOrEqual(
            (doc.body.blocks.first(where: { $0.type == "speakerSection" })?.blocks ?? []).count,
            2,
            "Enter must seed a second empty body child"
        )
    }

    func testMidParagraphSplit_preservesFollowingParagraph() {
        var note = NativeAPIClient.emptyNote()
        note.title = "Nota"
        note.body.blocks = [
            NativeAPIClient.LineBlock(
                id: "s1",
                type: "speakerSection",
                spans: nil,
                speakerId: "sp1",
                title: "Beto",
                collapsed: nil,
                checked: nil,
                blocks: [
                    NativeAPIClient.LineBlock(
                        id: "c1",
                        type: "paragraph",
                        spans: [.init(type: "text", text: "AAAA BBBB", marks: nil, bookId: nil, chapter: nil, verseStart: nil, verseEnd: nil, href: nil)],
                        speakerId: nil,
                        title: nil,
                        collapsed: nil,
                        checked: nil,
                        blocks: nil
                    ),
                    NativeAPIClient.LineBlock(
                        id: "c2",
                        type: "paragraph",
                        spans: [.init(type: "text", text: "CCCC", marks: nil, bookId: nil, chapter: nil, verseStart: nil, verseEnd: nil, href: nil)],
                        speakerId: nil,
                        title: nil,
                        collapsed: nil,
                        checked: nil,
                        blocks: nil
                    ),
                ]
            ),
        ]
        let storage = NSMutableAttributedString(attributedString: NoteDocumentCodec.attributedString(from: note))
        let ns = storage.string as NSString
        let range = ns.range(of: "BBBB")
        XCTAssertNotEqual(range.location, NSNotFound)
        _ = SpeakerSectionEditing.insertContinuingBodyParagraph(in: storage, at: range.location)
        let doc = NoteDocumentCodec.document(from: storage, base: note)
        let texts = (doc.body.blocks.first?.blocks ?? []).map {
            ($0.spans ?? []).compactMap(\.text).joined()
        }.filter { !$0.isEmpty }
        XCTAssertEqual(texts, ["AAAA", "BBBB", "CCCC"])
    }

    func testInsertSpeaker_replacesEmptyTrailingBetweenSections() {
        var note = NativeAPIClient.emptyNote()
        note.title = "Nota"
        note.body.blocks = [
            NativeAPIClient.LineBlock(
                id: "s1",
                type: "speakerSection",
                spans: nil,
                speakerId: "sp1",
                title: "Beto",
                collapsed: nil,
                checked: nil,
                blocks: [
                    NativeAPIClient.LineBlock(
                        id: "c1",
                        type: "paragraph",
                        spans: [],
                        speakerId: nil,
                        title: nil,
                        collapsed: nil,
                        checked: nil,
                        blocks: nil
                    ),
                ]
            ),
            NativeAPIClient.LineBlock(
                id: "trail",
                type: "paragraph",
                spans: [],
                speakerId: nil,
                title: nil,
                collapsed: nil,
                checked: nil,
                blocks: nil
            ),
        ]
        let result = SpeakerSectionEditing.insertSpeakerBlock(
            into: note,
            speakerId: "sp2",
            speakerName: "Ana",
            afterBlockId: "trail"
        )
        let types = result.document.body.blocks.map(\.type)
        XCTAssertEqual(types.filter { $0 == "speakerSection" }.count, 2)
        if let i0 = types.firstIndex(of: "speakerSection"),
           let i1 = types.lastIndex(of: "speakerSection"),
           i1 > i0
        {
            XCTAssertTrue(
                Array(types[(i0 + 1)..<i1]).allSatisfy { $0 == "speakerSection" },
                "no blank between sections: \(types)"
            )
        }
    }

    func testExitOnEmptyLastBody() {
        var note = NativeAPIClient.emptyNote()
        note.title = "Nota"
        note.body.blocks = [
            NativeAPIClient.LineBlock(
                id: "s1",
                type: "speakerSection",
                spans: nil,
                speakerId: "sp1",
                title: "Beto",
                collapsed: nil,
                checked: nil,
                blocks: [
                    NativeAPIClient.LineBlock(
                        id: "c1",
                        type: "paragraph",
                        spans: [.init(type: "text", text: "dentro", marks: nil, bookId: nil, chapter: nil, verseStart: nil, verseEnd: nil, href: nil)],
                        speakerId: nil,
                        title: nil,
                        collapsed: nil,
                        checked: nil,
                        blocks: nil
                    ),
                    NativeAPIClient.LineBlock(
                        id: "c2",
                        type: "paragraph",
                        spans: [],
                        speakerId: nil,
                        title: nil,
                        collapsed: nil,
                        checked: nil,
                        blocks: nil
                    ),
                ]
            ),
        ]
        let storage = NSMutableAttributedString(attributedString: NoteDocumentCodec.attributedString(from: note))
        // Find last body paragraph
        let ns = storage.string as NSString
        var lastBody: NSRange?
        var cursor = 0
        while cursor < ns.length {
            let para = ns.paragraphRange(for: NSRange(location: cursor, length: 0))
            let attrs = storage.attributes(at: para.location, effectiveRange: nil)
            if NoteDocumentCodec.isSpeakerBody(attrs),
               (attrs[NoteDocumentCodec.blockTypeKey] as? String) != "speakerSection"
            {
                lastBody = para
            }
            let next = NSMaxRange(para)
            if next <= cursor { break }
            cursor = next
        }
        guard let empty = lastBody else { return XCTFail("no body") }
        _ = SpeakerSectionEditing.exitSection(in: storage, emptyBodyRange: empty, removeEmptyBody: true)
        let doc = NoteDocumentCodec.document(from: storage, base: note)
        XCTAssertEqual(doc.body.blocks.first?.type, "speakerSection")
        XCTAssertEqual(doc.body.blocks.first?.blocks?.first?.spans?.first?.text, "dentro")
        XCTAssertTrue(doc.body.blocks.contains { $0.type == "paragraph" })
    }

    private func paragraphCount(_ storage: NSAttributedString) -> Int {
        let ns = storage.string as NSString
        var count = 0
        var cursor = 0
        while cursor < ns.length {
            let para = ns.paragraphRange(for: NSRange(location: cursor, length: 0))
            count += 1
            let next = NSMaxRange(para)
            if next <= cursor { break }
            cursor = next
        }
        return count
    }
}
