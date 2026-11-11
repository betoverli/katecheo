import Foundation

/// Persists whether the first-launch intro has been completed.
/// Key is Katecheo-prefixed (`katecheo.*`) to match other UserDefaults flags.
enum OnboardingStore {
    static let hasSeenKey = "katecheo.hasSeenOnboarding.v1"

    /// Process launch arg so existing UI / host tests can skip the intro and keep passing.
    static let skipLaunchArgument = "-katecheoSkipOnboarding"
    /// Optional: force a clean first-launch path (clears the seen flag).
    static let resetLaunchArgument = "-katecheoResetOnboarding"

    private static var launchArgumentsApplied = false

    static var hasSeenOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: hasSeenKey) }
        set { UserDefaults.standard.set(newValue, forKey: hasSeenKey) }
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
        }
    }

    /// Whether cold start should show the intro (before auth / tabs).
    static var shouldShowOnLaunch: Bool {
        applyLaunchArgumentsIfNeeded()
        return !hasSeenOnboarding
    }

    static func markSeen() {
        hasSeenOnboarding = true
    }

    /// Test / Settings helpers — reset without requiring a process relaunch.
    static func resetForTesting() {
        hasSeenOnboarding = false
        launchArgumentsApplied = false
    }

    static func markSeenForTesting() {
        hasSeenOnboarding = true
        launchArgumentsApplied = false
    }
}
