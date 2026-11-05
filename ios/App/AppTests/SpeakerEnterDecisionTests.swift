import XCTest
@testable import App

final class SpeakerEnterDecisionTests: XCTestCase {
    func testEnterOnHeaderInsertsBody() {
        let decision = SpeakerEnterDecision.decide(
            blockType: "speakerSection",
            insideSpeaker: true,
            paragraphEmpty: true,
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

    func testEnterOnNonEmptyBodyStaysInside() {
        let decision = SpeakerEnterDecision.decide(
            blockType: "paragraph",
            insideSpeaker: true,
            paragraphEmpty: false,
            isLastBodyOfSection: true
        )
        XCTAssertEqual(decision, .defaultNewline)
    }

    func testEnterOnEmptyNonLastBodyStaysInside() {
        let decision = SpeakerEnterDecision.decide(
            blockType: "paragraph",
            insideSpeaker: true,
            paragraphEmpty: true,
            isLastBodyOfSection: false
        )
        XCTAssertEqual(decision, .defaultNewline)
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
}
