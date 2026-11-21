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
        XCTAssertTrue(cell.testing_speakerChip.isHidden)
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
        XCTAssertFalse(cell.testing_speakerChip.isHidden)
        XCTAssertFalse(cell.testing_tagsRow.isHidden)
        let pillName = cell.testing_speakerPill.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        XCTAssertEqual(pillName, "Pastor Ana")
        XCTAssertGreaterThan(cell.testing_speakerChip.bounds.width, 1)
        XCTAssertGreaterThan(cell.testing_speakerChip.bounds.height, 1)
        XCTAssertGreaterThan(cell.testing_speakerChip.alpha, 0.99)

        let titleX = cell.testing_titleLabel.convert(cell.testing_titleLabel.bounds, to: cell.contentView).minX
        let subtitleX = cell.testing_subtitleLabel.convert(cell.testing_subtitleLabel.bounds, to: cell.contentView).minX
        XCTAssertEqual(titleX, subtitleX, accuracy: 0.5, "preview stays full-width and aligned with title")

        let pillMinY = cell.testing_speakerChip.convert(cell.testing_speakerChip.bounds, to: cell.contentView).minY
        let subtitleMaxY = cell.testing_subtitleLabel.convert(cell.testing_subtitleLabel.bounds, to: cell.contentView).maxY
        XCTAssertGreaterThan(pillMinY, subtitleMaxY - 0.5, "speaker pill sits on the tags row below the preview")

        let tagsMinX = cell.testing_tagsLabel.convert(cell.testing_tagsLabel.bounds, to: cell.contentView).minX
        let pillMaxX = cell.testing_speakerChip.convert(cell.testing_speakerChip.bounds, to: cell.contentView).maxX
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
        XCTAssertFalse(cell.testing_speakerChip.isHidden)
        XCTAssertFalse(cell.testing_tagsRow.isHidden)
        XCTAssertTrue(cell.testing_tagsLabel.isHidden)
        XCTAssertEqual(cell.testing_speakerPill.text, "João")

        let titleX = cell.testing_titleLabel.convert(cell.testing_titleLabel.bounds, to: cell.contentView).minX
        let subtitleX = cell.testing_subtitleLabel.convert(cell.testing_subtitleLabel.bounds, to: cell.contentView).minX
        XCTAssertEqual(titleX, subtitleX, accuracy: 0.5)

        let pillMinY = cell.testing_speakerChip.convert(cell.testing_speakerChip.bounds, to: cell.contentView).minY
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

    func testNoteRow_speakerChipPaintsNameAndFill_inLightAndDark() {
        for style: UIUserInterfaceStyle in [.light, .dark] {
            let cell = KCNoteRowCell(style: .default, reuseIdentifier: KCNoteRowCell.reuseId)
            cell.overrideUserInterfaceStyle = style
            cell.frame = CGRect(x: 0, y: 0, width: 390, height: 120)
            cell.backgroundColor = KCDesign.surface
            cell.contentView.backgroundColor = KCDesign.surface
            cell.configure(
                title: "Culto de domingo",
                subtitle: "Passagem reflexão",
                tags: ["casais", "retiro", "marido"],
                speakerName: "Hélio Azevedo",
                date: "Hoje"
            )
            cell.setNeedsLayout()
            cell.layoutIfNeeded()

            XCTAssertEqual(cell.testing_speakerPill.text, "Hélio Azevedo", "style=\(style.rawValue)")
            XCTAssertTrue(cell.testing_speakerPillInTagsRow, "style=\(style.rawValue)")
            XCTAssertFalse(cell.testing_speakerChip.isHidden, "style=\(style.rawValue)")
            XCTAssertGreaterThanOrEqual(cell.testing_speakerChip.bounds.width, 16, "style=\(style.rawValue)")
            XCTAssertGreaterThanOrEqual(cell.testing_speakerChip.bounds.height, 16, "style=\(style.rawValue)")

            let titleX = cell.testing_titleLabel.convert(cell.testing_titleLabel.bounds, to: cell.contentView).minX
            let chipX = cell.testing_speakerChip.convert(cell.testing_speakerChip.bounds, to: cell.contentView).minX
            XCTAssertEqual(chipX, titleX, accuracy: 0.5, "chip aligns with title; style=\(style.rawValue)")

            let tagsMinX = cell.testing_tagsLabel.convert(cell.testing_tagsLabel.bounds, to: cell.contentView).minX
            let chipMaxX = cell.testing_speakerChip.convert(cell.testing_speakerChip.bounds, to: cell.contentView).maxX
            XCTAssertGreaterThan(tagsMinX, chipMaxX - 0.5, "tags follow chip; style=\(style.rawValue)")

            let traits = UITraitCollection(userInterfaceStyle: style)
            let textColor = cell.testing_speakerPill.textColor?.resolvedColor(with: traits) ?? .clear
            let fillCG = cell.testing_speakerChip.layer.backgroundColor
            XCTAssertNotNil(fillCG, "fill must be set; style=\(style.rawValue)")
            let fillColor = UIColor(cgColor: fillCG!).resolvedColor(with: traits)
            let surface = KCDesign.surface.resolvedColor(with: traits)

            XCTAssertGreaterThan(textColor.cgColor.alpha, 0.01, "text not clear; style=\(style.rawValue)")
            XCTAssertGreaterThan(fillColor.cgColor.alpha, 0.01, "fill not clear; style=\(style.rawValue)")
            XCTAssertFalse(colorsVisuallyEqual(textColor, surface), "text ≠ surface; style=\(style.rawValue)")
            XCTAssertFalse(colorsVisuallyEqual(fillColor, surface), "fill ≠ surface; style=\(style.rawValue)")

            let chipBoundsInCell = cell.testing_speakerChip.convert(cell.testing_speakerChip.bounds, to: cell)
            let renderer = UIGraphicsImageRenderer(bounds: cell.bounds)
            let image = renderer.image { _ in
                cell.drawHierarchy(in: cell.bounds, afterScreenUpdates: true)
            }
            guard let cgImage = image.cgImage else {
                XCTFail("failed to render cell; style=\(style.rawValue)")
                continue
            }
            let scale = image.scale
            let sampleRect = CGRect(
                x: max(0, chipBoundsInCell.minX * scale),
                y: max(0, chipBoundsInCell.minY * scale),
                width: max(1, chipBoundsInCell.width * scale),
                height: max(1, chipBoundsInCell.height * scale)
            ).integral
            guard let cropped = cgImage.cropping(to: sampleRect) else {
                XCTFail("failed to crop chip; style=\(style.rawValue)")
                continue
            }
            XCTAssertTrue(
                imageContainsNonSurfacePixels(cropped, surface: surface),
                "chip must paint non-surface pixels; style=\(style.rawValue)"
            )
        }
    }

    private func colorsVisuallyEqual(_ a: UIColor, _ b: UIColor, tolerance: CGFloat = 0.02) -> Bool {
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        guard a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa),
              b.getRed(&br, green: &bg, blue: &bb, alpha: &ba) else {
            return a == b
        }
        return abs(ar - br) <= tolerance
            && abs(ag - bg) <= tolerance
            && abs(ab - bb) <= tolerance
            && abs(aa - ba) <= tolerance
    }

    private func imageContainsNonSurfacePixels(_ image: CGImage, surface: UIColor) -> Bool {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return false }
        var surfaceR: CGFloat = 0, surfaceG: CGFloat = 0, surfaceB: CGFloat = 0, surfaceA: CGFloat = 0
        _ = surface.getRed(&surfaceR, green: &surfaceG, blue: &surfaceB, alpha: &surfaceA)
        let sR = Int((surfaceR * 255).rounded())
        let sG = Int((surfaceG * 255).rounded())
        let sB = Int((surfaceB * 255).rounded())

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var data = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let ctx = CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Sample a denser grid inside the pill; any non-surface pixel means fill/text painted.
        let stepX = max(1, width / 12)
        let stepY = max(1, height / 8)
        for y in stride(from: height / 4, to: (height * 3) / 4, by: stepY) {
            for x in stride(from: width / 6, to: (width * 5) / 6, by: stepX) {
                let idx = y * bytesPerRow + x * bytesPerPixel
                let r = Int(data[idx])
                let g = Int(data[idx + 1])
                let b = Int(data[idx + 2])
                let a = Int(data[idx + 3])
                if a < 8 { continue }
                if abs(r - sR) > 12 || abs(g - sG) > 12 || abs(b - sB) > 12 {
                    return true
                }
            }
        }
        return false
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
