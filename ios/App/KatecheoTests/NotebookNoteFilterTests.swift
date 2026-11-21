import XCTest
@testable import Katecheo

@MainActor
final class NotebookNoteFilterTests: XCTestCase {
    private func note(
        id: String,
        tags: [String] = [],
        noteSpeakerId: String? = nil,
        sectionSpeakerIds: [String] = []
    ) -> NativeAPIClient.NoteDocument {
        var doc = NativeAPIClient.emptyNote(id: id)
        doc.tags = tags
        doc.noteSpeakerId = noteSpeakerId
        if !sectionSpeakerIds.isEmpty {
            doc.body.blocks = sectionSpeakerIds.map { speakerId in
                NativeAPIClient.LineBlock(
                    id: "sec-\(speakerId)",
                    type: "speakerSection",
                    spans: [],
                    speakerId: speakerId,
                    title: nil,
                    collapsed: nil,
                    checked: nil,
                    blocks: [
                        NativeAPIClient.LineBlock(
                            id: "p-\(speakerId)",
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
            }
        }
        return doc
    }

    func testMatchesTags_anyOfSelected() {
        let a = note(id: "a", tags: ["culto", "manhã"])
        let b = note(id: "b", tags: ["estudo"])
        let c = note(id: "c", tags: [])

        XCTAssertTrue(NotebookNoteFilter.matchesTags(a, selectedTags: ["culto", "noite"]))
        XCTAssertTrue(NotebookNoteFilter.matchesTags(b, selectedTags: ["estudo", "culto"]))
        XCTAssertFalse(NotebookNoteFilter.matchesTags(b, selectedTags: ["culto"]))
        XCTAssertFalse(NotebookNoteFilter.matchesTags(c, selectedTags: ["culto"]))
        XCTAssertTrue(NotebookNoteFilter.matchesTags(c, selectedTags: []), "empty selection = no tag constraint")
    }

    func testMatchesSpeakers_anyOfSelected_noteOrSection() {
        let main = note(id: "m", noteSpeakerId: "sp1")
        let section = note(id: "s", sectionSpeakerIds: ["sp2"])
        let both = note(id: "b", noteSpeakerId: "sp1", sectionSpeakerIds: ["sp2"])
        let none = note(id: "n")

        XCTAssertTrue(NotebookNoteFilter.matchesSpeakers(main, selectedSpeakerIds: ["sp1", "sp9"]))
        XCTAssertTrue(NotebookNoteFilter.matchesSpeakers(section, selectedSpeakerIds: ["sp2"]))
        XCTAssertTrue(NotebookNoteFilter.matchesSpeakers(both, selectedSpeakerIds: ["sp2"]))
        XCTAssertFalse(NotebookNoteFilter.matchesSpeakers(none, selectedSpeakerIds: ["sp1"]))
        XCTAssertTrue(NotebookNoteFilter.matchesSpeakers(none, selectedSpeakerIds: []))
    }

    func testMatchesCombined_requiresTagAndSpeakerWhenBothSet() {
        let match = note(id: "1", tags: ["culto"], noteSpeakerId: "sp1")
        let tagOnly = note(id: "2", tags: ["culto"], noteSpeakerId: "sp9")
        let speakerOnly = note(id: "3", tags: ["estudo"], noteSpeakerId: "sp1")
        let neither = note(id: "4", tags: ["x"], noteSpeakerId: "sp9")

        let tags: Set = ["culto"]
        let speakers: Set = ["sp1"]

        XCTAssertTrue(NotebookNoteFilter.matchesCombined(match, selectedTags: tags, selectedSpeakerIds: speakers))
        XCTAssertFalse(NotebookNoteFilter.matchesCombined(tagOnly, selectedTags: tags, selectedSpeakerIds: speakers))
        XCTAssertFalse(NotebookNoteFilter.matchesCombined(speakerOnly, selectedTags: tags, selectedSpeakerIds: speakers))
        XCTAssertFalse(NotebookNoteFilter.matchesCombined(neither, selectedTags: tags, selectedSpeakerIds: speakers))

        // Only tags set → speaker unconstrained.
        XCTAssertTrue(NotebookNoteFilter.matchesCombined(tagOnly, selectedTags: tags, selectedSpeakerIds: []))
        // Only speakers set → tag unconstrained.
        XCTAssertTrue(NotebookNoteFilter.matchesCombined(speakerOnly, selectedTags: [], selectedSpeakerIds: speakers))
    }

    func testFilterNotes_tagsModeWithoutSelection_showsAnyTagged() {
        let notes = [
            note(id: "a", tags: ["a"]),
            note(id: "b", tags: []),
            note(id: "c", tags: ["c"]),
        ]
        let filtered = NotebookNoteFilter.filterNotes(
            notes,
            mode: .tags,
            selectedTags: [],
            selectedSpeakerIds: []
        )
        XCTAssertEqual(filtered.map(\.id), ["a", "c"])
    }

    func testFilterNotes_multiTagAny_andSpeakerAnd() {
        let notes = [
            note(id: "1", tags: ["culto"], noteSpeakerId: "sp1"),
            note(id: "2", tags: ["estudo"], noteSpeakerId: "sp1"),
            note(id: "3", tags: ["culto"], noteSpeakerId: "sp2"),
            note(id: "4", tags: ["noite"], noteSpeakerId: "sp1"),
        ]
        let filtered = NotebookNoteFilter.filterNotes(
            notes,
            mode: .all,
            selectedTags: ["culto", "estudo"],
            selectedSpeakerIds: ["sp1"]
        )
        XCTAssertEqual(Set(filtered.map(\.id)), Set(["1", "2"]))
    }

    func testFilterNotes_sharedBase_stillAppliesSelections() {
        let owned = note(id: "owned", tags: ["culto"], noteSpeakerId: "sp1")
        let granted = note(id: "granted", tags: ["culto"], noteSpeakerId: "sp1")
        let grantedOther = note(id: "other", tags: ["x"], noteSpeakerId: "sp1")
        let filtered = NotebookNoteFilter.filterNotes(
            [owned],
            mode: .shared,
            selectedTags: ["culto"],
            selectedSpeakerIds: ["sp1"],
            grantedNotes: [granted, grantedOther]
        )
        XCTAssertEqual(filtered.map(\.id), ["granted"])
    }
}
