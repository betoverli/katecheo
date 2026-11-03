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

    struct BibleRefPayload: Equatable {
        var bookId: String
        var chapter: Int
        var verseStart: Int?
        var verseEnd: Int?
        var text: String?
    }

    // MARK: - Document → Attributed

    /// Apple Notes style: first paragraph is the title (large), then body blocks.
    static func attributedString(from document: NativeAPIClient.NoteDocument) -> NSAttributedString {
        precondition(Thread.isMainThread)
        let result = NSMutableAttributedString()
        appendLine(
            to: result,
            type: "heading",
            id: "title",
            spans: [.init(type: "text", text: document.title, marks: nil, bookId: nil, chapter: nil, verseStart: nil, verseEnd: nil, href: nil)],
            checked: nil,
            speakerId: nil
        )
        for block in document.body.blocks {
            appendBlock(block, to: result)
        }
        if result.length == 0 {
            appendLine(to: result, type: "paragraph", id: newId(), spans: [], checked: nil, speakerId: nil)
        }
        return result
    }

    private static func appendBlock(_ block: NativeAPIClient.LineBlock, to result: NSMutableAttributedString) {
        if block.type == "speakerSection" {
            let titleSpans: [NativeAPIClient.TextSpan] = [
                .init(type: "text", text: block.title?.isEmpty == false ? (block.title ?? "") : "Speaker", marks: ["bold"], bookId: nil, chapter: nil, verseStart: nil, verseEnd: nil, href: nil),
            ]
            appendLine(to: result, type: "speakerSection", id: block.id, spans: titleSpans, checked: nil, speakerId: block.speakerId)
            for child in block.blocks ?? [] {
                appendBlock(child, to: result)
            }
            return
        }
        appendLine(
            to: result,
            type: block.type,
            id: block.id,
            spans: block.spans ?? [],
            checked: block.checked,
            speakerId: nil
        )
    }

    private static func appendLine(
        to result: NSMutableAttributedString,
        type: String,
        id: String,
        spans: [NativeAPIClient.TextSpan],
        checked: Bool?,
        speakerId: String?
    ) {
        if result.length > 0 {
            result.append(NSAttributedString(string: "\n"))
        }
        let base = baseAttributes(type: type, id: id, checked: checked, speakerId: speakerId)
        if spans.isEmpty {
            result.append(NSAttributedString(string: "", attributes: base))
            return
        }
        for span in spans {
            result.append(spanAttributed(span, base: base))
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
            let label = displayText(for: payload)
            attrs[.foregroundColor] = UIColor.systemBlue
            attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
            attrs[bibleRefKey] = payload
            attrs[.accessibilityHint] = "Referência bíblica"
            return NSAttributedString(string: label, attributes: attrs)
        }
        if span.type == "link" {
            let text = span.text?.isEmpty == false ? (span.text ?? "") : (span.href ?? "")
            attrs[.foregroundColor] = UIColor.systemBlue
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

    private static func baseAttributes(type: String, id: String, checked: Bool?, speakerId: String?) -> [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 3
        var font = UIFont.preferredFont(forTextStyle: .body)
        switch type {
        case "heading", "speakerSection":
            font = UIFont.preferredFont(forTextStyle: type == "heading" && id == "title" ? .title1 : .title2)
            style.paragraphSpacingBefore = id == "title" ? 0 : 8
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
            .foregroundColor: UIColor.label,
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
                currentSpeaker = NativeAPIClient.LineBlock(
                    id: id,
                    type: "speakerSection",
                    spans: nil,
                    speakerId: line.attributes[speakerIdKey] as? String,
                    title: String(line.string),
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
