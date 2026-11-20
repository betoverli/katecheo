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
            subtitle: "Passagem reflexão sobre Salmos",
            tags: [],
            speakerName: nil,
            date: "Hoje"
        )
        cell.layoutIfNeeded()

        XCTAssertFalse(cell.testing_speakerPillInTagsRow)
        XCTAssertTrue(cell.testing_speakerPill.isHidden)
        XCTAssertTrue(cell.testing_tagsRow.isHidden)
        XCTAssertEqual(cell.testing_dateLabel.text, "Hoje")
        XCTAssertFalse(cell.testing_dateLabel.isHidden)

        let titleX = cell.testing_titleLabel.convert(cell.testing_titleLabel.bounds, to: cell.contentView).minX
        let subtitleX = cell.testing_subtitleLabel.convert(cell.testing_subtitleLabel.bounds, to: cell.contentView).minX
        XCTAssertEqual(titleX, subtitleX, accuracy: 0.5, "subtitle must align with title when there is no speaker")

        let dateMaxX = cell.testing_dateLabel.convert(cell.testing_dateLabel.bounds, to: cell.contentView).maxX
        let titleMaxX = cell.testing_titleLabel.convert(cell.testing_titleLabel.bounds, to: cell.contentView).maxX
        XCTAssertGreaterThan(dateMaxX, titleMaxX - 0.5, "date sits to the right of the title")
    }

    func testNoteRow_subtitleFollowsPill_whenSpeakerPresent() {
        let cell = KCNoteRowCell(style: .default, reuseIdentifier: KCNoteRowCell.reuseId)
        cell.frame = CGRect(x: 0, y: 0, width: 390, height: 110)
        cell.configure(
            title: "Culto de domingo",
            subtitle: "reflexão",
            tags: ["igreja"],
            speakerName: "Pastor Ana",
            date: "12 nov"
        )
        cell.layoutIfNeeded()

        XCTAssertTrue(cell.testing_speakerPillInTagsRow)
        XCTAssertFalse(cell.testing_speakerPill.isHidden)
        XCTAssertFalse(cell.testing_tagsRow.isHidden)
        let pillName = cell.testing_speakerPill.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        XCTAssertEqual(pillName, "Pastor Ana")
        XCTAssertGreaterThan(cell.testing_speakerPill.bounds.width, 1)
        XCTAssertGreaterThan(cell.testing_speakerPill.bounds.height, 1)
        XCTAssertGreaterThan(cell.testing_speakerPill.alpha, 0.99)

        let titleX = cell.testing_titleLabel.convert(cell.testing_titleLabel.bounds, to: cell.contentView).minX
        let subtitleX = cell.testing_subtitleLabel.convert(cell.testing_subtitleLabel.bounds, to: cell.contentView).minX
        XCTAssertEqual(titleX, subtitleX, accuracy: 0.5, "preview stays full-width and aligned with title")

        let pillMinY = cell.testing_speakerPill.convert(cell.testing_speakerPill.bounds, to: cell.contentView).minY
        let subtitleMaxY = cell.testing_subtitleLabel.convert(cell.testing_subtitleLabel.bounds, to: cell.contentView).maxY
        XCTAssertGreaterThan(pillMinY, subtitleMaxY - 0.5, "speaker pill sits on the tags row below the preview")

        let tagsMinX = cell.testing_tagsLabel.convert(cell.testing_tagsLabel.bounds, to: cell.contentView).minX
        let pillMaxX = cell.testing_speakerPill.convert(cell.testing_speakerPill.bounds, to: cell.contentView).maxX
        XCTAssertGreaterThan(tagsMinX, pillMaxX - 0.5, "tags follow the speaker pill on the same row")
    }

    func testNoteRow_speakerPillAlone_whenNoTags() {
        let cell = KCNoteRowCell(style: .default, reuseIdentifier: KCNoteRowCell.reuseId)
        cell.frame = CGRect(x: 0, y: 0, width: 390, height: 110)
        cell.configure(
            title: "Culto",
            subtitle: "texto do preview",
            tags: [],
            speakerName: "João",
            date: "Ontem"
        )
        cell.layoutIfNeeded()

        XCTAssertTrue(cell.testing_speakerPillInTagsRow)
        XCTAssertFalse(cell.testing_speakerPill.isHidden)
        XCTAssertFalse(cell.testing_tagsRow.isHidden)
        XCTAssertTrue(cell.testing_tagsLabel.isHidden)
        XCTAssertEqual(cell.testing_speakerPill.text, "João")

        let titleX = cell.testing_titleLabel.convert(cell.testing_titleLabel.bounds, to: cell.contentView).minX
        let subtitleX = cell.testing_subtitleLabel.convert(cell.testing_subtitleLabel.bounds, to: cell.contentView).minX
        XCTAssertEqual(titleX, subtitleX, accuracy: 0.5)

        let pillMinY = cell.testing_speakerPill.convert(cell.testing_speakerPill.bounds, to: cell.contentView).minY
        let subtitleMaxY = cell.testing_subtitleLabel.convert(cell.testing_subtitleLabel.bounds, to: cell.contentView).maxY
        XCTAssertGreaterThan(pillMinY, subtitleMaxY - 0.5, "pill alone still shows below the preview")
    }

    func testNoteRow_reuseFromSpeakerToNone_clearsGap() {
        let cell = KCNoteRowCell(style: .default, reuseIdentifier: KCNoteRowCell.reuseId)
        cell.frame = CGRect(x: 0, y: 0, width: 390, height: 88)
        cell.configure(title: "A", subtitle: "com speaker", tags: [], speakerName: "João", date: "Ontem")
        cell.layoutIfNeeded()
        XCTAssertTrue(cell.testing_speakerPillInTagsRow)

        cell.prepareForReuse()
        cell.configure(title: "B", subtitle: "sem speaker", tags: [], speakerName: nil, date: "Hoje")
        cell.layoutIfNeeded()

        XCTAssertFalse(cell.testing_speakerPillInTagsRow)
        XCTAssertTrue(cell.testing_tagsRow.isHidden)
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

    func testListBodyPreview_excludesBibleRefsAndSpeakerHeaders() {
        var note = NativeAPIClient.emptyNote(id: "list-preview")
        note.title = "Encontro em Loughborough"
        note.body.blocks = [
            NativeAPIClient.LineBlock(
                id: "sec1",
                type: "speakerSection",
                spans: nil,
                speakerId: "sp1",
                title: "Isaac Watts",
                collapsed: false,
                checked: nil,
                blocks: [
                    NativeAPIClient.LineBlock(
                        id: "c1",
                        type: "paragraph",
                        spans: [
                            .init(
                                type: "bibleRef",
                                text: "Lucas 14:26–27",
                                marks: nil,
                                bookId: "LUK",
                                chapter: 14,
                                verseStart: 26,
                                verseEnd: 27,
                                href: nil
                            ),
                            .init(type: "text", text: "  Semantic shift  ", marks: nil, bookId: nil, chapter: nil, verseStart: nil, verseEnd: nil, href: nil),
                            .init(
                                type: "bibleRef",
                                text: "Mateus 10:32",
                                marks: nil,
                                bookId: "MAT",
                                chapter: 10,
                                verseStart: 32,
                                verseEnd: nil,
                                href: nil
                            ),
                            .init(type: "text", text: " Hinos de Isaac Watts", marks: nil, bookId: nil, chapter: nil, verseStart: nil, verseEnd: nil, href: nil),
                        ],
                        speakerId: nil,
                        title: nil,
                        collapsed: nil,
                        checked: nil,
                        blocks: nil
                    ),
                ]
            ),
        ]

        let list = note.listBodyPreview
        XCTAssertEqual(list, "Semantic shift Hinos de Isaac Watts")
        XCTAssertFalse(list.contains("Lucas"), list)
        XCTAssertFalse(list.contains("Mateus"), list)
        XCTAssertFalse(list.hasPrefix("Isaac Watts"), "speaker section header title must not be the preview")
        // Share/search preview still keeps readable bible labels.
        XCTAssertTrue(note.preview.contains("Lucas 14:26–27"), note.preview)
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
