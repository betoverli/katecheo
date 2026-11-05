import UIKit

/// Pure attributed-string / document helpers for speaker sections (editor + AppTests).
///
/// Web parity (`docs/editor-behavior-spec.md`): the header is non-editable chrome;
/// body lines carry `speakerBodyKey`; Enter on empty last body exits after the section.
enum SpeakerSectionEditing {
    struct Result {
        var caret: Int
        var typingAttributes: [NSAttributedString.Key: Any]
    }

    /// Attributes for a body paragraph that still belongs to the speaker section.
    static func bodyTypingAttributes(blockId: String = NoteDocumentCodec.newId()) -> [NSAttributedString.Key: Any] {
        var attrs = NoteDocumentCodec.baseAttributes(
            type: "paragraph",
            id: blockId,
            checked: nil,
            speakerId: nil,
            speakers: [:]
        )
        attrs = NoteDocumentCodec.applyingSpeakerSectionInset(attrs)
        return attrs
    }

    /// Attributes for a normal paragraph *after* exiting a speaker section.
    static func outsideTypingAttributes(blockId: String = NoteDocumentCodec.newId()) -> [NSAttributedString.Key: Any] {
        var attrs = NoteDocumentCodec.baseAttributes(
            type: "paragraph",
            id: blockId,
            checked: nil,
            speakerId: nil,
            speakers: [:]
        )
        attrs.removeValue(forKey: NoteDocumentCodec.speakerBodyKey)
        return attrs
    }

    /// Empty body paragraph run (ZWSP) belonging to the section — web seeds one child.
    static func emptyBodyParagraph() -> NSAttributedString {
        let attrs = bodyTypingAttributes()
        return NSAttributedString(string: "\u{200B}", attributes: attrs)
    }

