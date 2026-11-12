import XCTest
@testable import Katecheo

@MainActor
final class SettingsGuideTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        OnboardingStore.resetForTesting()
    }

    override func tearDown() async throws {
        OnboardingStore.markSeenForTesting()
        try await super.tearDown()
    }

    func testStore_settingsGuideFlagDefaultsToShowOnce() {
        OnboardingStore.resetForTesting()
        XCTAssertTrue(OnboardingStore.shouldShowSettingsGuide)
        XCTAssertFalse(OnboardingStore.hasSeenSettingsGuide)

        OnboardingStore.markSettingsGuideSeen()
        XCTAssertFalse(OnboardingStore.shouldShowSettingsGuide)
        XCTAssertTrue(OnboardingStore.hasSeenSettingsGuide)
    }

    func testStore_skipOnboardingAlsoSkipsSettingsGuideForCI() {
        OnboardingStore.resetForTesting()
        OnboardingStore.applyLaunchArgumentsIfNeeded(arguments: [OnboardingStore.skipLaunchArgument])
        XCTAssertTrue(OnboardingStore.hasSeenOnboarding)
        XCTAssertTrue(OnboardingStore.hasSeenSettingsGuide)
        XCTAssertFalse(OnboardingStore.shouldShowSettingsGuide)
    }

    func testStore_dedicatedSkipAndResetLaunchArgs() {
        OnboardingStore.resetForTesting()
        OnboardingStore.hasSeenSettingsGuide = true
        OnboardingStore.applyLaunchArgumentsIfNeeded(arguments: [
            OnboardingStore.resetSettingsGuideLaunchArgument,
        ])
        XCTAssertFalse(OnboardingStore.hasSeenSettingsGuide)
        XCTAssertTrue(OnboardingStore.shouldShowSettingsGuide)

        OnboardingStore.resetForTesting()
        OnboardingStore.applyLaunchArgumentsIfNeeded(arguments: [
            OnboardingStore.skipSettingsGuideLaunchArgument,
        ])
        XCTAssertTrue(OnboardingStore.hasSeenSettingsGuide)
    }

    func testPrefsDefaults_translationByDeviceLocale() {
        XCTAssertEqual(ProfileBibleCatalog.defaultTranslationId(for: "pt"), "nvi-pt")
        XCTAssertEqual(ProfileBibleCatalog.defaultTranslationId(for: "en"), "niv")
        XCTAssertEqual(ProfileBibleCatalog.defaultTranslationId(for: "es"), "rvr1960")
        XCTAssertEqual(ProfileBibleCatalog.defaultTranslationId(for: "fr"), "nvi-pt")
    }

    func testPrefsDefaults_canonicalTranslationMapsLegacyYouVersion() {
        XCTAssertEqual(ProfileBibleCatalog.canonicalTranslationId("111", locale: "en"), "niv")
        XCTAssertEqual(ProfileBibleCatalog.canonicalTranslationId("129", locale: "pt"), "nvi-pt")
        XCTAssertEqual(ProfileBibleCatalog.canonicalTranslationId("128", locale: "es"), "rvr1960")
        XCTAssertEqual(ProfileBibleCatalog.canonicalTranslationId("niv"), "niv")
        XCTAssertEqual(ProfileBibleCatalog.canonicalTranslationId("99999", locale: "en"), "niv")
        XCTAssertEqual(ProfileBibleCatalog.canonicalTranslationId("unknown", locale: "pt"), "nvi-pt")
    }

    func testGuide_defaultsSelectYouVersionAndLocaleTranslation() {
        let vc = SettingsGuideViewController()
        vc.loadViewIfNeeded()
        XCTAssertEqual(vc.testing_stepIndex, 0)
        XCTAssertEqual(vc.testing_selectedAppId, "youversion")
        XCTAssertEqual(
            vc.testing_selectedTranslationId,
            ProfileBibleCatalog.defaultTranslationId()
        )
        XCTAssertEqual(vc.testing_title, String(localized: "App de Bíblia"))
        XCTAssertFalse(vc.testing_isSecondaryVisible)
    }

    func testGuide_skipAdvancesAndMarksSeenOnLastStep() {
        // Without a bearer, prefs saves short-circuit and advance synchronously.
        XCTAssertFalse(NativeAPIClient.hasBearer)
        let vc = SettingsGuideViewController()
        var finished = false
        vc.onFinished = { finished = true }
        vc.loadViewIfNeeded()

        vc.testing_tapSkip()
        XCTAssertEqual(vc.testing_stepIndex, 1)
        XCTAssertEqual(vc.testing_title, String(localized: "Tradução"))

        vc.testing_tapSkip()
        XCTAssertEqual(vc.testing_stepIndex, 2)
        XCTAssertTrue(vc.testing_isSecondaryVisible)
        XCTAssertEqual(vc.testing_title, String(localized: "Notificações"))

        vc.testing_tapSecondary()
        XCTAssertTrue(OnboardingStore.hasSeenSettingsGuide)
        XCTAssertTrue(finished)
    }
}
