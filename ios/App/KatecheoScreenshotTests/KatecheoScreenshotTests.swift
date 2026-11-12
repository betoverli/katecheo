import XCTest

/// Captures App Store marketing screenshots (iPhone only).
/// Driven by CI via SCREENSHOT_OUTPUT_DIR / SCREENSHOT_LOCALE / SCREENSHOT_DEVICE_SLUG.
final class KatecheoScreenshotTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCaptureAppStoreScenes() throws {
        let env = ProcessInfo.processInfo.environment
        // Prefer TEST_RUNNER_-injected values (Xcode strips the prefix into XCTest).
        let locale = env["SCREENSHOT_LOCALE"] ?? "pt-BR"
        let deviceSlug = env["SCREENSHOT_DEVICE_SLUG"] ?? "iphone-16-pro"
        let root = env["SCREENSHOT_OUTPUT_DIR"]
            ?? (FileManager.default.temporaryDirectory
                .appendingPathComponent("katecheo-screenshots", isDirectory: true)
                .path)
        NSLog("[KatecheoScreenshotTests] locale=%@ device=%@ out=%@", locale, deviceSlug, root)
        let outDir = URL(fileURLWithPath: root, isDirectory: true)
            .appendingPathComponent(locale, isDirectory: true)
            .appendingPathComponent(deviceSlug, isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let (appleLanguages, appleLocale) = Self.appleLocaleArgs(for: locale)

        let scenes: [(name: String, stem: String)] = [
            ("notebook", "01-caderno"),
            ("editor", "02-editor"),
            ("lists", "03-listas"),
            ("groups", "04-grupos"),
            ("profile", "05-perfil"),
        ]

        for scene in scenes {
            let app = XCUIApplication()
            app.launchArguments = [
                "-KatecheoScreenshotMode",
                "-KatecheoScreenshotScene", scene.name,
                "-katecheoSkipOnboarding",
                "-AppleLanguages", "(\(appleLanguages))",
                "-AppleLocale", appleLocale,
            ]
            app.launch()

            let rootId = "screenshot.root.\(scene.name)"
            let marker = app.otherElements[rootId]
            // Some hosts expose the id on the VC view as Any / otherElements.
            let appeared =
                marker.waitForExistence(timeout: 12)
                || app.descendants(matching: .any).matching(identifier: rootId).firstMatch
                .waitForExistence(timeout: 4)
            XCTAssertTrue(appeared, "Scene \(scene.name) root (\(rootId)) should appear")

            // Extra settle so large titles / list cells / chips finish layout.
            RunLoop.current.run(until: Date().addingTimeInterval(1.2))

            let screenshot = app.screenshot()
            let fileURL = outDir.appendingPathComponent("\(scene.stem).png")
            try screenshot.pngRepresentation.write(to: fileURL)

            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = "\(locale)/\(deviceSlug)/\(scene.stem)"
            attachment.lifetime = .keepAlways
            add(attachment)

            app.terminate()
        }
    }

    private static func appleLocaleArgs(for locale: String) -> (String, String) {
        switch locale {
        case "en":
            return ("en", "en_US")
        case "es":
            return ("es", "es_ES")
        default:
            return ("pt-BR", "pt_BR")
        }
    }
}
