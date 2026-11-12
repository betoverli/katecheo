import Foundation

/// Persists first-launch intro + post-sign-in settings guide completion.
/// Keys are Katecheo-prefixed (`katecheo.*`) to match other UserDefaults flags.
enum OnboardingStore {
    static let hasSeenKey = "katecheo.hasSeenOnboarding.v1"
    static let hasSeenSettingsGuideKey = "katecheo.hasSeenSettingsGuide.v1"

    /// Process launch arg so existing UI / host tests can skip the intro and keep passing.
    static let skipLaunchArgument = "-katecheoSkipOnboarding"
    /// Optional: force a clean first-launch path (clears the seen flag).
    static let resetLaunchArgument = "-katecheoResetOnboarding"
    /// Skip the post-sign-in settings guide (CI / UI tests).
    static let skipSettingsGuideLaunchArgument = "-katecheoSkipSettingsGuide"
    /// Force the settings guide to show again.
    static let resetSettingsGuideLaunchArgument = "-katecheoResetSettingsGuide"

    private static var launchArgumentsApplied = false

    static var hasSeenOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: hasSeenKey) }
        set { UserDefaults.standard.set(newValue, forKey: hasSeenKey) }
    }

    /// Once per account/device — Bible app, translation, notifications setup after sign-in.
    static var hasSeenSettingsGuide: Bool {
        get { UserDefaults.standard.bool(forKey: hasSeenSettingsGuideKey) }
        set { UserDefaults.standard.set(newValue, forKey: hasSeenSettingsGuideKey) }
    }

    /// Apply once per process from `ProcessInfo` launch arguments.
    static func applyLaunchArgumentsIfNeeded(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) {
        guard !launchArgumentsApplied else { return }
        launchArgumentsApplied = true
        if arguments.contains(resetLaunchArgument) {
            hasSeenOnboarding = false
        }
        if arguments.contains(skipLaunchArgument) {
            hasSeenOnboarding = true
            // UI / host tests that skip the intro also skip the settings guide.
            hasSeenSettingsGuide = true
        }
        if arguments.contains(resetSettingsGuideLaunchArgument) {
            hasSeenSettingsGuide = false
        }
        if arguments.contains(skipSettingsGuideLaunchArgument) {
            hasSeenSettingsGuide = true
        }
    }

    /// Whether cold start should show the intro (before auth / tabs).
    static var shouldShowOnLaunch: Bool {
        applyLaunchArgumentsIfNeeded()
        return !hasSeenOnboarding
    }

    /// Whether the signed-in shell should present the short settings guide.
    static var shouldShowSettingsGuide: Bool {
        applyLaunchArgumentsIfNeeded()
        return !hasSeenSettingsGuide
    }

    static func markSeen() {
        hasSeenOnboarding = true
    }

    static func markSettingsGuideSeen() {
        hasSeenSettingsGuide = true
    }

    /// Test / Settings helpers — reset without requiring a process relaunch.
    static func resetForTesting() {
        hasSeenOnboarding = false
        hasSeenSettingsGuide = false
        launchArgumentsApplied = false
    }

    static func markSeenForTesting() {
        hasSeenOnboarding = true
        hasSeenSettingsGuide = true
        launchArgumentsApplied = false
    }

    static func resetSettingsGuideForTesting() {
        hasSeenSettingsGuide = false
        launchArgumentsApplied = false
    }

    static func markSettingsGuideSeenForTesting() {
        hasSeenSettingsGuide = true
        launchArgumentsApplied = false
    }
}
