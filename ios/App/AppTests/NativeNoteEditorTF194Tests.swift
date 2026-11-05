import XCTest
@testable import App

/// Real `NativeNoteEditorView` / UITextView coverage for TestFlight 194 bugs.
@MainActor
final class NativeNoteEditorTF194Tests: XCTestCase {
    private var editor: NativeNoteEditorView!
    private let speakers = [
        NativeAPIClient.SpeakerDTO(
            id: "sp1",
            name: "Beto",
            color: "#C4A574",
            updatedAt: "2026-01-01T00:00:00Z"
        ),
        NativeAPIClient.SpeakerDTO(
            id: "sp2",
            name: "Ana",
            color: "#8B7355",
            updatedAt: "2026-01-01T00:00:00Z"
        ),
    ]

    override func setUp() async throws {
        try await super.setUp()
        editor = NativeNoteEditorView(frame: .zero)
        editor.testing_prepare()
        var note = NativeAPIClient.emptyNote(id: "note-tf194")
        note.title = "Culto"
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
        editor.pushNote(note, speakers: speakers)
        let storage = editor.testing_textStorage()
        editor.testing_setSelectedRange(NSRange(location: storage.length, length: 0))
    }

    override func tearDown() async throws {
        editor = nil
        try await super.tearDown()
    }

    private func indentPair(at location: Int) -> (first: CGFloat, head: CGFloat) {
        let storage = editor.testing_textStorage()
        let loc = min(max(0, location), max(0, storage.length - 1))
        let style = storage.attributes(at: loc, effectiveRange: nil)[.paragraphStyle] as? NSParagraphStyle
        return (style?.firstLineHeadIndent ?? -1, style?.headIndent ?? -1)
    }

    private func paragraphStarts() -> [Int] {
        let ns = editor.testing_textStorage().string as NSString
        var starts: [Int] = []
        var cursor = 0
        while cursor < ns.length {
            let para = ns.paragraphRange(for: NSRange(location: cursor, length: 0))
            starts.append(para.location)
            let next = NSMaxRange(para)
            if next <= cursor { break }
            cursor = next
        }
        return starts
    }

    // Bugs 1–2: exit section → flush outside; wraps share first-line indent.
    func testExitSection_outsideParagraphsStayFlushAndAligned() {
        editor.insertSpeakerSection(speakerId: "sp1", name: "Beto")
        editor.testing_insertText("dentro")
        editor.testing_insertText("\n")
        editor.testing_insertText("\n") // exit
        editor.testing_insertText("fora1")
        let afterExit = editor.testing_selectedRange().location - 1
        let (first1, head1) = indentPair(at: afterExit)
        XCTAssertEqual(first1, 0, accuracy: 0.5, "first outside para must be flush")
        XCTAssertEqual(head1, 0, accuracy: 0.5)
        XCTAssertEqual(first1, head1, accuracy: 0.5)

        editor.testing_insertText("\n")
        editor.testing_insertText("fora2")
        let afterSecond = editor.testing_selectedRange().location - 1
        let (first2, head2) = indentPair(at: afterSecond)
        XCTAssertEqual(first2, 0, accuracy: 0.5, "second outside para must stay flush (TF194 #1)")
        XCTAssertEqual(head2, 0, accuracy: 0.5)
        XCTAssertEqual(first2, head2, accuracy: 0.5)
    }

    func testSpeakerBodyLines_shareEqualIndent() {
        editor.insertSpeakerSection(speakerId: "sp1", name: "Beto")
        editor.testing_insertText("corpo longo")
        let loc = editor.testing_selectedRange().location - 1
        let (first, head) = indentPair(at: loc)
        XCTAssertGreaterThan(first, 0)
        XCTAssertEqual(first, head, accuracy: 0.5, "no hanging indent inside speaker body (TF194 #2)")
    }

    // Bug 4: lists continue; empty item ends list.
    func testListEnter_continuesThenEmptyExits() {
        // Land explicitly on the body paragraph (not the title).
        let storage = editor.testing_textStorage()
        let ns = storage.string as NSString
        let lastPara = ns.paragraphRange(for: NSRange(location: max(0, ns.length - 1), length: 0))
        editor.testing_setSelectedRange(NSRange(location: lastPara.location, length: 0))
        editor.testing_insertText("item")
        applyBlockTypeForTest("bullet")
        XCTAssertEqual(
            editor.testing_paragraphBlockType(),
            "bullet",
            "after promote; plain=\(editor.testing_textStorage().string.debugDescription)"
        )
        editor.testing_insertText("\n")
        XCTAssertEqual(
            editor.testing_paragraphBlockType(),
            "bullet",
            "Enter continues bullet list; plain=\(editor.testing_textStorage().string.debugDescription)"
        )
        // Second Enter on the new empty item ends the list (web empty ul → p).
        editor.testing_insertText("\n")
        XCTAssertEqual(
            editor.testing_paragraphBlockType(),
            "paragraph",
            "empty list item ends list; plain=\(editor.testing_textStorage().string.debugDescription)"
        )
    }

