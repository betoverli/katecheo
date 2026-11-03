import UIKit

/// Round-trip `NoteDocumentV1` ↔ `NSAttributedString` for the native editor.
///
/// Custom attributes (not serialized to RTF):
/// - `NoteBlockTypeKey` — paragraph | heading | bullet | numbered | check | quote | speakerSection
/// - `NoteBlockIdKey` — stable block id
/// - `NoteCheckedKey` — checklist checked
/// - `NoteBibleRefKey` — BibleRefPayload
/// - `NoteLinkKey` — URL string
enum NoteDocumentCodec {
    static let blockTypeKey = NSAttributedString.Key("v2n.blockType")
    static let blockIdKey = NSAttributedString.Key("v2n.blockId")
    static let checkedKey = NSAttributedString.Key("v2n.checked")
    static let bibleRefKey = NSAttributedString.Key("v2n.bibleRef")
    static let linkKey = NSAttributedString.Key("v2n.link")
    static let speakerIdKey = NSAttributedString.Key("v2n.speakerId")
    /// Marks a leading "• " / "1. " glyph that is display-only (not part of NoteDocumentV1 text).
    static let listMarkerKey = NSAttributedString.Key("v2n.listMarker")

    /// NSObject so it can live in NSAttributedString attribute values.
    final class BibleRefPayload: NSObject {
        let bookId: String
        let chapter: Int
        let verseStart: Int?
        let verseEnd: Int?
        let text: String?

        init(bookId: String, chapter: Int, verseStart: Int?, verseEnd: Int?, text: String?) {
            self.bookId = bookId
            self.chapter = chapter
            self.verseStart = verseStart
            self.verseEnd = verseEnd
            self.text = text
            super.init()
        }
    }

    // MARK: - Document → Attributed

    /// Apple Notes style: first paragraph is the title (large), then body blocks.
    static func attributedString(from document: NativeAPIClient.NoteDocument, speakers: [NativeAPIClient.SpeakerDTO] = []) -> NSAttributedString {
        precondition(Thread.isMainThread)
        let speakerMap = Dictionary(uniqueKeysWithValues: speakers.map { ($0.id, $0) })
        let result = NSMutableAttributedString()
        appendLine(
            to: result,
            type: "heading",
            id: "title",
            spans: [.init(type: "text", text: document.title, marks: nil, bookId: nil, chapter: nil, verseStart: nil, verseEnd: nil, href: nil)],
            checked: nil,
            speakerId: nil,
            speakers: speakerMap
        )
        var numberedIndex = 0
        for block in document.body.blocks {
            appendBlock(block, to: result, speakers: speakerMap, numberedIndex: &numberedIndex)
        }
        if result.length == 0 {
            appendLine(to: result, type: "paragraph", id: newId(), spans: [], checked: nil, speakerId: nil, speakers: speakerMap)
        }
        return result
    }

    private static func appendBlock(
        _ block: NativeAPIClient.LineBlock,
        to result: NSMutableAttributedString,
        speakers: [String: NativeAPIClient.SpeakerDTO],
        numberedIndex: inout Int
    ) {
        if block.type == "speakerSection" {
            numberedIndex = 0
            let speakerName: String = {
                if let sid = block.speakerId, let speaker = speakers[sid] { return speaker.name }
                if let title = block.title, !title.isEmpty { return title }
                return String(localized: "Speaker")
            }()
            let colorHex = block.speakerId.flatMap { speakers[$0]?.color }
            if result.length > 0 {
                result.append(NSAttributedString(string: "\n"))
            }
            result.append(
                speakerSectionHeader(
                    name: speakerName,
                    speakerId: block.speakerId,
                    colorHex: colorHex,
                    blockId: block.id
                )
            )
            var childNumbered = 0
            for child in block.blocks ?? [] {
                appendBlock(child, to: result, speakers: speakers, numberedIndex: &childNumbered)
            }
            return
        }
        if block.type == "numbered" {
            numberedIndex += 1
        } else {
            numberedIndex = 0
        }
        appendLine(
            to: result,
            type: block.type,
            id: block.id,
            spans: block.spans ?? [],
            checked: block.checked,
            speakerId: nil,
            speakers: speakers,
            listNumber: max(numberedIndex, 1)
        )
    }