    /// Enter inside a body line → exactly one new body paragraph in the same section.
    @discardableResult
    static func insertContinuingBodyParagraph(
        in storage: NSMutableAttributedString,
        at caretLocation: Int
    ) -> Result {
        let attrs = bodyTypingAttributes()
        let para = paragraphRange(in: storage, at: caretLocation)
        let afterRange = NSRange(location: caretLocation, length: NSMaxRange(para) - caretLocation)
        let afterText = afterRange.length > 0
            ? (storage.string as NSString).substring(with: afterRange)
            : ""
        // Caret at end of the line (only the paragraph terminator left): insert a new
        // body paragraph *without* consuming that `\n`. Replacing it glued the new ZWSP
        // onto the following block and produced 0 net paragraphs (build-189 Enter bug).
        let onlyTerminator = afterText == "\n" || afterText == "\r\n" || afterRange.length == 0

        let piece = NSMutableAttributedString(string: "\n", attributes: attrs)
        if onlyTerminator {
            piece.append(NSAttributedString(string: "\u{200B}", attributes: attrs))
            storage.replaceCharacters(in: NSRange(location: caretLocation, length: 0), with: piece)
            let caret = caretLocation + 2 // after `\n`, on ZWSP
            return Result(caret: min(caret, storage.length), typingAttributes: attrs)
        }

        // Mid-paragraph split: move the remainder onto the new body line.
        let moved = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: afterRange))
        storage.replaceCharacters(in: afterRange, with: "")
        if (moved.string as NSString).hasPrefix("\n") {
            moved.replaceCharacters(in: NSRange(location: 0, length: 1), with: "")
        }
        if moved.length == 0 {
            piece.append(NSAttributedString(string: "\u{200B}", attributes: attrs))
        } else {
            moved.addAttribute(
                NoteDocumentCodec.speakerBodyKey,
                value: true,
                range: NSRange(location: 0, length: moved.length)
            )
            // Drop a trailing paragraph terminator from the moved run — the `\n` we
            // prepend already starts the new paragraph.
            if (moved.string as NSString).hasSuffix("\n") {
                moved.replaceCharacters(
                    in: NSRange(location: moved.length - 1, length: 1),
                    with: ""
                )
            }
            piece.append(moved)
        }
        storage.replaceCharacters(in: NSRange(location: caretLocation, length: 0), with: piece)
        // Land at the start of the new paragraph (after `\n`, on ZWSP or moved text).
        let caret = caretLocation + 1 + (moved.length == 0 ? 1 : 0)
        return Result(caret: min(caret, storage.length), typingAttributes: attrs)
    }

    /// Double-Enter on an empty last body line → remove it (if not sole child) and place a normal paragraph after.
    @discardableResult
    static func exitSection(
        in storage: NSMutableAttributedString,
        emptyBodyRange: NSRange,
        removeEmptyBody: Bool
    ) -> Result {
        var deleteLocation = emptyBodyRange.location
        var deleteLength = emptyBodyRange.length
        let ns = storage.string as NSString
        if removeEmptyBody, emptyBodyRange.location > 0 {
            let prev = ns.substring(with: NSRange(location: emptyBodyRange.location - 1, length: 1))
            if prev == "\n" {
                deleteLocation = emptyBodyRange.location - 1
                deleteLength = emptyBodyRange.length + 1
            }
            storage.replaceCharacters(in: NSRange(location: deleteLocation, length: deleteLength), with: "")
        }

        let attrs = outsideTypingAttributes()
        let insertAt = min(deleteLocation, storage.length)
        // Ensure we start a new paragraph after the section.
        let needsLeadingNewline = insertAt > 0 && (insertAt >= storage.length
            || (storage.string as NSString).substring(with: NSRange(location: insertAt - 1, length: 1)) != "\n")
        let piece = NSMutableAttributedString()
        if needsLeadingNewline || insertAt == storage.length {
            piece.append(NSAttributedString(string: "\n", attributes: attrs))
        }
        piece.append(NSAttributedString(string: "\u{200B}", attributes: attrs))
        storage.replaceCharacters(in: NSRange(location: insertAt, length: 0), with: piece)
        let caret = insertAt + piece.length
        return Result(caret: caret, typingAttributes: attrs)
    }

    static func paragraphRange(in storage: NSAttributedString, at location: Int) -> NSRange {
        let ns = storage.string as NSString
        let loc = min(max(0, location), ns.length)
        return ns.paragraphRange(for: NSRange(location: loc, length: 0))
    }

    static func blockType(in storage: NSAttributedString, at location: Int) -> String {
        guard storage.length > 0 else { return "paragraph" }
        let loc = min(max(0, location), storage.length - 1)
        return (storage.attributes(at: loc, effectiveRange: nil)[NoteDocumentCodec.blockTypeKey] as? String) ?? "paragraph"
    }

    static func isSpeakerBody(in storage: NSAttributedString, at location: Int) -> Bool {
        guard storage.length > 0 else { return false }
        let loc = min(max(0, location), storage.length - 1)
        return NoteDocumentCodec.isSpeakerBody(storage.attributes(at: loc, effectiveRange: nil))
    }

    static func findSpeakerHeaderRange(in storage: NSAttributedString) -> NSRange? {
        let ns = storage.string as NSString
        var cursor = 0
        while cursor < ns.length {
            let para = ns.paragraphRange(for: NSRange(location: cursor, length: 0))
            if para.length > 0 {
                let attrs = storage.attributes(at: para.location, effectiveRange: nil)
                if (attrs[NoteDocumentCodec.blockTypeKey] as? String) == "speakerSection" {
                    return para
                }
            }
            let next = NSMaxRange(para)
            if next <= cursor { break }
            cursor = next
        }
        return nil
    }

    /// Web `insertAfterAnchor` / bare-note rules applied to NoteDocumentV1.
    static func insertSpeakerBlock(
        into document: NativeAPIClient.NoteDocument,
        speakerId: String,
        speakerName: String,
        afterBlockId: String?
    ) -> (document: NativeAPIClient.NoteDocument, focusBodyId: String, sectionId: String) {
        let sectionId = NoteDocumentCodec.newId()
        let childId = NoteDocumentCodec.newId()
        let section = NativeAPIClient.LineBlock(
            id: sectionId,
            type: "speakerSection",
            spans: nil,
            speakerId: speakerId,
            title: speakerName,
            collapsed: nil,
            checked: nil,
            blocks: [
                NativeAPIClient.LineBlock(
                    id: childId,
                    type: "paragraph",
                    spans: [],
                    speakerId: nil,
                    title: nil,
                    collapsed: nil,
                    checked: nil,
                    blocks: nil
                ),
            ]
        )
        let trailing = NativeAPIClient.LineBlock(
            id: NoteDocumentCodec.newId(),
            type: "paragraph",
            spans: [],
            speakerId: nil,
            title: nil,
            collapsed: nil,
            checked: nil,
            blocks: nil
        )

        var blocks = document.body.blocks
        let bare = blocks.allSatisfy { block in
            if block.type == "speakerSection" { return false }
            let text = (block.spans ?? []).compactMap(\.text).joined()
                .replacingOccurrences(of: "\u{200B}", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty
        }

        if bare {
            blocks = [section, trailing]
        } else if let afterBlockId,
                  let idx = indexOfTopLevel(blockId: afterBlockId, in: blocks)
        {
            blocks.insert(section, at: idx + 1)
            if idx + 1 == blocks.count - 1 {
                blocks.append(trailing)
            }
        } else if let afterBlockId,
                  let parentIdx = indexOfSpeakerContaining(lineId: afterBlockId, in: blocks)
        {
            // Focus inside a speaker → insert new section after that whole speaker.
            blocks.insert(section, at: parentIdx + 1)
            if parentIdx + 1 == blocks.count - 1 {
                blocks.append(trailing)
            }
        } else {
            blocks.append(section)
            blocks.append(trailing)
        }

        var next = document
        next.body.blocks = blocks
        return (next, childId, sectionId)
    }

    private static func indexOfTopLevel(blockId: String, in blocks: [NativeAPIClient.LineBlock]) -> Int? {
        blocks.firstIndex(where: { $0.id == blockId })
    }

    private static func indexOfSpeakerContaining(lineId: String, in blocks: [NativeAPIClient.LineBlock]) -> Int? {
        blocks.firstIndex { block in
            block.type == "speakerSection" && (block.blocks ?? []).contains(where: { $0.id == lineId })
        }
    }
}
