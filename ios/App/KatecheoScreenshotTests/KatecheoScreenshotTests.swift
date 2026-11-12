import XCTest

/// Captures App Store marketing screenshots (iPhone only).
/// Driven by CI via SCREENSHOT_OUTPUT_DIR / SCREENSHOT_LOCALE / SCREENSHOT_DEVICE_SLUG
/// (injected with the TEST_RUNNER_ prefix from xcodebuild).
final class KatecheoScreenshotTests: XCTestCase {
    override func setUpWithError() throws {
        // Keep going across scenes so one slow frame does not abort the whole matrix.
        continueAfterFailure = true
    }

    func testCaptureAppStoreScenes() throws {
        let env = ProcessInfo.processInfo.environment
        let locale = env["SCREENSHOT_LOCALE"] ?? "pt-BR"
        let deviceSlug = env["SCREENSHOT_DEVICE_SLUG"] ?? "iphone-16-pro"
        let root = env["SCREENSHOT_OUTPUT_DIR"]
            ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("katecheo-screenshots", isDirectory: true)
            .path
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

        var wrote = 0
        for scene in scenes {
            let app = XCUIApplication()
            app.launchArguments = [
                "-KatecheoScreenshotMode",
                "-KatecheoScreenshotScene", scene.name,
                "-katecheoSkipOnboarding",
                "-AppleLanguages", "(\(appleLanguages))",
                "-AppleLocale", appleLocale,
                // Cut spring animations that keep the app from going idle.
                "-UIViewAnimationDragCoefficient", "0.001",
            ]
            app.launch()

            // Scene routing is launch-arg driven — fixed settle beats accessibility idle waits
            // (those hung for minutes on the second simulator in CI).
            RunLoop.current.run(until: Date().addingTimeInterval(2.5))

            let screenshot = XCUIScreen.main.screenshot()
            let fileURL = outDir.appendingPathComponent("\(scene.stem).png")
            do {
                try screenshot.pngRepresentation.write(to: fileURL)
                wrote += 1
                NSLog("[KatecheoScreenshotTests] wrote %@", fileURL.path)
            } catch {
                XCTFail("Failed to write \(fileURL.lastPathComponent): \(error)")
            }

            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = "\(locale)/\(deviceSlug)/\(scene.stem)"
            attachment.lifetime = .keepAlways
            add(attachment)

            app.terminate()
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        }

        XCTAssertEqual(wrote, scenes.count, "Expected \(scenes.count) PNGs under \(outDir.path)")
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