    private static func appendLine(
        to result: NSMutableAttributedString,
        type: String,
        id: String,
        spans: [NativeAPIClient.TextSpan],
        checked: Bool?,
        speakerId: String?,
        speakers: [String: NativeAPIClient.SpeakerDTO],
        listNumber: Int = 1
    ) {
        if result.length > 0 {
            result.append(NSAttributedString(string: "\n"))
        }
        let base = baseAttributes(type: type, id: id, checked: checked, speakerId: speakerId, speakers: speakers)
        if let marker = listMarkerString(type: type, checked: checked, number: listNumber) {
            var markerAttrs = base
            markerAttrs[listMarkerKey] = true
            markerAttrs[.foregroundColor] = UIColor.secondaryLabel
            result.append(NSAttributedString(string: marker, attributes: markerAttrs))
        }
        if spans.isEmpty {
            result.append(NSAttributedString(string: "", attributes: base))
            return
        }
        for span in spans {
            result.append(spanAttributed(span, base: base))
        }
    }

    static func listMarkerString(type: String, checked: Bool?, number: Int = 1) -> String? {
        switch type {
        case "bullet":
            return "•\u{00A0}"
        case "numbered":
            return "\(number).\u{00A0}"
        case "check":
            return (checked == true ? "☑\u{00A0}" : "☐\u{00A0}")
        default:
            return nil
        }
    }

    private static func spanAttributed(_ span: NativeAPIClient.TextSpan, base: [NSAttributedString.Key: Any]) -> NSAttributedString {
        var attrs = base
        if span.type == "bibleRef" {
            let payload = BibleRefPayload(
                bookId: span.bookId ?? "?",
                chapter: span.chapter ?? 1,
                verseStart: span.verseStart,
                verseEnd: span.verseEnd,
                text: span.text
            )
            return bibleRefPill(payload: payload, base: attrs)
        }
        if span.type == "link" {
            let text = span.text?.isEmpty == false ? (span.text ?? "") : (span.href ?? "")
            attrs[.foregroundColor] = V2NDesign.bookmark
            attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
            if let href = span.href { attrs[linkKey] = href }
            return NSAttributedString(string: text, attributes: attrs)
        }
        let text = span.text ?? ""
        let marks = Set(span.marks ?? [])
        if let font = attrs[.font] as? UIFont {
            var traits = font.fontDescriptor.symbolicTraits
            if marks.contains("bold") { traits.insert(.traitBold) }
            if marks.contains("italic") { traits.insert(.traitItalic) }
            if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) {
                attrs[.font] = UIFont(descriptor: descriptor, size: font.pointSize)
            }
        }
        if marks.contains("underline") {
            attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        if marks.contains("strikethrough") {
            attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        return NSAttributedString(string: text, attributes: attrs)
    }

    private static func baseAttributes(
        type: String,
        id: String,
        checked: Bool?,
        speakerId: String?,
        speakers: [String: NativeAPIClient.SpeakerDTO]
    ) -> [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 3
        var font = UIFont.preferredFont(forTextStyle: .body)
        var foreground: UIColor = .label
        switch type {
        case "heading":
            font = UIFont.preferredFont(forTextStyle: id == "title" ? .title1 : .title2)
            style.paragraphSpacingBefore = id == "title" ? 0 : 8
        case "speakerSection":
            font = V2NDesign.preferred(.title3, weight: .semibold)
            style.paragraphSpacingBefore = 10
            style.paragraphSpacing = 6
            if let speakerId, let speaker = speakers[speakerId], let color = UIColor(v2nHex: speaker.color) {
                foreground = color
            } else {
                foreground = UIColor(red: 0.77, green: 0.65, blue: 0.45, alpha: 1) // #c4a574
            }
        case "bullet", "numbered", "check":
            style.headIndent = 22
            style.firstLineHeadIndent = 0
        case "quote":
            style.headIndent = 16
            style.firstLineHeadIndent = 16
            font = UIFont.preferredFont(forTextStyle: .body).italic()
        default:
            break
        }
        var attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: foreground,
            .paragraphStyle: style,
            blockTypeKey: type,
            blockIdKey: id,
        ]
        if type == "check" {
            attrs[checkedKey] = checked ?? false
        }
        if let speakerId {
            attrs[speakerIdKey] = speakerId
        }
        return attrs
    }

