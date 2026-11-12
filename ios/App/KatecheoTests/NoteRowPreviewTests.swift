import XCTest
@testable import Katecheo

@MainActor
final class NoteRowPreviewTests: XCTestCase {
    func testNoteRow_subtitleAlignsWithTitle_whenSpeakerAbsent() {
        let cell = KCNoteRowCell(style: .default, reuseIdentifier: KCNoteRowCell.reuseId)
        let width: CGFloat = 390
        cell.frame = CGRect(x: 0, y: 0, width: width, height: 88)
        cell.configure(
            title: "Culto de domingo",
            subtitle: "12 nov · Passagem: Salmos 23",
            tags: [],
            speakerName: nil
        )
        cell.layoutIfNeeded()

        XCTAssertFalse(cell.testing_speakerPillInMetaRow)
        XCTAssertTrue(cell.testing_speakerPill.isHidden)

        let titleX = cell.testing_titleLabel.convert(cell.testing_titleLabel.bounds, to: cell.contentView).minX
        let subtitleX = cell.testing_subtitleLabel.convert(cell.testing_subtitleLabel.bounds, to: cell.contentView).minX
        XCTAssertEqual(titleX, subtitleX, accuracy: 0.5, "subtitle must align with title when there is no speaker")
    }

    func testNoteRow_subtitleFollowsPill_whenSpeakerPresent() {
        let cell = KCNoteRowCell(style: .default, reuseIdentifier: KCNoteRowCell.reuseId)
        cell.frame = CGRect(x: 0, y: 0, width: 390, height: 88)
        cell.configure(
            title: "Culto de domingo",
            subtitle: "12 nov · João 3:16",
            tags: ["igreja"],
            speakerName: "Pastor Ana"
        )
        cell.layoutIfNeeded()

        XCTAssertTrue(cell.testing_speakerPillInMetaRow)
        XCTAssertFalse(cell.testing_speakerPill.isHidden)

        let pillMaxX = cell.testing_speakerPill.convert(cell.testing_speakerPill.bounds, to: cell.contentView).maxX
        let subtitleMinX = cell.testing_subtitleLabel.convert(cell.testing_subtitleLabel.bounds, to: cell.contentView).minX
        XCTAssertGreaterThan(subtitleMinX, pillMaxX - 0.5, "subtitle starts after the speaker pill")
    }

    func testNoteRow_reuseFromSpeakerToNone_clearsGap() {
        let cell = KCNoteRowCell(style: .default, reuseIdentifier: KCNoteRowCell.reuseId)
        cell.frame = CGRect(x: 0, y: 0, width: 390, height: 88)
        cell.configure(title: "A", subtitle: "com speaker", tags: [], speakerName: "João")
        cell.layoutIfNeeded()
        XCTAssertTrue(cell.testing_speakerPillInMetaRow)

        cell.prepareForReuse()
        cell.configure(title: "B", subtitle: "sem speaker", tags: [], speakerName: nil)
        cell.layoutIfNeeded()

        XCTAssertFalse(cell.testing_speakerPillInMetaRow)
        let titleX = cell.testing_titleLabel.convert(cell.testing_titleLabel.bounds, to: cell.contentView).minX
        let subtitleX = cell.testing_subtitleLabel.convert(cell.testing_subtitleLabel.bounds, to: cell.contentView).minX
        XCTAssertEqual(titleX, subtitleX, accuracy: 0.5)
    }

    func testPreview_rendersBibleRefLabelInsteadOfStripping() {
        var note = NativeAPIClient.emptyNote(id: "preview-ref")
        note.title = "Estudo"
        note.body.blocks = [
            NativeAPIClient.LineBlock(
                id: "p1",
                type: "paragraph",
                spans: [
                    .init(type: "text", text: "Passagem: ", marks: nil, bookId: nil, chapter: nil, verseStart: nil, verseEnd: nil, href: nil),
                    .init(
                        type: "bibleRef",
                        text: "Salmos 23",
                        marks: nil,
                        bookId: "PSA",
                        chapter: 23,
                        verseStart: nil,
                        verseEnd: nil,
                        href: nil
                    ),
                    .init(type: "text", text: " · Texto: reflexão", marks: nil, bookId: nil, chapter: nil, verseStart: nil, verseEnd: nil, href: nil),
                ],
                speakerId: nil,
                title: nil,
                collapsed: nil,
                checked: nil,
                blocks: nil
            ),
        ]
        let preview = note.preview
        XCTAssertTrue(preview.contains("Passagem: Salmos 23"), preview)
        XCTAssertTrue(preview.contains("Texto: reflexão"), preview)
        XCTAssertFalse(preview.hasSuffix("Passagem:"), preview)
    }

    func testPreview_formatsMissingDisplayTextFromBookId() {
        let span = NativeAPIClient.TextSpan(
            type: "bibleRef",
            text: nil,
            marks: nil,
            bookId: "JHN",
            chapter: 15,
            verseStart: 1,
            verseEnd: 8,
            href: nil
        )
        let label = NativeAPIClient.NoteDocument.bibleRefPreviewLabel(span)
        XCTAssertEqual(label, BibleBookCatalog.formatPassage(
            bookId: "JHN",
            chapter: 15,
            verseStart: 1,
            verseEnd: 8
        ))
    }
}
