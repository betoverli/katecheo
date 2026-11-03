import Foundation

/// Converts legacy web `Note` / zustand shapes (`blocks` + `inlines`) into `NoteDocumentV1`.
enum LegacyNoteConverter {
    static func noteDocument(fromLegacy raw: Any) -> NativeAPIClient.NoteDocument? {
        guard let row = raw as? [String: Any] else { return nil }
        // Already NoteDocumentV1?
        if row["schemaVersion"] as? Int == 1 || row["body"] != nil {
            return decodeDocument(row)
        }
        let id = (row["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !id.isEmpty else { return nil }
        let title = (row["title"] as? String) ?? ""
        let happenedAt = sanitizeDay(row["happenedAt"] as? String)
        let tags = ((row["tags"] as? [Any]) ?? []).compactMap { $0 as? String }
        let speakerId = row["speakerId"] as? String
        let visibility = (row["visibility"] as? String) == "unlisted" ? "unlisted" : "private"
        let updatedAt = (row["updatedAt"] as? String) ?? ISO8601DateFormatter().string(from: Date())
        let blocksRaw = (row["blocks"] as? [Any]) ?? []
        let blocks = blocksRaw.compactMap(convertBlock).prefix(200)
        let finalBlocks = blocks.isEmpty
            ? [NativeAPIClient.LineBlock(
                id: newId(),
                type: "paragraph",
                spans: [],
                speakerId: nil,
                title: nil,
                collapsed: nil,
                blocks: nil
            )]
            : Array(blocks)
        return NativeAPIClient.NoteDocument(
            schemaVersion: 1,
            id: String(id.prefix(40)),
            title: String(title.prefix(80)),
            happenedAt: happenedAt,
            tags: tags,
            noteSpeakerId: speakerId.flatMap { $0.isEmpty ? nil : String($0.prefix(40)) },
            visibility: visibility,
            updatedAt: updatedAt,
            body: NativeAPIClient.NoteBody(blocks: finalBlocks)
        )
    }

    static func speaker(fromLegacy raw: Any) -> NativeAPIClient.SpeakerDTO? {
        guard let row = raw as? [String: Any] else { return nil }
        let id = (row["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let name = (row["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !id.isEmpty, !name.isEmpty else { return nil }
        let color = (row["color"] as? String) ?? "#8aa0b8"
        let updatedAt = (row["updatedAt"] as? String) ?? ISO8601DateFormatter().string(from: Date())
        return NativeAPIClient.SpeakerDTO(
            id: String(id.prefix(40)),
            name: String(name.prefix(80)),
            color: String(color.prefix(16)),
            updatedAt: updatedAt
        )
    }

    /// Prefer the newer `updatedAt` (ISO-8601 lexicographic works for our wire format).
    static func preferNewer(
        _ a: NativeAPIClient.NoteDocument,
        _ b: NativeAPIClient.NoteDocument
    ) -> NativeAPIClient.NoteDocument {
        a.updatedAt >= b.updatedAt ? a : b
    }

    // MARK: - Private

    private static func decodeDocument(_ row: [String: Any]) -> NativeAPIClient.NoteDocument? {
        guard JSONSerialization.isValidJSONObject(row),
              let data = try? JSONSerialization.data(withJSONObject: row),
              let doc = try? JSONDecoder().decode(NativeAPIClient.NoteDocument.self, from: data),
              !doc.id.isEmpty
        else { return nil }
        var next = doc
        next.schemaVersion = 1
        return next
    }

    private static func convertBlock(_ raw: Any) -> NativeAPIClient.LineBlock? {
        guard let row = raw as? [String: Any] else { return nil }
        let type = row["type"] as? String ?? "p"
        let id = ((row["id"] as? String).flatMap { $0.isEmpty ? nil : $0 }) ?? newId()
        if type == "speaker" {
            let speakerId = row["speakerId"] as? String ?? ""
            guard !speakerId.isEmpty else { return nil }
            let children = ((row["children"] as? [Any]) ?? []).compactMap(convertLine).prefix(80)
            let childBlocks = children.isEmpty
                ? [NativeAPIClient.LineBlock(
                    id: newId(), type: "paragraph", spans: [], speakerId: nil, title: nil, collapsed: nil, blocks: nil
                )]
                : Array(children)
            return NativeAPIClient.LineBlock(
                id: String(id.prefix(40)),
                type: "speakerSection",
                spans: nil,
                speakerId: String(speakerId.prefix(40)),
                title: row["title"] as? String,
                collapsed: row["collapsed"] as? Bool,
                blocks: childBlocks
            )
        }
        return convertLine(row)
    }

    private static func convertLine(_ raw: Any) -> NativeAPIClient.LineBlock? {
        guard let row = raw as? [String: Any] else { return nil }
        let legacyType = row["type"] as? String ?? "p"
        let docType: String
        switch legacyType {
        case "h": docType = "heading"
        case "ul": docType = "bullet"
        case "ol": docType = "numbered"
        case "paragraph", "heading", "bullet", "numbered": docType = legacyType
        default: docType = "paragraph"
        }
        let id = ((row["id"] as? String).flatMap { $0.isEmpty ? nil : $0 }) ?? newId()
        let spans: [NativeAPIClient.TextSpan]
        if let inlines = row["inlines"] as? [Any] {
            spans = inlines.compactMap(convertInline)
        } else if let existing = row["spans"] as? [Any] {
            spans = existing.compactMap { item -> NativeAPIClient.TextSpan? in
                guard JSONSerialization.isValidJSONObject(item),
                      let data = try? JSONSerialization.data(withJSONObject: item),
                      let span = try? JSONDecoder().decode(NativeAPIClient.TextSpan.self, from: data)
                else { return nil }
                return span
            }
        } else {
            spans = []
        }
        return NativeAPIClient.LineBlock(
            id: String(id.prefix(40)),
            type: docType,
            spans: spans,
            speakerId: nil,
            title: nil,
            collapsed: nil,
            blocks: nil
        )
    }

    private static func convertInline(_ raw: Any) -> NativeAPIClient.TextSpan? {
        guard let row = raw as? [String: Any] else { return nil }
        let type = row["type"] as? String ?? "text"
        if type == "ref" || type == "bibleRef" {
            guard let bookId = row["bookId"] as? String, let chapter = row["chapter"] as? Int else { return nil }
            return NativeAPIClient.TextSpan(
                type: "bibleRef",
                text: nil,
                marks: nil,
                bookId: bookId,
                chapter: chapter,
                verseStart: row["verseStart"] as? Int,
                verseEnd: row["verseEnd"] as? Int,
                href: nil
            )
        }
        if type == "link" {
            return NativeAPIClient.TextSpan(
                type: "link",
                text: row["text"] as? String,
                marks: nil,
                bookId: nil,
                chapter: nil,
                verseStart: nil,
                verseEnd: nil,
                href: row["href"] as? String
            )
        }
        let text = row["text"] as? String ?? ""
        var marks: [String] = []
        if row["bold"] as? Bool == true { marks.append("bold") }
        if row["italic"] as? Bool == true { marks.append("italic") }
        if let existing = row["marks"] as? [String] { marks.append(contentsOf: existing) }
        return NativeAPIClient.TextSpan(
            type: "text",
            text: text,
            marks: marks.isEmpty ? nil : Array(Set(marks)),
            bookId: nil,
            chapter: nil,
            verseStart: nil,
            verseEnd: nil,
            href: nil
        )
    }

    private static func sanitizeDay(_ raw: String?) -> String {
        if let raw, raw.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil {
            return raw
        }
        let day = ISO8601DateFormatter()
        day.formatOptions = [.withFullDate]
        return day.string(from: Date())
    }

    private static func newId() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }
}
