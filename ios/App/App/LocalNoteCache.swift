import Foundation

/// On-device mirror of `NoteDocumentV1` lists for offline read / quick paint.
enum LocalNoteCache {
    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("NativeNotes", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var notesURL: URL { directory.appendingPathComponent("notes-v1.json") }
    private static var speakersURL: URL { directory.appendingPathComponent("speakers-v1.json") }

    static func saveNotes(_ notes: [NativeAPIClient.NoteDocument]) {
        guard let data = try? JSONEncoder().encode(notes) else { return }
        try? data.write(to: notesURL, options: .atomic)
    }

    static func loadNotes() -> [NativeAPIClient.NoteDocument] {
        guard let data = try? Data(contentsOf: notesURL),
              let notes = try? JSONDecoder().decode([NativeAPIClient.NoteDocument].self, from: data)
        else { return [] }
        return notes
    }

    static func upsertNote(_ note: NativeAPIClient.NoteDocument) {
        var notes = loadNotes()
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes[index] = note
        } else {
            notes.insert(note, at: 0)
        }
        notes.sort { lhs, rhs in
            if lhs.happenedAt != rhs.happenedAt { return lhs.happenedAt > rhs.happenedAt }
            return lhs.updatedAt > rhs.updatedAt
        }
        saveNotes(notes)
    }

    static func removeNote(id: String) {
        var notes = loadNotes()
        notes.removeAll { $0.id == id }
        saveNotes(notes)
    }

    static func saveSpeakers(_ speakers: [NativeAPIClient.SpeakerDTO]) {
        guard let data = try? JSONEncoder().encode(speakers) else { return }
        try? data.write(to: speakersURL, options: .atomic)
    }

    /// Merge into the on-device catalog without wiping unrelated speakers.
    /// `getNote` returns only speakers used by that note — replacing the cache
    /// with that subset emptied the picker (TF200 #3).
    @discardableResult
    static func mergeSpeakers(_ speakers: [NativeAPIClient.SpeakerDTO]) -> [NativeAPIClient.SpeakerDTO] {
        var byId: [String: NativeAPIClient.SpeakerDTO] = [:]
        for speaker in loadSpeakers() { byId[speaker.id] = speaker }
        for speaker in speakers { byId[speaker.id] = speaker }
        let merged = byId.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        saveSpeakers(merged)
        return merged
    }

    static func removeSpeaker(id: String) {
        var speakers = loadSpeakers()
        speakers.removeAll { $0.id == id }
        saveSpeakers(speakers)
    }

    static func loadSpeakers() -> [NativeAPIClient.SpeakerDTO] {
        guard let data = try? Data(contentsOf: speakersURL),
              let speakers = try? JSONDecoder().decode([NativeAPIClient.SpeakerDTO].self, from: data)
        else { return [] }
        return speakers
    }
}
