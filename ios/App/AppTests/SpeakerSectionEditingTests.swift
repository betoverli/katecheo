import XCTest
@testable import App

@MainActor
final class SpeakerSectionEditingTests: XCTestCase {
    private func makeStorageWithSpeaker(named name: String = "Beto") -> NSMutableAttributedString {
        var note = NativeAPIClient.emptyNote()
        note.title = "Nota"
        note.body.blocks = [
            NativeAPIClient.LineBlock(
                id: "s1",
                type: "speakerSection",
                spans: nil,
                speakerId: "sp1",
                title: name,
                collapsed: nil,
                checked: nil,
                blocks: []
            ),
        ]
        return NSMutableAttributedString(attributedString: NoteDocumentCodec.attributedString(from: note))
    }

    func testNameEnterThenTypeLandsInSpeakerBody() {
        let storage = makeStorageWithSpeaker()
        guard let header = SpeakerSectionEditing.findSpeakerHeaderRange(in: storage) else {
            return XCTFail("missing speaker header")
        }
        XCTAssertEqual(SpeakerSectionEditing.blockType(in: storage, at: header.location), "speakerSection")

        // Enter on the name line → body inside the section.
        let afterEnter = SpeakerSectionEditing.insertBodyAfterHeader(in: storage, headerRange: header)
        XCTAssertTrue(NoteDocumentCodec.isSpeakerBody(afterEnter.typingAttributes))
        XCTAssertEqual(afterEnter.typingAttributes[NoteDocumentCodec.blockTypeKey] as? String, "paragraph")

        // Type body text.
        let caret = SpeakerSectionEditing.typeText(
            "corpo da seção",
            in: storage,
            at: afterEnter.caret,
            attributes: afterEnter.typingAttributes
        )
        XCTAssertTrue(SpeakerSectionEditing.isSpeakerBody(in: storage, at: caret - 1))

        let doc = NoteDocumentCodec.document(
            from: storage,
            base: NativeAPIClient.emptyNote()
        )
        XCTAssertEqual(doc.body.blocks.count, 1)
        XCTAssertEqual(doc.body.blocks[0].type, "speakerSection")
        XCTAssertEqual(doc.body.blocks[0].title, "Beto")
        XCTAssertEqual(doc.body.blocks[0].blocks?.count, 1)
        XCTAssertEqual(doc.body.blocks[0].blocks?.first?.spans?.first?.text, "corpo da seção")
    }

    func testBodyEnterThenTypeStaysInside() {
        let storage = makeStorageWithSpeaker()
        let header = SpeakerSectionEditing.findSpeakerHeaderRange(in: storage)!
        var state = SpeakerSectionEditing.insertBodyAfterHeader(in: storage, headerRange: header)
        state.caret = SpeakerSectionEditing.typeText(
            "primeira",
            in: storage,
            at: state.caret,
            attributes: state.typingAttributes
        )

        // Enter inside non-empty body → another body paragraph still in the section.
        let para = SpeakerSectionEditing.paragraphRange(in: storage, at: state.caret)
        let continued = SpeakerSectionEditing.insertContinuingBodyParagraph(in: storage, paragraphRange: para)
        XCTAssertTrue(NoteDocumentCodec.isSpeakerBody(continued.typingAttributes))

        _ = SpeakerSectionEditing.typeText(
            "segunda",
            in: storage,
            at: continued.caret,
            attributes: continued.typingAttributes
        )

        let doc = NoteDocumentCodec.document(from: storage, base: NativeAPIClient.emptyNote())
        XCTAssertEqual(doc.body.blocks.count, 1)
        XCTAssertEqual(doc.body.blocks[0].type, "speakerSection")
        XCTAssertEqual(doc.body.blocks[0].blocks?.count, 2)
        XCTAssertEqual(doc.body.blocks[0].blocks?[0].spans?.first?.text, "primeira")
        XCTAssertEqual(doc.body.blocks[0].blocks?[1].spans?.first?.text, "segunda")
    }

    func testEnterOnEmptyLastBodyExitsSection() {
        let storage = makeStorageWithSpeaker()
        let header = SpeakerSectionEditing.findSpeakerHeaderRange(in: storage)!
        var state = SpeakerSectionEditing.insertBodyAfterHeader(in: storage, headerRange: header)
        state.caret = SpeakerSectionEditing.typeText(
            "dentro",
            in: storage,
            at: state.caret,
            attributes: state.typingAttributes
        )
        let afterContent = SpeakerSectionEditing.paragraphRange(in: storage, at: state.caret)
        let emptyBody = SpeakerSectionEditing.insertContinuingBodyParagraph(
            in: storage,
            paragraphRange: afterContent
        )

        // Empty last body + Enter → exit.
        let decision = SpeakerEnterDecision.decide(
            blockType: "paragraph",
            insideSpeaker: true,
            paragraphEmpty: true,
            isLastBodyOfSection: true
        )
        XCTAssertEqual(decision, .exitSection)

        let emptyPara = SpeakerSectionEditing.paragraphRange(in: storage, at: emptyBody.caret)
        let exited = SpeakerSectionEditing.exitSection(in: storage, emptyBodyRange: emptyPara)
        XCTAssertFalse(NoteDocumentCodec.isSpeakerBody(exited.typingAttributes))

        _ = SpeakerSectionEditing.typeText(
            "fora",
            in: storage,
            at: exited.caret,
            attributes: exited.typingAttributes
        )

        let doc = NoteDocumentCodec.document(from: storage, base: NativeAPIClient.emptyNote())
        XCTAssertEqual(doc.body.blocks.count, 2)
        XCTAssertEqual(doc.body.blocks[0].type, "speakerSection")
        XCTAssertEqual(doc.body.blocks[0].blocks?.first?.spans?.first?.text, "dentro")
        XCTAssertEqual(doc.body.blocks[1].type, "paragraph")
        XCTAssertEqual(doc.body.blocks[1].spans?.first?.text, "fora")
    }

    func testRoundTripSpeakerBodyThroughNoteDocumentV1() {
        let storage = makeStorageWithSpeaker(named: "Ana")
        let header = SpeakerSectionEditing.findSpeakerHeaderRange(in: storage)!
        var state = SpeakerSectionEditing.insertBodyAfterHeader(in: storage, headerRange: header)
        state.caret = SpeakerSectionEditing.typeText(
            "mensagem",
            in: storage,
            at: state.caret,
            attributes: state.typingAttributes
        )

        let first = NoteDocumentCodec.document(from: storage, base: NativeAPIClient.emptyNote())
        let reloaded = NoteDocumentCodec.attributedString(from: first)
        let second = NoteDocumentCodec.document(from: reloaded, base: first)

        XCTAssertEqual(second.body.blocks.count, 1)
        XCTAssertEqual(second.body.blocks[0].type, "speakerSection")
        XCTAssertEqual(second.body.blocks[0].title, "Ana")
        XCTAssertEqual(second.body.blocks[0].blocks?.count, 1)
        XCTAssertEqual(second.body.blocks[0].blocks?.first?.spans?.first?.text, "mensagem")
    }
}