    /// Speaker section header rendered as a card attachment (avatar + name + accent bar).
    static func speakerSectionHeader(
        name: String,
        speakerId: String?,
        colorHex: String?,
        blockId: String
    ) -> NSAttributedString {
        let color = colorHex.flatMap { UIColor(v2nHex: $0) }
            ?? UIColor(red: 0.77, green: 0.65, blue: 0.45, alpha: 1)
        let attachment = SpeakerSectionAttachment(name: name, color: color, speakerId: speakerId)
        let result = NSMutableAttributedString(attachment: attachment)
        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = 10
        style.paragraphSpacing = 6
        var attrs: [NSAttributedString.Key: Any] = [
            .font: V2NDesign.preferred(.title3, weight: .semibold),
            .foregroundColor: color,
            .paragraphStyle: style,
            blockTypeKey: "speakerSection",
            blockIdKey: blockId,
        ]
        if let speakerId {
            attrs[speakerIdKey] = speakerId
        }
        result.addAttributes(attrs, range: NSRange(location: 0, length: result.length))
        return result
    }

    static func bibleRefPill(payload: BibleRefPayload, base: [NSAttributedString.Key: Any] = [:]) -> NSAttributedString {
        let label = displayText(for: payload)
        let kind = refKind(bookId: payload.bookId)
        let attachment = BibleRefPillAttachment(payload: payload, label: label, kind: kind)
        let result = NSMutableAttributedString(attachment: attachment)
        var attrs = base
        attrs[bibleRefKey] = payload
        attrs[.foregroundColor] = UIColor.clear
        // Keep block metadata on the attachment character for round-trip.
        result.addAttributes(attrs, range: NSRange(location: 0, length: result.length))
        // Soft spaces around the pill so typing stays readable.
        let pad = NSAttributedString(string: "\u{200B}", attributes: base)
        let out = NSMutableAttributedString()
        out.append(pad)
        out.append(result)
        out.append(pad)
        return out
    }

    static func refKind(bookId: String) -> BibleRefKind {
        switch bookId.uppercased() {
        case "MAT", "MRK", "LUK", "JHN":
            return .gospel
        default:
            // NT books after Malachi id set — Gospels already handled; use testament heuristic via known NT ids.
            let nt: Set<String> = [
                "MAT", "MRK", "LUK", "JHN", "ACT", "ROM", "1CO", "2CO", "GAL", "EPH", "PHP", "COL",
                "1TH", "2TH", "1TI", "2TI", "TIT", "PHM", "HEB", "JAS", "1PE", "2PE", "1JN", "2JN", "3JN", "JUD", "REV",
            ]
            return nt.contains(bookId.uppercased()) ? .nt : .ot
        }
    }

    enum BibleRefKind {
        case gospel, nt, ot
    }

