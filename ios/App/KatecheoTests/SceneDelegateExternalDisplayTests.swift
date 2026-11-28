import XCTest
@testable import Katecheo

/// External-display / mirroring scenes must never get a Katecheo root UI
/// (Beto: second fullscreen light-mode copy on the monitor).
final class SceneDelegateExternalDisplayTests: XCTestCase {
    func testSceneDelegate_buildsRootUI_onlyForApplicationRole() {
        XCTAssertTrue(
            SceneDelegate.shouldBuildRootUI(for: .windowApplication),
            "Interactive application scenes must build the full root UI"
        )
    }

    func testSceneDelegate_rejectsExternalDisplayNonInteractiveRole() throws {
        if #available(iOS 16.0, *) {
            XCTAssertFalse(
                SceneDelegate.shouldBuildRootUI(for: .windowExternalDisplayNonInteractive),
                "External-display non-interactive / mirroring role must not build UI"
            )
        } else {
            throw XCTSkip("windowExternalDisplayNonInteractive requires iOS 16+")
        }
    }

    func testSceneDelegate_rejectsDeprecatedExternalDisplayRole() {
        XCTAssertFalse(
            SceneDelegate.shouldBuildRootUI(for: .windowExternalDisplay),
            "Deprecated external-display mirroring role must not build UI"
        )
    }

    func testInfoPlist_supportsMultipleScenes() throws {
        let supports = Bundle.main.infoDictionary?["UIApplicationSceneManifest"] as? [String: Any]
        let flag = supports?["UIApplicationSupportsMultipleScenes"] as? Bool
        // Prefer the processed bundle; fall back to source Info.plist beside the app.
        if let flag {
            XCTAssertTrue(flag, "UIApplicationSupportsMultipleScenes must be true for Stage Manager")
            return
        }
        let sourceRoot = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceInfo = sourceRoot.appendingPathComponent("Katecheo/Info.plist")
        let dict = try XCTUnwrap(NSDictionary(contentsOf: sourceInfo) as? [String: Any])
        let manifest = try XCTUnwrap(dict["UIApplicationSceneManifest"] as? [String: Any])
        let sourceFlag = try XCTUnwrap(manifest["UIApplicationSupportsMultipleScenes"] as? Bool)
        XCTAssertTrue(sourceFlag, "Info.plist UIApplicationSupportsMultipleScenes must be true")
    }

    func testInfoPlist_hasNoUIRequiresFullScreen() {
        XCTAssertNil(
            Bundle.main.infoDictionary?["UIRequiresFullScreen"],
            "UIRequiresFullScreen must stay absent (Split View / Stage Manager)"
        )
    }
}
