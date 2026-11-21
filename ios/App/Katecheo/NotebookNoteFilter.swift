import Foundation

/// Pure Caderno list filter rules — multi-tag ANY, multi-speaker ANY, combined with AND.
enum NotebookNoteFilter {
    enum Mode: String, Equatable {
        case all
        case tags
        case speakers
        case shared
    }

    /// Tag constraint: empty set means no tag filter; otherwise note must include **any** selected tag.
    static func matchesTags(_ note: NativeAPIClient.NoteDocument, selectedTags: Set<String>) -> Bool {
        guard !selectedTags.isEmpty else { return true }
        return note.tags.contains { selectedTags.contains($0) }
    }

    /// Speaker constraint: empty set means no speaker filter; otherwise note must include **any** selected speaker.
    static func matchesSpeakers(
        _ note: NativeAPIClient.NoteDocument,
        selectedSpeakerIds: Set<String>
    ) -> Bool {
        guard !selectedSpeakerIds.isEmpty else { return true }
        return selectedSpeakerIds.contains { includesSpeaker(note, speakerId: $0) }
    }

    /// Combined: tag filter AND speaker filter when both are set.
    static func matchesCombined(
        _ note: NativeAPIClient.NoteDocument,
        selectedTags: Set<String>,
        selectedSpeakerIds: Set<String>
    ) -> Bool {
        matchesTags(note, selectedTags: selectedTags)
            && matchesSpeakers(note, selectedSpeakerIds: selectedSpeakerIds)
    }

    static func includesSpeaker(_ note: NativeAPIClient.NoteDocument, speakerId: String) -> Bool {
        if note.noteSpeakerId == speakerId { return true }
        return note.body.blocks.contains { block in
            block.type == "speakerSection" && block.speakerId == speakerId
        }
    }

    static func hasAnySpeaker(_ note: NativeAPIClient.NoteDocument) -> Bool {
        if note.noteSpeakerId != nil { return true }
        return note.body.blocks.contains { $0.type == "speakerSection" }
    }

    /// Applies chip mode + multi-select constraints. Shared mode uses `grantedNotes` as the base set.
    static func filterNotes(
        _ notes: [NativeAPIClient.NoteDocument],
        mode: Mode,
        selectedTags: Set<String>,
        selectedSpeakerIds: Set<String>,
        grantedNotes: [NativeAPIClient.NoteDocument] = []
    ) -> [NativeAPIClient.NoteDocument] {
        var source: [NativeAPIClient.NoteDocument]
        switch mode {
        case .all:
            source = notes
        case .shared:
            source = grantedNotes
        case .tags:
            source = notes
            if selectedTags.isEmpty {
                // Browsing Tags with no pick yet → notes that have at least one tag.
                source = source.filter { !$0.tags.isEmpty }
            }
        case .speakers:
            source = notes
            if selectedSpeakerIds.isEmpty {
                source = source.filter { hasAnySpeaker($0) }
            }
        }

        return source.filter {
            matchesCombined($0, selectedTags: selectedTags, selectedSpeakerIds: selectedSpeakerIds)
        }
    }
}
