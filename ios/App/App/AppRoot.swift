import UIKit

/// Builds the window root. Phase 5: always native tabs — no Capacitor site host.
enum AppRoot {
    static func makeRootViewController() -> UIViewController {
        NativeRootTabBarController()
    }

    static func applyToKeyWindow(animated: Bool = true) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        guard let window = scene?.windows.first(where: { $0.isKeyWindow }) ?? scene?.windows.first else {
            return
        }
        let next = makeRootViewController()
        if animated {
            UIView.transition(with: window, duration: 0.28, options: .transitionCrossDissolve, animations: {
                window.rootViewController = next
            })
        } else {
            window.rootViewController = next
        }
    }
}