    static func displayText(for ref: BibleRefPayload) -> String {
        if let text = ref.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            return text
        }
        if let start = ref.verseStart {
            if let end = ref.verseEnd, end != start {
                return "\(ref.bookId) \(ref.chapter):\(start)–\(end)"
            }
            return "\(ref.bookId) \(ref.chapter):\(start)"
        }
        return "\(ref.bookId) \(ref.chapter)"
    }

    // MARK: - Attributed → Document

    static func document(
        from attributed: NSAttributedString,
        base: NativeAPIClient.NoteDocument
    ) -> NativeAPIClient.NoteDocument {
        precondition(Thread.isMainThread)
        let lines = splitParagraphs(attributed)
        var title = base.title
        var bodyBlocks: [NativeAPIClient.LineBlock] = []
        var index = 0
        if let first = lines.first {
            title = String(first.string).trimmingCharacters(in: .whitespacesAndNewlines)
            index = 1
        }
        var currentSpeaker: NativeAPIClient.LineBlock?
        func flushSpeaker() {
            if let speaker = currentSpeaker {
                bodyBlocks.append(speaker)
                currentSpeaker = nil
            }
        }
        while index < lines.count {
            let line = lines[index]
            index += 1
            let type = (line.attributes[blockTypeKey] as? String) ?? "paragraph"
            let id = (line.attributes[blockIdKey] as? String) ?? newId()
            if type == "speakerSection" {
                flushSpeaker()
                let speakerName: String = {
                    if let attachment = line.attributes[.attachment] as? SpeakerSectionAttachment {
                        return attachment.name
                    }
                    let raw = String(line.string).trimmingCharacters(in: .whitespacesAndNewlines)
                    return raw.isEmpty ? String(localized: "Speaker") : raw
                }()
                currentSpeaker = NativeAPIClient.LineBlock(
                    id: id,
                    type: "speakerSection",
                    spans: nil,
                    speakerId: line.attributes[speakerIdKey] as? String
                        ?? (line.attributes[.attachment] as? SpeakerSectionAttachment)?.speakerId,
                    title: speakerName,
                    collapsed: false,
                    checked: nil,
                    blocks: []
                )
                continue
            }
            let block = lineBlock(from: line, type: type, id: id)
            if var speaker = currentSpeaker {
                var children = speaker.blocks ?? []
                children.append(block)
                speaker.blocks = children
                currentSpeaker = speaker
            } else {
                bodyBlocks.append(block)
            }
        }
        flushSpeaker()
        if bodyBlocks.isEmpty {
            bodyBlocks = [NativeAPIClient.LineBlock(id: newId(), type: "paragraph", spans: [], speakerId: nil, title: nil, collapsed: nil, checked: nil, blocks: nil)]
        }
        var next = base
        next.title = String(title.prefix(80))
        next.schemaVersion = 1
        next.body = .init(blocks: bodyBlocks)
        next.updatedAt = ISO8601DateFormatter().string(from: Date())
        return next
    }

    private static func lineBlock(from line: ParagraphSlice, type: String, id: String) -> NativeAPIClient.LineBlock {
        let spans = spans(from: line.attributed)
        let checked = type == "check" ? (line.attributes[checkedKey] as? Bool) : nil
        return NativeAPIClient.LineBlock(
            id: id,
            type: normalizedType(type),
            spans: spans,
            speakerId: nil,
            title: nil,
            collapsed: nil,
            checked: checked,
            blocks: nil
        )
    }

    private static func normalizedType(_ type: String) -> String {
        switch type {
        case "heading", "bullet", "numbered", "check", "quote", "speakerSection":
            return type
        default:
            return "paragraph"
        }
    }

    private static func spans(from attributed: NSAttributedString) -> [NativeAPIClient.TextSpan] {
        var out: [NativeAPIClient.TextSpan] = []
        let full = NSRange(location: 0, length: attributed.length)
        attributed.enumerateAttributes(in: full, options: []) { attrs, range, _ in
            let text = (attributed.string as NSString).substring(with: range)
            if text.isEmpty { return }
            if attrs[.attachment] is SpeakerSectionAttachment {
                // Speaker header is a block, not an inline span.
                return
            }
            if let attachment = attrs[.attachment] as? BibleRefPillAttachment {
                let payload = attachment.payload
                out.append(NativeAPIClient.TextSpan(
                    type: "bibleRef",
                    text: payload.text ?? displayText(for: payload),
                    marks: nil,
                    bookId: payload.bookId,
                    chapter: payload.chapter,
                    verseStart: payload.verseStart,
                    verseEnd: payload.verseEnd,
                    href: nil
                ))
                return
            }
            if let payload = attrs[bibleRefKey] as? BibleRefPayload {
                out.append(NativeAPIClient.TextSpan(
                    type: "bibleRef",
                    text: payload.text ?? displayText(for: payload),
                    marks: nil,
                    bookId: payload.bookId,
                    chapter: payload.chapter,
                    verseStart: payload.verseStart,
                    verseEnd: payload.verseEnd,
                    href: nil
                ))
                return
            }
            // Zero-width pads around pills / empty placeholders
            if text == "\u{200B}" { return }
            // Display-only list markers must not enter NoteDocumentV1 spans.
            if attrs[listMarkerKey] as? Bool == true { return }
            if let href = attrs[linkKey] as? String {
                out.append(NativeAPIClient.TextSpan(
                    type: "link",
                    text: text,
                    marks: nil,
                    bookId: nil,
                    chapter: nil,
                    verseStart: nil,
                    verseEnd: nil,
                    href: href
                ))
                return
            }
            var marks: [String] = []
            if let font = attrs[.font] as? UIFont {
                let traits = font.fontDescriptor.symbolicTraits
                if traits.contains(.traitBold) { marks.append("bold") }
                if traits.contains(.traitItalic) { marks.append("italic") }
            }
            if let underline = attrs[.underlineStyle] as? Int, underline != 0, attrs[bibleRefKey] == nil {
                marks.append("underline")
            }
            if let strike = attrs[.strikethroughStyle] as? Int, strike != 0 {
                marks.append("strikethrough")
            }
            out.append(NativeAPIClient.TextSpan(
                type: "text",
                text: text,
                marks: marks.isEmpty ? nil : marks,
                bookId: nil,
                chapter: nil,
                verseStart: nil,
                verseEnd: nil,
                href: nil
            ))
        }
        return mergeAdjacentText(out)
    }

    private static func mergeAdjacentText(_ spans: [NativeAPIClient.TextSpan]) -> [NativeAPIClient.TextSpan] {
        var out: [NativeAPIClient.TextSpan] = []
        for span in spans {
            if span.type == "text",
               let last = out.last,
               last.type == "text",
               last.marks == span.marks
            {
                var merged = last
                merged.text = (last.text ?? "") + (span.text ?? "")
                out[out.count - 1] = merged
            } else {
                out.append(span)
            }
        }
        return out
    }

    private struct ParagraphSlice {
        var string: String
        var attributed: NSAttributedString
        var attributes: [NSAttributedString.Key: Any]
    }

    private static func splitParagraphs(_ attributed: NSAttributedString) -> [ParagraphSlice] {
        let ns = attributed.string as NSString
        var lines: [ParagraphSlice] = []
        var start = 0
        while start <= ns.length {
            let remaining = NSRange(location: start, length: ns.length - start)
            let found = ns.rangeOfCharacter(from: .newlines, options: [], range: remaining)
            let end = found.location == NSNotFound ? ns.length : found.location
            let range = NSRange(location: start, length: end - start)
            let piece = attributed.attributedSubstring(from: range)
            var attrs: [NSAttributedString.Key: Any] = [:]
            if piece.length > 0 {
                attrs = piece.attributes(at: 0, effectiveRange: nil)
            } else if attributed.length > start {
                attrs = attributed.attributes(at: min(start, attributed.length - 1), effectiveRange: nil)
            }
            lines.append(ParagraphSlice(string: piece.string, attributed: piece, attributes: attrs))
            if found.location == NSNotFound { break }
            start = found.location + found.length
            if start >= ns.length, found.location + found.length == ns.length {
                // Trailing newline → extra empty paragraph (Apple Notes behavior).
                let emptyAttrs = attrs
                lines.append(ParagraphSlice(string: "", attributed: NSAttributedString(string: ""), attributes: emptyAttrs))
                break
            }
        }
        if lines.isEmpty {
            lines.append(ParagraphSlice(string: "", attributed: NSAttributedString(string: ""), attributes: [:]))
        }
        return lines
    }

    static func newId() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }
}