    // Bug 5–6: header hit metrics.
    func testSpeakerHeader_chevronLeftAndRemoveHitAtLeast44() {
        editor.insertSpeakerSection(speakerId: "sp1", name: "Beto")
        guard let header = SpeakerSectionEditing.findSpeakerHeaderRange(in: editor.testing_textStorage()),
              let attachment = editor.testing_headerAttachment(at: header.location)
        else {
            return XCTFail("missing header attachment")
        }
        // Force layout metrics without relying on UITextView layout (avoids CI flakes).
        attachment.refreshImage(width: 320)
        let hitWidth = (1 - attachment.removeStartX) * 320
        XCTAssertGreaterThanOrEqual(hitWidth, 44, "× hit band must be ≥44pt; removeStartX=\(attachment.removeStartX)")
        XCTAssertGreaterThanOrEqual(attachment.bounds.height, 44)
        // padL=4 + chevron 10 + gap 8 = 22pt from the left.
        XCTAssertLessThanOrEqual(attachment.chevronEndX * 320, 24, "chevron+name nudged left")
    }

    // Bug 10: mid-paragraph split must not merge the following paragraph.
    func testMidParagraphEnter_doesNotMergeFollowingParagraph() {
        editor.testing_insertText("AAAA BBBB")
        editor.testing_insertText("\n")
        editor.testing_insertText("CCCC")
        let storage = editor.testing_textStorage()
        let ns = storage.string as NSString
        let range = ns.range(of: "BBBB")
        XCTAssertNotEqual(range.location, NSNotFound, "missing BBBB")
        editor.testing_setSelectedRange(NSRange(location: range.location, length: 0))
        editor.testing_insertText("\n")
        let doc = editor.currentDocument()
        let texts = doc.body.blocks.compactMap { block -> String? in
            let t = (block.spans ?? []).compactMap(\.text).joined()
                .replacingOccurrences(of: "\u{200B}", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        XCTAssertEqual(texts, ["AAAA", "BBBB", "CCCC"], "got \(texts)")
    }

    // Bug 11: back-to-back sections — no blank between.
    func testInsertSectionAfterSection_noBlankBetween() {
        editor.insertSpeakerSection(speakerId: "sp1", name: "Beto")
        // Move caret onto the trailing empty outside line (simulates leaving the section).
        let doc1 = editor.currentDocument()
        XCTAssertEqual(doc1.body.blocks.filter { $0.type == "speakerSection" }.count, 1)
        // Place selection at end (trailing empty) then insert another section.
        let storage = editor.testing_textStorage()
        editor.testing_setSelectedRange(NSRange(location: storage.length, length: 0))
        editor.insertSpeakerSection(speakerId: "sp2", name: "Ana")
        let doc = editor.currentDocument()
        let types = doc.body.blocks.map(\.type)
        XCTAssertEqual(
            types.filter { $0 == "speakerSection" }.count,
            2,
            "types=\(types)"
        )
        // No empty paragraph between the two speaker sections.
        if let i0 = types.firstIndex(of: "speakerSection"),
           let i1 = types.lastIndex(of: "speakerSection"),
           i1 > i0
        {
            let between = types[(i0 + 1)..<i1]
            XCTAssertTrue(
                between.allSatisfy { $0 == "speakerSection" },
                "blank between sections: \(types)"
            )
        }
    }

    // Bug 3: confirm path is wired (testing seam still deletes without UI).
    func testRemoveSection_testingSeamStillDeletes() {
        editor.insertSpeakerSection(speakerId: "sp1", name: "Beto")
        editor.testing_insertText("x")
        guard let id = editor.currentDocument().body.blocks.first(where: { $0.type == "speakerSection" })?.id
        else { return XCTFail("missing") }
        editor.testing_removeSection(sectionId: id)
        XCTAssertFalse(editor.currentDocument().body.blocks.contains { $0.type == "speakerSection" })
    }

    private func applyBlockTypeForTest(_ type: String) {
        editor.testing_applyBlockTypeHook(type)
    }
}
