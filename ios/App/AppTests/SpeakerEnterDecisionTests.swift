import XCTest
@testable import App

final class SpeakerEnterDecisionTests: XCTestCase {
    func testEnterOnHeaderInsertsBody() {
        let decision = SpeakerEnterDecision.decide(
            blockType: "speakerSection",
            insideSpeaker: true,
            paragraphEmpty: false,
            isLastBodyOfSection: true
        )
        XCTAssertEqual(decision, .insertBodyFromHeader)
    }

    func testEnterOnEmptyLastBodyExits() {
        let decision = SpeakerEnterDecision.decide(
            blockType: "paragraph",
            insideSpeaker: true,
            paragraphEmpty: true,
            isLastBodyOfSection: true
        )
        XCTAssertEqual(decision, .exitSection)
    }

    func testEnterOnNonEmptyBodyContinuesInSection() {
        let decision = SpeakerEnterDecision.decide(
            blockType: "paragraph",
            insideSpeaker: true,
            paragraphEmpty: false,
            isLastBodyOfSection: true
        )
        XCTAssertEqual(decision, .continueInSection)
    }

    func testEnterOnEmptyNonLastBodyContinuesInSection() {
        let decision = SpeakerEnterDecision.decide(
            blockType: "paragraph",
            insideSpeaker: true,
            paragraphEmpty: true,
            isLastBodyOfSection: false
        )
        XCTAssertEqual(decision, .continueInSection)
    }

    func testEmptyListDemotesBeforeExit() {
        let decision = SpeakerEnterDecision.decide(
            blockType: "bullet",
            insideSpeaker: true,
            paragraphEmpty: true,
            isLastBodyOfSection: true
        )
        XCTAssertEqual(decision, .demoteListToParagraph)
    }

    func testListContinueOutsideSpeaker() {
        let decision = SpeakerEnterDecision.decide(
            blockType: "numbered",
            insideSpeaker: false,
            paragraphEmpty: false,
            isLastBodyOfSection: false
        )
        XCTAssertEqual(decision, .continueList("numbered"))
    }

    func testNewlineReplacementAcceptsCRAndCRLF() {
        XCTAssertTrue(NativeNoteEditorView.isNewlineReplacement("\n"))
        XCTAssertTrue(NativeNoteEditorView.isNewlineReplacement("\r"))
        XCTAssertTrue(NativeNoteEditorView.isNewlineReplacement("\r\n"))
        XCTAssertFalse(NativeNoteEditorView.isNewlineReplacement("a"))
    }

    func testDemotedTrailingRunStillInsertsBodyWhenParagraphStartIsHeader() {
        // Mirrors the live bug: caret character looks like paragraph, paragraph start is speakerSection.
        let decision = SpeakerEnterDecision.decide(
            blockType: "speakerSection",
            insideSpeaker: true,
            paragraphEmpty: false,
            isLastBodyOfSection: true
        )
        XCTAssertEqual(decision, .insertBodyFromHeader)
    }
}