private extension UIFont {
    func italic() -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(fontDescriptor.symbolicTraits.union(.traitItalic)) else {
            return self
        }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}

// MARK: - Speaker section card attachment

/// Card-style speaker block header: left accent bar, color avatar, name.
final class SpeakerSectionAttachment: NSTextAttachment {
    let name: String
    let color: UIColor
    let speakerId: String?

    init(name: String, color: UIColor, speakerId: String?) {
        self.name = name
        self.color = color
        self.speakerId = speakerId
        super.init(data: nil, ofType: nil)
        refreshImage()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func refreshImage() {
        let nameFont = V2NDesign.preferred(.headline, weight: .semibold)
        let metaFont = V2NDesign.caption()
        let nameText = NSAttributedString(string: name, attributes: [
            .font: nameFont,
            .foregroundColor: UIColor.label,
        ])
        let meta = NSAttributedString(string: String(localized: "Speaker"), attributes: [
            .font: metaFont,
            .foregroundColor: UIColor.secondaryLabel,
        ])
        let nameSize = nameText.size()
        let metaSize = meta.size()
        let padX: CGFloat = 12
        let padY: CGFloat = 10
        let avatar: CGFloat = 32
        let gap: CGFloat = 10
        let accentW: CGFloat = 4
        let contentW = max(nameSize.width, metaSize.width)
        let width = min(max(accentW + padX + avatar + gap + contentW + padX, 160), UIScreen.main.bounds.width - 48)
        let height = max(avatar, nameSize.height + 2 + metaSize.height) + padY * 2
        let size = CGSize(width: ceil(width), height: ceil(height))
        let renderer = UIGraphicsImageRenderer(size: size)
        image = renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: size)
            let bg = UIBezierPath(roundedRect: rect, cornerRadius: V2NDesign.Radius.md)
            V2NDesign.surface.setFill()
            bg.fill()

            let accentRect = CGRect(x: 0, y: 0, width: accentW, height: size.height)
            color.setFill()
            UIBezierPath(roundedRect: accentRect, cornerRadius: 1).fill()
            V2NDesign.surface.setFill()
            UIBezierPath(rect: CGRect(x: accentW, y: 0, width: 2, height: size.height)).fill()

            let avatarRect = CGRect(
                x: accentW + padX,
                y: (size.height - avatar) / 2,
                width: avatar,
                height: avatar
            )
            ctx.cgContext.saveGState()
            UIBezierPath(ovalIn: avatarRect).addClip()
            color.setFill()
            UIBezierPath(ovalIn: avatarRect).fill()
            let initial = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased()
            let initialFont = V2NDesign.preferred(.subheadline, weight: .bold)
            let initialAttr = NSAttributedString(string: initial.isEmpty ? "S" : initial, attributes: [
                .font: initialFont,
                .foregroundColor: UIColor.white,
            ])
            let iSize = initialAttr.size()
            initialAttr.draw(at: CGPoint(
                x: avatarRect.midX - iSize.width / 2,
                y: avatarRect.midY - iSize.height / 2
            ))
            ctx.cgContext.restoreGState()

            let textX = avatarRect.maxX + gap
            let textBlockH = nameSize.height + 2 + metaSize.height
            let textY = (size.height - textBlockH) / 2
            nameText.draw(at: CGPoint(x: textX, y: textY))
            meta.draw(at: CGPoint(x: textX, y: textY + nameSize.height + 2))

            V2NDesign.separator.setStroke()
            bg.lineWidth = 0.5
            bg.stroke()
        }
        let font = V2NDesign.preferred(.headline, weight: .semibold)
        bounds = CGRect(x: 0, y: font.descender - 4, width: size.width, height: size.height)
    }
}

