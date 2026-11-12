import XCTest
@testable import Katecheo

/// Ensures marketing screenshot mode stays launch-argument gated.
final class KatecheoScreenshotModeTests: XCTestCase {
    func testLaunchArgumentConstant() {
        XCTAssertEqual(KatecheoScreenshotMode.launchArgument, "-KatecheoScreenshotMode")
        XCTAssertEqual(KatecheoScreenshotMode.sceneLaunchArgument, "-KatecheoScreenshotScene")
    }

    func testIsEnabledRequiresLaunchArgument() {
        // Host unit tests never pass -KatecheoScreenshotMode.
        XCTAssertFalse(
            ProcessInfo.processInfo.arguments.contains(KatecheoScreenshotMode.launchArgument),
            "Unit-test host must not arm screenshot mode"
        )
        XCTAssertFalse(KatecheoScreenshotMode.isEnabled)
    }

    func testSceneFileStemsAreStable() {
        XCTAssertEqual(KatecheoScreenshotMode.Scene.notebook.fileStem, "01-caderno")
        XCTAssertEqual(KatecheoScreenshotMode.Scene.editor.fileStem, "02-editor")
        XCTAssertEqual(KatecheoScreenshotMode.Scene.lists.fileStem, "03-listas")
        XCTAssertEqual(KatecheoScreenshotMode.Scene.groups.fileStem, "04-grupos")
        XCTAssertEqual(KatecheoScreenshotMode.Scene.profile.fileStem, "05-perfil")
    }

    func testFixtureResponseNeverRequiresNetwork() throws {
        // Direct fixture builder — no URLSession.
        var request = URLRequest(url: URL(string: "https://katecheo.app/api/native/v1/notes")!)
        request.httpMethod = "GET"
        let (status, data, _) = try KatecheoScreenshotMode.fixtureResponse(for: request)
        XCTAssertEqual(status, 200)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?["ok"] as? Bool, true)
        XCTAssertNotNil(json?["notes"])
    }
}
