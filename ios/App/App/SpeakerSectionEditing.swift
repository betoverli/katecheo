import UIKit

/// Pure attributed-string mutations for speaker sections (shared by the editor + AppTests).
///
/// UITextView paragraph breaks need a real attribute run *after* the `\n`. Inserting only
/// `"\n"` leaves the new paragraph without `speakerBodyKey`, so typed text falls outside
/// the section in both rendering and NoteDocumentV1 encoding.
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

    /// Enter on the speaker name line → first (or next) body paragraph inside the section.
    @discardableResult
    static func insertBodyAfterHeader(
        in storage: NSMutableAttributedString,
        headerRange: NSRange
    ) -> Result {
        let insertLoc = NSMaxRange(headerRange)
        let attrs = bodyTypingAttributes()
        let piece = NSMutableAttributedString(string: "\n", attributes: attrs)
        // ZWSP anchors speakerBodyKey + inset on the new paragraph run.
        piece.append(NSAttributedString(string: "\u{200B}", attributes: attrs))
        storage.replaceCharacters(in: NSRange(location: insertLoc, length: 0), with: piece)
        let caret = insertLoc + piece.length
        return Result(caret: caret, typingAttributes: attrs)
    }

    /// Enter inside a non-exiting body line → another body paragraph in the same section.
    @discardableResult
    static func insertContinuingBodyParagraph(
        in storage: NSMutableAttributedString,
        paragraphRange: NSRange
    ) -> Result {
        let insertLoc = NSMaxRange(paragraphRange)
        let attrs = bodyTypingAttributes()
        let piece = NSMutableAttributedString(string: "\n", attributes: attrs)
        piece.append(NSAttributedString(string: "\u{200B}", attributes: attrs))
        storage.replaceCharacters(in: NSRange(location: insertLoc, length: 0), with: piece)
        let caret = insertLoc + piece.length
        return Result(caret: caret, typingAttributes: attrs)
    }

    /// Double-Enter on an empty last body line → remove it and place a normal paragraph after.
    @discardableResult
    static func exitSection(
        in storage: NSMutableAttributedString,
        emptyBodyRange: NSRange
    ) -> Result {
        var deleteLocation = emptyBodyRange.location
        var deleteLength = emptyBodyRange.length
        let ns = storage.string as NSString
        if emptyBodyRange.location > 0 {
            let prev = ns.substring(with: NSRange(location: emptyBodyRange.location - 1, length: 1))
            if prev == "\n" {
                deleteLocation = emptyBodyRange.location - 1
                deleteLength = emptyBodyRange.length + 1
            }
        }
        storage.replaceCharacters(in: NSRange(location: deleteLocation, length: deleteLength), with: "")

        let attrs = outsideTypingAttributes()
        let piece = NSMutableAttributedString(string: "\n", attributes: attrs)
        piece.append(NSAttributedString(string: "\u{200B}", attributes: attrs))
        let insertAt = min(deleteLocation, storage.length)
        storage.replaceCharacters(in: NSRange(location: insertAt, length: 0), with: piece)
        let caret = insertAt + piece.length
        return Result(caret: caret, typingAttributes: attrs)
    }

    /// Replace the ZWSP placeholder at `caret-1` (if present) with typed content helper for tests.
    @discardableResult
    static func typeText(
        _ text: String,
        in storage: NSMutableAttributedString,
        at caret: Int,
        attributes: [NSAttributedString.Key: Any]
    ) -> Int {
        var loc = caret
        if loc > 0, loc <= storage.length {
            let prev = (storage.string as NSString).substring(with: NSRange(location: loc - 1, length: 1))
            if prev == "\u{200B}" {
                storage.replaceCharacters(
                    in: NSRange(location: loc - 1, length: 1),
                    with: NSAttributedString(string: text, attributes: attributes)
                )
                return loc - 1 + text.count
            }
        }
        storage.replaceCharacters(
            in: NSRange(location: loc, length: 0),
            with: NSAttributedString(string: text, attributes: attributes)
        )
        return loc + text.count
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
                let type = storage.attributes(at: para.location, effectiveRange: nil)[NoteDocumentCodec.blockTypeKey] as? String
                if type == "speakerSection" { return para }
            }
            let next = NSMaxRange(para)
            if next <= cursor { break }
            cursor = next
        }
        return nil
    }
}