// MARK: - Bible ref pill attachment

final class BibleRefPillAttachment: NSTextAttachment {
    let payload: NoteDocumentCodec.BibleRefPayload
    let label: String
    let kind: NoteDocumentCodec.BibleRefKind

    init(payload: NoteDocumentCodec.BibleRefPayload, label: String, kind: NoteDocumentCodec.BibleRefKind) {
        self.payload = payload
        self.label = label
        self.kind = kind
        super.init(data: nil, ofType: nil)
        refreshImage()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func colors() -> (UIColor, UIColor) {
        let dark = UITraitCollection.current.userInterfaceStyle == .dark
        switch kind {
        case .gospel:
            return (V2NDesign.accent, .white)
        case .nt:
            return dark
                ? (UIColor(red: 0.24, green: 0.29, blue: 0.36, alpha: 1), UIColor(red: 0.91, green: 0.93, blue: 0.96, alpha: 1))
                : (UIColor(red: 0.84, green: 0.88, blue: 0.93, alpha: 1), UIColor(red: 0.11, green: 0.16, blue: 0.23, alpha: 1))
        case .ot:
            return dark
                ? (UIColor(red: 0.29, green: 0.24, blue: 0.20, alpha: 1), UIColor(red: 0.95, green: 0.93, blue: 0.90, alpha: 1))
                : (UIColor(red: 0.92, green: 0.85, blue: 0.78, alpha: 1), UIColor(red: 0.23, green: 0.16, blue: 0.11, alpha: 1))
        }
    }

    func refreshImage() {
        let font = V2NDesign.preferred(.footnote, weight: .semibold)
        let (bg, fg) = colors()
        let text = NSAttributedString(string: label, attributes: [
            .font: font,
            .foregroundColor: fg,
        ])
        let textSize = text.size()
        let padX: CGFloat = 8
        let padY: CGFloat = 3
        let size = CGSize(width: ceil(textSize.width + padX * 2), height: ceil(textSize.height + padY * 2))
        let renderer = UIGraphicsImageRenderer(size: size)
        image = renderer.image { _ in
            let rect = CGRect(origin: .zero, size: size)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: size.height / 2)
            bg.setFill()
            path.fill()
            let textRect = CGRect(
                x: padX,
                y: (size.height - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )
            text.draw(in: textRect)
        }
        bounds = CGRect(x: 0, y: font.descender - 2, width: size.width, height: size.height)
    }
}

extension UIColor {
    /// Parse `#RRGGBB` speaker colors from the notebook API.
    convenience init?(v2nHex: String) {
        var hex = v2nHex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        let r = CGFloat((value >> 16) & 0xff) / 255
        let g = CGFloat((value >> 8) & 0xff) / 255
        let b = CGFloat(value & 0xff) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}
