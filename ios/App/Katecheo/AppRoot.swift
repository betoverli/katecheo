import UIKit

/// Builds the window root. Phase 5: always native tabs — no Capacitor site host.
/// First launch shows onboarding before tabs (and before the auth screen).
enum AppRoot {
    static func makeRootViewController() -> UIViewController {
        if OnboardingStore.shouldShowOnLaunch {
            let onboarding = OnboardingViewController()
            onboarding.onFinished = {
                // Marked seen inside the VC; swap to the main shell.
                applyMainShell(animated: true)
            }
            return onboarding
        }
        return makeMainShell()
    }

    static func makeMainShell() -> UIViewController {
        NativeRootTabBarController()
    }

    /// After onboarding (or when forcing the signed-in shell), always land on tabs.
    static func applyMainShell(animated: Bool = true) {
        apply(makeMainShell(), animated: animated)
    }

    static func applyToKeyWindow(animated: Bool = true) {
        apply(makeRootViewController(), animated: animated)
    }

    private static func apply(_ next: UIViewController, animated: Bool) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        guard let window = scene?.windows.first(where: { $0.isKeyWindow }) ?? scene?.windows.first else {
            return
        }
        if animated {
            UIView.transition(with: window, duration: 0.28, options: .transitionCrossDissolve, animations: {
                window.rootViewController = next
            })
        } else {
            window.rootViewController = next
        }
    }
}
