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

    func testUniversalDeviceFamily_inProject() throws {
        // iPhone simulators do not surface `UISupportedInterfaceOrientations~ipad` via
        // infoDictionary (device-family keys). Read the processed Info.plist / project instead.
        let orientations = Bundle.main.infoDictionary?["UISupportedInterfaceOrientations"] as? [String]
        XCTAssertNotNil(orientations)
        XCTAssertNil(Bundle.main.infoDictionary?["UIRequiresFullScreen"])
        let caps = Bundle.main.infoDictionary?["UIRequiredDeviceCapabilities"] as? [String]
        XCTAssertFalse(caps?.contains("armv7") == true)

        let bundleInfo = Bundle.main.bundleURL.appendingPathComponent("Info.plist")
        let sourceRoot = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceInfo = sourceRoot.appendingPathComponent("Katecheo/Info.plist")
        let projectURL = sourceRoot.appendingPathComponent("Katecheo.xcodeproj/project.pbxproj")

        var declaredIpadOrientations = false
        for url in [bundleInfo, sourceInfo] {
            guard let dict = NSDictionary(contentsOf: url) as? [String: Any],
                  let ipad = dict["UISupportedInterfaceOrientations~ipad"] as? [String]
            else { continue }
            XCTAssertEqual(ipad.count, 4, "iPad must support all 4 orientations")
            declaredIpadOrientations = true
            break
        }
        if let project = try? String(contentsOf: projectURL, encoding: .utf8) {
            XCTAssertTrue(
                project.contains("TARGETED_DEVICE_FAMILY = \"1,2\""),
                "project must target universal iPhone+iPad"
            )
            declaredIpadOrientations = declaredIpadOrientations
                || project.contains("TARGETED_DEVICE_FAMILY = \"1,2\"")
        }
        XCTAssertTrue(
            declaredIpadOrientations,
            "Universal app must declare iPad orientations and/or TARGETED_DEVICE_FAMILY = \"1,2\""
        )
    }
}
