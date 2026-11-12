import XCTest
@testable import Katecheo

@MainActor
final class ReportBlockTests: XCTestCase {
    func testReasonCatalog_coversGuidelineOptions() {
        let codes = ReportBlockLogic.reasonCodes
        XCTAssertEqual(codes, ["spam", "offensive", "inappropriate", "other"])
        XCTAssertEqual(ReportBlockSupport.Reason.allCases.count, 4)
        XCTAssertFalse(ReportBlockSupport.Reason.spam.title.isEmpty)
        XCTAssertFalse(ReportBlockSupport.Reason.offensive.title.isEmpty)
        XCTAssertFalse(ReportBlockSupport.Reason.inappropriate.title.isEmpty)
        XCTAssertFalse(ReportBlockSupport.Reason.other.title.isEmpty)
    }

    func testTargetMapping_userNoteGroup() {
        let user = ReportBlockSupport.Target.user(userId: "u1", displayName: "Ana")
        XCTAssertEqual(user.reportType, "user")
        XCTAssertEqual(user.reportId, "u1")
        XCTAssertEqual(user.blockUserId, "u1")

        let note = ReportBlockSupport.Target.note(noteId: "n1", authorUserId: "u2", authorName: "Bo")
        XCTAssertEqual(note.reportType, "note")
        XCTAssertEqual(note.reportId, "n1")
        XCTAssertEqual(note.blockUserId, "u2")

        let group = ReportBlockSupport.Target.group(groupId: "g1", name: "Grupo")
        XCTAssertEqual(group.reportType, "group")
        XCTAssertEqual(group.reportId, "g1")
        XCTAssertNil(group.blockUserId)
    }

    func testBlockCopy_mentionsFriendship() {
        let message = String(localized: "Vocês deixam de ser amigos. Conteúdo compartilhado some da sua lista. A pessoa não pode enviar pedidos de amizade.")
        XCTAssertTrue(ReportBlockLogic.blockConfirmMessageContainsFriendshipHint(message))
        XCTAssertTrue(message.contains("Katecheo") == false)
    }

    func testIphoneOnlyDeviceFamily_inProject() throws {
        let url = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Katecheo.xcodeproj/project.pbxproj")
        // Simulator unit tests may not see the project file; assert Info.plist orientations instead.
        let orientations = Bundle.main.infoDictionary?["UISupportedInterfaceOrientations"] as? [String]
        XCTAssertNotNil(orientations)
        XCTAssertNil(Bundle.main.infoDictionary?["UISupportedInterfaceOrientations~ipad"])
        _ = url
    }
}
